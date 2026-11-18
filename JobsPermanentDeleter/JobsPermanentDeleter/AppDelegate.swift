//
//  AppDelegate.swift
//  JobsPermanentDeleter
//
//  Created by Jobs on 2026年11月18日，星期三.
//

import AppKit

final class AppDelegate: NSObject,
                         NSApplicationDelegate {

    // Keep an in-flight recursive deletion alive until its result is visible.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        return PermanentDeleteController.busy ? .terminateCancel : .terminateNow
    }

    private var pending: [PermanentDeleteRequest] = []
    private var handled: Set<UUID> = []
    private var running = false
    private var launched = false
    private var generation = 0

    func applicationWillFinishLaunching(_ notification: Notification) {
        PermanentDeleteInterface.installEditingMenu()
        NSAppleEventManager.shared().setEventHandler(self,
                                                     andSelector: #selector(openURL(_:withReplyEvent:)),
                                                     forEventClass: AEEventClass(kInternetEventClass),
                                                     andEventID: AEEventID(kAEGetURL))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        launched = true
        drain()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            enqueue(url)
        }
    }

    @objc private func openURL(_ event: NSAppleEventDescriptor,
                               withReplyEvent reply: NSAppleEventDescriptor) {
        guard let raw = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: raw) else {
            return
        }
        enqueue(url)
    }

    private func enqueue(_ url: URL) {
        guard let request = PermanentDeleteRequest(url: url) else {
            PermanentDeleteInterface.show(warning: true) {
                return PermanentDeleteLocalization.text("invalidTarget")
            }
            drain()
            return
        }
        // macOS may deliver one request through both URL callbacks.
        guard handled.insert(request.identifier).inserted else {
            return
        }
        pending.append(request)
        generation += 1
        drain()
    }

    private func drain() {
        guard launched, !running else {
            return
        }
        running = true
        while !pending.isEmpty {
            PermanentDeleteController().run(pending.removeFirst())
        }
        running = false
        generation += 1
        let current = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            guard current == self.generation, !self.running, self.pending.isEmpty else {
                return
            }
            NSApp.terminate(nil)
        }
    }
}
