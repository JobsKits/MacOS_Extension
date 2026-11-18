//
//  AppDelegate.swift
//  JobsEnvironmentUpdater
//
//  Created by Jobs on 2026年11月17日，星期二.
//

import AppKit

final class AppDelegate: NSObject,
                         NSApplicationDelegate {

    private var handledRequests: Set<UUID> = []
    private var didFinishLaunching = false
    private var exitGeneration = 0
    var launchUpdate: () throws -> Void = {
        try EnvironmentUpdateTerminalLauncher.open()
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
            guard let request = EnvironmentUpdateRequest(url: url),
                  handledRequests.insert(request.identifier).inserted else {
                continue
            }
            do {
                try launchUpdate()
            } catch {
                NSAlert.showEnvironmentUpdateFailure(error.localizedDescription)
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
