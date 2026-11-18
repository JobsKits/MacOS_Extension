//
//  AppDelegate.swift
//  JobsSendTo
//
//  Created by Jobs on 2026年11月18日，星期三.
//

import AppKit

final class AppDelegate: NSObject,
                         NSApplicationDelegate {

    private var handled: Set<UUID> = []
    private var pending: [SendToRequest] = []
    private var controllers: [UUID: SendToWindowController] = [:]
    private var launched = false
    private var recoveryController: SendToRecoveryWindowController?
    private var terminationPending = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        SendToAppMenu.install()
        NSAppleEventManager.shared().setEventHandler(self,
                                                     andSelector: #selector(openURL(_:withReplyEvent:)),
                                                     forEventClass: AEEventClass(kInternetEventClass),
                                                     andEventID: AEEventID(kAEGetURL))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        launched = true
        for request in pending {
            present(request)
        }
        pending.removeAll()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            guard self.controllers.isEmpty else {
                return
            }
            self.showRecovery(nil)
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard !terminationPending else {
            return
        }
        for url in urls {
            guard let request = SendToRequest(url: url), handled.insert(request.identifier).inserted else {
                continue
            }
            if launched {
                present(request)
            } else {
                pending.append(request)
            }
        }
    }

    @objc private func openURL(_ event: NSAppleEventDescriptor,
                               withReplyEvent reply: NSAppleEventDescriptor) {
        guard let value = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: value) else {
            return
        }
        application(NSApplication.shared, open: [url])
    }

    private func present(_ request: SendToRequest?) {
        guard !terminationPending else {
            return
        }
        let identifier = request?.identifier ?? UUID()
        let controller = SendToWindowController(request: request)
        configure(controller, identifier: identifier)
        controllers[identifier] = controller
        controller.show()
    }

    private func configure(_ controller: SendToWindowController, identifier: UUID) {
        controller.onClose = { [weak self] in
            self?.controllers.removeValue(forKey: identifier)
            if self?.controllers.isEmpty == true && self?.recoveryController == nil {
                NSApp.terminate(nil)
            }
        }
        controller.onShowRecovery = { [weak self] in
            self?.showRecovery(nil)
        }
        controller.onBusyChanged = { [weak self] in
            guard let self else {
                return
            }
            self.recoveryController?.refresh()
            self.finishTerminationIfReady()
        }
    }

    @objc func showRecovery(_ sender: Any?) {
        if let recoveryController {
            recoveryController.focus()
            recoveryController.refresh()
            return
        }
        let recovery = SendToRecoveryWindowController()
        recovery.onResume = { [weak self] task in
            guard let self, !self.terminationPending else {
                return
            }
            if let active = self.controllers.values.first(where: {
                return $0.taskIdentifier == task.id
            }) {
                active.continueTask(task)
                return
            }
            let identifier = UUID()
            let controller = SendToWindowController(task: task)
            self.configure(controller, identifier: identifier)
            self.controllers[identifier] = controller
            controller.show()
        }
        recovery.onClose = { [weak self] in
            self?.recoveryController = nil
            if self?.controllers.isEmpty == true {
                NSApp.terminate(nil)
            }
        }
        recovery.onBusyChanged = { [weak self] in
            self?.finishTerminationIfReady()
        }
        recoveryController = recovery
        recovery.show()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showRecovery(nil)
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let busy = controllers.values.filter(\.isBusy)
        guard busy.isEmpty && recoveryController?.isBusy != true else {
            terminationPending = true
            for controller in busy {
                controller.cancel()
            }
            return .terminateLater
        }
        return .terminateNow
    }

    private func finishTerminationIfReady() {
        guard terminationPending,
              recoveryController?.isBusy != true,
              !controllers.values.contains(where: \.isBusy) else {
            return
        }
        terminationPending = false
        NSApp.reply(toApplicationShouldTerminate: true)
    }
}
