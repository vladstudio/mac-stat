import Foundation
import IOKit

struct Stats {
    var cpuLoad: Int = 0
    var gpuLoad: Int = 0
    var downloadBytesPerSec: UInt64 = 0
    var uploadBytesPerSec: UInt64 = 0

    var downloadDisplay: (value: String, isMega: Bool) {
        let kbps = downloadBytesPerSec / 1024
        if kbps >= 1000 {
            return (String(format: "%.2f", Double(kbps) / 1024.0), true)
        }
        return ("\(kbps)", false)
    }

    var uploadDisplay: (value: String, isMega: Bool) {
        let kbps = uploadBytesPerSec / 1024
        if kbps >= 1000 {
            return (String(format: "%.2f", Double(kbps) / 1024.0), true)
        }
        return ("\(kbps)", false)
    }
}

@MainActor
final class SystemStats {
    private let hostPort = mach_host_self()
    private var prevCPUInfo: processor_info_array_t?
    private var prevCPUCount: mach_msg_type_number_t = 0
    private var prevNetIn: UInt64 = 0
    private var prevNetOut: UInt64 = 0
    private var hasBaseline = false

    func invalidateBaseline() {
        hasBaseline = false
        if let prev = prevCPUInfo {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: prev), vm_size_t(prevCPUCount) * vm_size_t(MemoryLayout<integer_t>.stride))
            prevCPUInfo = nil
        }
    }

    func read() -> Stats {
        var stats = Stats()
        stats.cpuLoad = readCPU()
        stats.gpuLoad = readGPU()
        let (netIn, netOut) = readNetBytes()
        if hasBaseline {
            stats.downloadBytesPerSec = netIn > prevNetIn ? netIn - prevNetIn : 0
            stats.uploadBytesPerSec = netOut > prevNetOut ? netOut - prevNetOut : 0
        }
        prevNetIn = netIn
        prevNetOut = netOut
        hasBaseline = true
        return stats
    }

    // MARK: - CPU

    private func readCPU() -> Int {
        var numCPUs: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var cpuInfoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(
            hostPort,
            PROCESSOR_CPU_LOAD_INFO,
            &numCPUs,
            &cpuInfo,
            &cpuInfoCount
        )
        guard result == KERN_SUCCESS, let cpuInfo else { return 0 }

        var totalUser: Int64 = 0, totalSystem: Int64 = 0, totalIdle: Int64 = 0, totalNice: Int64 = 0
        var prevTotalUser: Int64 = 0, prevTotalSystem: Int64 = 0, prevTotalIdle: Int64 = 0, prevTotalNice: Int64 = 0

        for i in 0..<Int(numCPUs) {
            let offset = Int(CPU_STATE_MAX) * i
            totalUser += Int64(cpuInfo[offset + Int(CPU_STATE_USER)])
            totalSystem += Int64(cpuInfo[offset + Int(CPU_STATE_SYSTEM)])
            totalIdle += Int64(cpuInfo[offset + Int(CPU_STATE_IDLE)])
            totalNice += Int64(cpuInfo[offset + Int(CPU_STATE_NICE)])

            if let prev = prevCPUInfo {
                prevTotalUser += Int64(prev[offset + Int(CPU_STATE_USER)])
                prevTotalSystem += Int64(prev[offset + Int(CPU_STATE_SYSTEM)])
                prevTotalIdle += Int64(prev[offset + Int(CPU_STATE_IDLE)])
                prevTotalNice += Int64(prev[offset + Int(CPU_STATE_NICE)])
            }
        }

        var load = 0
        if let _ = prevCPUInfo {
            let userDelta = totalUser - prevTotalUser
            let systemDelta = totalSystem - prevTotalSystem
            let idleDelta = totalIdle - prevTotalIdle
            let niceDelta = totalNice - prevTotalNice
            let total = userDelta + systemDelta + idleDelta + niceDelta
            if total > 0 {
                load = Int(((Double(userDelta + systemDelta + niceDelta)) / Double(total)) * 100)
            }
        }

        if let prev = prevCPUInfo {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: prev), vm_size_t(prevCPUCount) * vm_size_t(MemoryLayout<integer_t>.stride))
        }
        prevCPUInfo = cpuInfo
        prevCPUCount = cpuInfoCount

        return load
    }

    // MARK: - GPU

    private func readGPU() -> Int {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOAccelerator")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return 0 }
        defer { IOObjectRelease(iterator) }

        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dict = props?.takeRetainedValue() as? [String: Any],
               let perfStats = dict["PerformanceStatistics"] as? [String: Any] {
                let util = gpuUtil(from: perfStats)
                IOObjectRelease(entry)
                return util
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }
        return 0
    }

    private func gpuUtil(from stats: [String: Any]) -> Int {
        if let v = stats["GPU Activity(%)"] as? Int { return v }
        if let v = stats["Device Utilization %"] as? Int { return v }
        if let v = stats["GPU Core Utilization"] as? Int { return v }
        if let v = stats["gpuCoreUtilizationComponent"] as? Int { return v / 1_000_000 }
        for (key, value) in stats where key.contains("tilization") || key.contains("Activity") {
            if let v = value as? Int { return v > 100_000 ? v / 1_000_000 : v }
        }
        return 0
    }

    // MARK: - Network

    private func readNetBytes() -> (UInt64, UInt64) {
        var mib = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var len: size_t = 0
        guard sysctl(&mib, 6, nil, &len, nil, 0) == 0 else { return (0, 0) }
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: len)
        defer { buf.deallocate() }
        guard sysctl(&mib, 6, buf, &len, nil, 0) == 0 else { return (0, 0) }

        var totalIn: UInt64 = 0, totalOut: UInt64 = 0
        var ptr = UnsafeMutableRawPointer(buf)
        let end = ptr + len
        while ptr < end {
            let hdr = ptr.assumingMemoryBound(to: if_msghdr.self).pointee
            if hdr.ifm_type == RTM_IFINFO2 {
                let hdr2 = ptr.assumingMemoryBound(to: if_msghdr2.self).pointee
                if hdr2.ifm_data.ifi_type != UInt8(IFT_LOOP) {
                    totalIn += hdr2.ifm_data.ifi_ibytes
                    totalOut += hdr2.ifm_data.ifi_obytes
                }
            }
            ptr += Int(hdr.ifm_msglen)
        }
        return (totalIn, totalOut)
    }
}
