//
//  AppDelegate.swift
//  JobsIOSTools
//
//  Created by Jobs on 2026年10月23日，星期五.
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = IOSToolsModel()
    private var pendingOperations = 0
    private var acceptedRequests = Set<String>()
    private var didFinishLaunching = false
    private var idleWorkItem: DispatchWorkItem?
    private var idleGeneration = 0

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleOpenURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
        model.record("宿主启动，URL 接收器已注册。")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        didFinishLaunching = true
        if CommandLine.arguments.contains("--initialize-finder-extension") {
            beginOperation()
            model.enableExtension { [weak self] in
                self?.finishOperation()
            }
        } else {
            scheduleExitIfIdle()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard urls.count == 1, let request = urls.first else {
            model.record("无法识别 Finder 请求，已停止。")
            scheduleExitIfIdle()
            return
        }
        handleRequest(request)
    }

    @objc private func handleOpenURL(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        guard let value = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let request = URL(string: value) else {
            model.record("无法识别 Finder 请求，已停止。")
            scheduleExitIfIdle()
            return
        }
        handleRequest(request)
    }

    private func handleRequest(_ request: URL) {
        guard let projectURL = IOSToolsRequest.projectURL(from: request),
              let action = IOSToolsRequest.action(from: request) else {
            model.record("无法识别 Finder 请求，已停止。")
            scheduleExitIfIdle()
            return
        }
        let identity = action.rawValue + "\0" + projectURL.standardizedFileURL.path
        guard acceptedRequests.insert(identity).inserted else {
            model.record("忽略重复的 Finder 请求：本次宿主已派发相同项目与动作。")
            return
        }
        // 两种系统 URL 回调共享同一入口；先记账，异步完成后仍不重复打开终端。
        model.record("收到 Finder 项目请求：\(projectURL.path)")
        beginOperation()
        model.diagnose(projectURL, action: action) { [weak self] in
            self?.finishOperation()
        }
    }

    private func beginOperation() {
        idleGeneration += 1
        idleWorkItem?.cancel()
        idleWorkItem = nil
        pendingOperations += 1
    }

    private func finishOperation() {
        pendingOperations -= 1
        scheduleExitIfIdle()
    }

    private func scheduleExitIfIdle() {
        guard didFinishLaunching, pendingOperations == 0 else {
            return
        }
        idleGeneration += 1
        let generation = idleGeneration
        idleWorkItem?.cancel()
        // 给冷启动与紧接的 Finder 请求留出派发窗口，不截断尚未返回的 osascript。
        let workItem = DispatchWorkItem.make { [weak self] in
            guard let self, self.pendingOperations == 0,
                  self.idleGeneration == generation else {
                return
            }
            self.model.record("后台初始化与所有终端派发已完成，宿主退出。")
            NSApp.terminate(nil)
        }
        idleWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: workItem)
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
}
