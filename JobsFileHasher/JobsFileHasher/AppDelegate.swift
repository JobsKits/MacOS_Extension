//
//  AppDelegate.swift
//  JobsFileHasher
//
//  Created by Jobs on 2026年11月6日，星期五.
//

import AppKit

final class AppDelegate: NSObject,
                         NSApplicationDelegate {

    private var handledRequests: Set<UUID> = []
    private var didFinishLaunching = false
    private var exitGeneration = 0

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(self,
                                                     andSelector: #selector(handleURL(_:withReplyEvent:)),
                                                     forEventClass: AEEventClass(kInternetEventClass),
                                                     andEventID: AEEventID(kAEGetURL))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        didFinishLaunching = true
        scheduleExit()
    }

    func application(_ application: NSApplication,
                     open urls: [URL]) {
        for url in urls {
            handle(url)
        }
    }

    @objc private func handleURL(_ event: NSAppleEventDescriptor,
                                 withReplyEvent reply: NSAppleEventDescriptor) {
        guard let value = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: value) else {
            return
        }
        handle(url)
    }

    private func handle(_ url: URL) {
        defer {
            scheduleExit()
        }
        guard let request = FileHashRequest(url: url) else {
            showFailure("请求格式无效或所选文件已变化，请重新打开右键菜单。")
            return
        }
        // 冷启动时同一 URL 可能经过两个系统回调，按点击 ID 去重。
        guard handledRequests.insert(request.identifier).inserted else {
            return
        }
        do {
            try FileHashTerminalLauncher.open(request.fileURL)
        } catch {
            showFailure(error.localizedDescription)
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

    private func showFailure(_ details: String) {
        NSAlert.make(message: "无法查看文件指纹", details: details).runModal()
    }
}
