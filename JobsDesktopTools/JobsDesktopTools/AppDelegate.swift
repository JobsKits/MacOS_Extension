//
//  AppDelegate.swift
//  JobsDesktopTools
//
//  Created by Jobs on 2026年10月26日，星期一.
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var pendingOperations = 0
    private var didFinishLaunching = false
    private var idleGeneration = 0
    private var recentRequests: [String: Date] = [:]

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(self,
            andSelector: #selector(handleOpenURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        didFinishLaunching = true
        scheduleExit()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach(handle)
    }

    @objc private func handleOpenURL(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let value = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: value) else {
            return
        }
        handle(url)
    }

    private func handle(_ url: URL) {
        guard let request = DesktopMenuRequest(url: url),
              DesktopMenuConfiguration.enabledFeatures().contains(request.action) else {
            DesktopAlert.show("桌面功能已关闭，或请求不在固定动作白名单中，请重新右键。")
            scheduleExit()
            return
        }
        let now = Date()
        recentRequests = recentRequests.filter { now.timeIntervalSince($0.value) < 1 }
        guard recentRequests[url.absoluteString] == nil else {
            return
        }
        recentRequests[url.absoluteString] = now
        pendingOperations += 1
        idleGeneration += 1
        DispatchQueue.global(qos: .userInitiated).async {
            var failure: String?
            do {
                try DesktopActionExecutor().perform(request)
            } catch {
                failure = error.localizedDescription
            }
            let message = failure
            DispatchQueue.main.async {
                if let message {
                    DesktopAlert.show(message)
                }
                self.pendingOperations -= 1
                self.scheduleExit()
            }
        }
    }

    private func scheduleExit() {
        guard didFinishLaunching, pendingOperations == 0 else {
            return
        }
        idleGeneration += 1
        let generation = idleGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            guard self.pendingOperations == 0, generation == self.idleGeneration else {
                return
            }
            NSApp.terminate(nil)
        }
    }
}
