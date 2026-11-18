//
//  AppDelegate.swift
//  JobsDiskSpaceInfo
//
//  Created by Jobs on 2026年11月15日，星期日.
//

import AppKit

final class AppDelegate: NSObject,
                         NSApplicationDelegate {

    private var handledRequests: Set<UUID> = []
    private var didFinishLaunching = false
    private var exitGeneration = 0
    var launchCleanup: () throws -> Void = {
        try DiskCleanupTerminalLauncher.open()
    }

    static func make() -> AppDelegate {
        return AppDelegate()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(self,
                                                   andSelector: #selector(handleURL(_:withReplyEvent:)),
                                                   forEventClass: AEEventClass(kInternetEventClass),
                                                   andEventID: AEEventID(kAEGetURL))
    }

    @objc private func handleURL(_ event: NSAppleEventDescriptor,
                                 withReplyEvent reply: NSAppleEventDescriptor) {
        guard let value = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: value) else {
            return
        }
        application(NSApplication.shared, open: [url])
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        didFinishLaunching = true
        scheduleExit()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            defer {
                scheduleExit()
            }
            guard let request = DiskCleanupRequest(url: url),
                  handledRequests.insert(request.identifier).inserted else {
                continue
            }
            do {
                try launchCleanup()
            } catch {
                NSAlert.showDiskCleanupFailure(error.localizedDescription)
            }
        }
    }

    private func scheduleExit() {
        guard didFinishLaunching else {
            return
        }
        exitGeneration += 1
        let generation = exitGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            guard generation == self.exitGeneration else {
                return
            }
            NSApp.terminate(nil)
        }
    }
}

extension NSApplication {

    @discardableResult
    func byDelegate(_ value: NSApplicationDelegate) -> Self {
        delegate = value
        return self
    }
}
