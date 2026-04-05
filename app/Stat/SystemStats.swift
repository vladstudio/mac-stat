import Foundation
import IOKit

struct Stats {
    var cpuLoad: Int = 0
    var gpuLoad: Int = 0
    var downloadBytesPerSec: UInt64 = 0
    var uploadBytesPerSec: UInt64 = 0

    var downloadDisplay: (value: Int, isMega: Bool) {
        let kbps = downloadBytesPerSec / 1024
        if kbps >= 1000 {
            return (Int(kbps / 1024), true)
        }
        return (Int(kbps), false)
    }

    var uploadDisplay: (value: Int, isMega: Bool) {
        let kbps = uploadBytesPerSec / 1024
        if kbps >= 1000 {
            return (Int(kbps / 1024), true)
        }
        return (Int(kbps), false)
    }
}

@MainActor
final class SystemStats {
    private var prevCPUInfo: processor_info_array_t?
    private var prevCPUCount: mach_msg_type_number_t = 0
    private var prevNetIn: UInt64 = 0
    private var prevNetOut: UInt64 = 0
    private var hasBaseline = false

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
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCPUs,
            &cpuInfo,
            &cpuInfoCount
        )
        guard result == KERN_SUCCESS, let cpuInfo else { return 0 }

        var totalUser: Int32 = 0, totalSystem: Int32 = 0, totalIdle: Int32 = 0, totalNice: Int32 = 0
        var prevTotalUser: Int32 = 0, prevTotalSystem: Int32 = 0, prevTotalIdle: Int32 = 0, prevTotalNice: Int32 = 0

        for i in 0..<Int(numCPUs) {
            let offset = Int(CPU_STATE_MAX) * i
            totalUser += cpuInfo[offset + Int(CPU_STATE_USER)]
            totalSystem += cpuInfo[offset + Int(CPU_STATE_SYSTEM)]
            totalIdle += cpuInfo[offset + Int(CPU_STATE_IDLE)]
            totalNice += cpuInfo[offset + Int(CPU_STATE_NICE)]

            if let prev = prevCPUInfo {
                prevTotalUser += prev[offset + Int(CPU_STATE_USER)]
                prevTotalSystem += prev[offset + Int(CPU_STATE_SYSTEM)]
                prevTotalIdle += prev[offset + Int(CPU_STATE_IDLE)]
                prevTotalNice += prev[offset + Int(CPU_STATE_NICE)]
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

        var entry: io_registry_entry_t = IOIteratorNext(iterator)
        while entry != 0 {
            defer { IOObjectRelease(entry); entry = IOIteratorNext(iterator) }
            var props: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dict = props?.takeRetainedValue() as? [String: Any] else { continue }

            if let perfStats = dict["PerformanceStatistics"] as? [String: Any] {
                // Try known keys for GPU utilization
                if let util = perfStats["GPU Activity(%)"] as? Int { return util }
                if let util = perfStats["Device Utilization %"] as? Int { return util }
                if let util = perfStats["GPU Core Utilization"] as? Int { return util }
                // Some drivers report as a 0-100_000_000 range
                if let util = perfStats["gpuCoreUtilizationComponent"] as? Int { return util / 10_000_00 }
            }
        }
        return 0
    }

    // MARK: - Network

    private func readNetBytes() -> (UInt64, UInt64) {
        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return (0, 0) }
        defer { freeifaddrs(ifaddr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let addr = ptr {
            let name = String(cString: addr.pointee.ifa_name)
            // Skip loopback
            if addr.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_LINK) && name != "lo0" {
                if let data = addr.pointee.ifa_data {
                    let networkData = data.assumingMemoryBound(to: if_data.self).pointee
                    totalIn += UInt64(networkData.ifi_ibytes)
                    totalOut += UInt64(networkData.ifi_obytes)
                }
            }
            ptr = addr.pointee.ifa_next
        }
        return (totalIn, totalOut)
    }
}
