//
//  AppDelegate.swift
//  JobsFileCreator
//
//  Created by Jobs on 2026年10月29日，星期四.
//

import AppKit

final class AppDelegate: NSObject,
                         NSApplicationDelegate {

    private var pendingRequests: [FileCreationRequest] = []
    private var handledRequests: Set<UUID> = []
    private var isRunning = false
    private var didFinishLaunching = false
    private var idleGeneration = 0

    func applicationWillFinishLaunching(_ notification: Notification) {
        FileCreatorInterface.installEditingMenu()
        NSAppleEventManager.shared().setEventHandler(self,
                                                     andSelector: #selector(handleOpenURL(_:withReplyEvent:)),
                                                     forEventClass: AEEventClass(kInternetEventClass),
                                                     andEventID: AEEventID(kAEGetURL))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        didFinishLaunching = true
        drainRequests()
    }

    func application(_ application: NSApplication,
                     open urls: [URL]) {
        for url in urls {
            enqueue(url)
        }
    }

    @objc private func handleOpenURL(_ event: NSAppleEventDescriptor,
                                     withReplyEvent reply: NSAppleEventDescriptor) {
        guard let value = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: value) else {
            return
        }
        enqueue(url)
    }

    private func enqueue(_ url: URL) {
        guard let request = FileCreationRequest(url: url) else {
            FileCreatorInterface.showFailure("目标目录已失效或请求格式不正确，请重新打开右键菜单。")
            scheduleExit()
            return
        }
        // 同一点击可能同时经过两条系统 URL 回调，只展示一次写入对话框。
        guard handledRequests.insert(request.identifier).inserted else {
            return
        }
        pendingRequests.append(request)
        idleGeneration += 1
        drainRequests()
    }

    private func drainRequests() {
        guard didFinishLaunching,
              !isRunning else {
            return
        }
        isRunning = true
        while !pendingRequests.isEmpty {
            let request = pendingRequests.removeFirst()
            FileCreationController().run(in: request.directoryURL)
        }
        isRunning = false
        scheduleExit()
    }

    private func scheduleExit() {
        guard didFinishLaunching,
              !isRunning,
              pendingRequests.isEmpty else {
            return
        }
        idleGeneration += 1
        let generation = idleGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            guard generation == self.idleGeneration,
                  !self.isRunning,
                  self.pendingRequests.isEmpty else {
                return
            }
            NSApp.terminate(nil)
        }
    }
}
