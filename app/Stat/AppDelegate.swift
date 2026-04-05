import Cocoa
import MacAppKit

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var statusView: StatusItemView!
    private var systemStats: SystemStats!
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        systemStats = SystemStats()
        LoginItem.enableOnFirstLaunch(key: "stat.loginItemEnabled")

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        statusView = StatusItemView(frame: NSRect(x: 0, y: 0, width: 150, height: 22))
        statusItem.button?.addSubview(statusView)
        statusItem.button?.frame = statusView.frame

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(NSMenuItem(title: "Start on Login", action: #selector(toggleLogin), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Check for Updates…", action: #selector(checkUpdates), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Stat", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) {
            item.target = self
        }
        statusItem.menu = menu

        // Initial read (establishes baseline for network deltas)
        statusView.stats = systemStats.read()

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.statusView.stats = self.systemStats.read()
                self.statusItem.length = self.statusView.frame.width
            }
        }
    }

    @objc private func toggleLogin(_ sender: NSMenuItem) {
        LoginItem.toggle()
        sender.state = LoginItem.isEnabled ? .on : .off
    }

    @objc private func checkUpdates(_ sender: NSMenuItem) {
        UpdateChecker.check(repo: "nickvdyck/stat", appName: "Stat", manual: true)
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        if let loginItem = menu.items.first {
            loginItem.state = LoginItem.isEnabled ? .on : .off
        }
    }
}
