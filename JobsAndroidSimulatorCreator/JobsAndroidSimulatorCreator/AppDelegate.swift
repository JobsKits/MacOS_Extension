//
//  AppDelegate.swift
//  JobsAndroidSimulatorCreator
//
//  Created by Jobs on 2026年10月22日，星期四.
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AndroidSimulatorModel()
    private var pendingOperations = 0
    private var didAcceptCreateRequest = false
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
        model.record("后台宿主启动，URL 接收器已注册。")
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
            rejectRequest()
            return
        }
        handleRequest(request)
    }

    @objc private func handleOpenURL(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        guard let value = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let request = URL(string: value) else {
            rejectRequest()
            return
        }
        handleRequest(request)
    }

    private func handleRequest(_ request: URL) {
        guard AndroidSimulatorRequest.isCreateRequest(request) else {
            rejectRequest()
            return
        }
        guard !didAcceptCreateRequest else {
            model.record("忽略重复的新建 Android 模拟器请求：本次宿主已接收过创建动作。")
            return
        }
        // 派发完成后宿主即将退出，期间收到的重复事件也不能再次打开终端。
        didAcceptCreateRequest = true
        model.record("收到 Finder 新建 Android 模拟器请求。")
        beginOperation()
        model.createSimulator { [weak self] in
            self?.finishOperation()
        }
    }

    private func rejectRequest() {
        model.record("请求不是受支持的新建模拟器动作，已停止。")
        scheduleExitIfIdle()
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
        // 冷启动时给紧接的 URL 事件留出派发窗口，终端交接未完成时保持宿主存活。
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.pendingOperations == 0,
                  self.idleGeneration == generation else {
                return
            }
            self.model.record("初始化与终端派发已完成，后台宿主退出。")
            NSApp.terminate(nil)
        }
        idleWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: workItem)
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
}
