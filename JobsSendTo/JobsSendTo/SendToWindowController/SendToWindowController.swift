//
//  SendToWindowController.swift
//  JobsSendTo
//
//  Created by Jobs on 2026年11月18日，星期三.
//

import AppKit

final class SendToWindowController: NSObject,
                                   NSWindowDelegate,
                                   NSOpenSavePanelDelegate {

    private static var activeRequests = Set<String>()

    private let request: SendToRequest?
    private var recoveryTask: SendToTaskSummary?
    private var volumes: [SendToVolume] = []
    private var scanGeneration = 0
    private var scanning = false
    private var token = SendToCancellation()
    private var result: SendToResult?
    private var progress: SendToProgress?
    private var scanError: String?
    private var noApplicableTargets = false
    private(set) var isBusy = false
    private var closeAfterPause = false
    private var selectedFolder: SendToVolume?
    private var selectedRootID: String?
    private var folderRoot: SendToVolume?
    private var folderPanel: NSOpenPanel?
    private var folderError: String?
    private var preparingSelection = false
    private var requestKey: String?
    private var repeatAlert: NSAlert?
    private var repeatPicker: NSPopUpButton?
    private var repeatMatches: [SendToTaskMatch] = []
    private var activeDestination: SendToVolume?
    private var reconnecting = false
    private var reconnectGeneration = 0
    private var reconnectText: String?
    private var reconnectDiagnostic: String?
    private var pendingRestart: SendToTaskMatch?
    private lazy var reconnect = SendToReconnectController(dependencies: .live(openShare: { url, completion in
        DispatchQueue.main.async {
            completion(NSWorkspace.shared.open(url))
        }
    }))
    var confirmPrevious: ((NSAlert) -> NSApplication.ModalResponse)?
    var onClose: (() -> Void)?
    var onBusyChanged: (() -> Void)?
    var onShowRecovery: (() -> Void)?

    var taskIdentifier: UUID? {
        return recoveryTask?.id ?? result?.taskID
    }

    private lazy var window = NSWindow.makeSendToWindow(delegate: self)
    private lazy var content = NSView.makeSendToView()
    private lazy var heading = NSTextField.makeSendToLabel(large: true)
    private lazy var scope = NSTextField.makeSendToLabel()
    private lazy var sourceHeading = NSTextField.makeSendToLabel()
    private lazy var sourceText = NSTextView.makeSendToTextView()
    private lazy var sourceScroll = NSScrollView.makeSendToScroll(text: sourceText)
    private lazy var destinationHeading = NSTextField.makeSendToLabel()
    private lazy var destination = NSPopUpButton.make(frame: .zero)
    private lazy var folderText = NSTextView.makeSendToTextView()
    private lazy var folderScroll = NSScrollView.makeSendToScroll(text: folderText)
    private lazy var folderButton = NSButton.makeSendToButton(target: self, action: #selector(chooseFolder(_:)))
    private lazy var reload = NSButton.makeSendToButton(target: self, action: #selector(reloadVolumes(_:)))
    private lazy var empty = NSTextField.makeSendToLabel()
    private lazy var status = NSTextField.makeSendToLabel()
    private lazy var current = NSTextField.makeSendToLabel()
    private lazy var activity = NSProgressIndicator.makeSendToActivity()
    private lazy var copyButton = NSButton.makeSendToButton(target: self, action: #selector(copySelected(_:)))
    private lazy var cancelButton = NSButton.makeSendToButton(target: self, action: #selector(cancelSelected(_:)))
    private lazy var recoveryButton = NSButton.makeSendToButton(target: self, action: #selector(showRecovery(_:)))
    private lazy var language = NSPopUpButton.make(frame: .zero)
    private lazy var theme = NSPopUpButton.make(frame: .zero)
    private lazy var languageLabel = NSTextField.makeSendToLabel()
    private lazy var themeLabel = NSTextField.makeSendToLabel()

    init(request: SendToRequest?) {
        self.request = request
        super.init()
    }

    init(task: SendToTaskSummary) {
        self.request = nil
        self.recoveryTask = task
        super.init()
    }

    func focus() {
        window.bySendToShow()
        NSApp.activate(ignoringOtherApps: true)
    }

    func continueTask(_ task: SendToTaskSummary) {
        focus()
        guard !isBusy else {
            return
        }
        recoveryTask = task
        startResume(task.id)
    }

    func show() {
        language.byItems([SendToLocalization.text("system")] + SendToLocalization.languageNames)
            .bySelectedIndex((["system"] + SendToLocalization.languages).firstIndex(of: SendToLocalization.defaults.string(forKey: "language") ?? "system") ?? 0)
            .byTarget(self)
            .byAction(#selector(languageChanged(_:)))
        theme.byItems(["system", "light", "dark"].map(SendToLocalization.text))
            .bySelectedIndex(["system", "light", "dark"].firstIndex(of: SendToLocalization.defaults.string(forKey: "theme") ?? "system") ?? 0)
            .byTarget(self)
            .byAction(#selector(themeChanged(_:)))
        destination.byTarget(self)
            .byAction(#selector(destinationChanged(_:)))
        for view in [heading, scope, sourceHeading, sourceScroll, destinationHeading, destination, folderScroll, folderButton, reload, empty,
                     status, current, activity, copyButton, cancelButton, recoveryButton, language, theme, languageLabel, themeLabel] {
            content.bySendToAddSubview(view)
        }
        window.bySendToContentView(content)
        updateText()
        layout()
        window.bySendToShow()
        NSApp.activate(ignoringOtherApps: true)
        if let task = recoveryTask {
            volumes = [task.destination]
            rebuildDestinations()
            startResume(task.id)
        } else if let destination = request?.destination {
            volumes = [destination]
            selectedRootID = destination.identifier
            rebuildDestinations()
            updateText()
        } else {
            reloadVolumes(nil)
        }
        if request != nil {
            offerPreviousRequest()
        }
    }

    func windowDidResize(_ notification: Notification) {
        layout()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !isBusy else {
            closeAfterPause = true
            cancel()
            return false
        }
        return true
    }

    func windowWillClose(_ notification: Notification) {
        scanGeneration += 1
        releaseRequest()
        onClose?()
    }

    func cancel() {
        guard isBusy else {
            return
        }
        token.cancel()
        if reconnecting {
            reconnectGeneration += 1
            reconnect.cancel()
            reconnecting = false
            isBusy = false
            reconnectText = SendToLocalization.text("reconnectPaused")
            releaseRequest()
            onBusyChanged?()
            if closeAfterPause {
                window.close()
            }
        }
        updateText()
    }

    @objc private func reloadVolumes(_ sender: Any?) {
        guard !isBusy else {
            return
        }
        scanGeneration += 1
        let generation = scanGeneration
        scanning = true
        scanError = nil
        updateText()
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = Result {
                let all = try SendToCore.volumes()
                guard let request = self.request else {
                    return (all, false)
                }
                let suitable = all.filter {
                    return SendToCore.canCopy(sources: request.sources, destination: $0)
                }
                return (suitable, !all.isEmpty && suitable.isEmpty)
            }
            DispatchQueue.main.async {
                guard generation == self.scanGeneration else {
                    return
                }
                self.scanning = false
                switch outcome {
                /// Replace the snapshot only with a completed mounted-volume scan.
                case .success(let values):
                    self.volumes = values.0
                    self.noApplicableTargets = values.1
                /// A failed scan has an explicit empty state and a reload action.
                case .failure(let error):
                    self.volumes = []
                    self.noApplicableTargets = false
                    self.scanError = error.localizedDescription
                }
                self.rebuildDestinations()
                self.updateText()
            }
        }
    }

    private func rebuildDestinations() {
        destination.bySendToReplaceItems(volumes.map {
            if let task = recoveryTask, task.destination == $0 {
                return SendToLocalization.taskDestination(task)
            }
            return $0.name + " — " + $0.url.path
        })
            .bySelectedIndex(volumes.firstIndex(where: { $0.identifier == selectedRootID }) ?? 0)
        selectedRootID = volumes.indices.contains(destination.indexOfSelectedItem) ? volumes[destination.indexOfSelectedItem].identifier : nil
        if let selectedFolder, !volumes.contains(where: {
            $0.url == selectedFolder.volumeURL && $0.identity == selectedFolder.volumeIdentity
        }) {
            self.selectedFolder = nil
        }
    }

    @objc private func destinationChanged(_ sender: Any?) {
        selectedRootID = volumes.indices.contains(destination.indexOfSelectedItem) ? volumes[destination.indexOfSelectedItem].identifier : nil
        selectedFolder = nil
        folderError = nil
        updateText()
    }

    @objc private func chooseFolder(_ sender: Any?) {
        if result?.resumeAvailable == true, activeDestination?.isNetwork == true {
            connectShare()
            return
        }
        guard !isBusy, !scanning, !preparingSelection, volumes.indices.contains(destination.indexOfSelectedItem) else {
            return
        }
        let root = volumes[destination.indexOfSelectedItem]
        folderRoot = root
        let directory = selectedFolder?.url ?? root.url
        let panel = NSOpenPanel.makeSendToFolderPanel(directory: directory,
                                                      message: SendToLocalization.text("chooseFolderScope") + "\n" + root.url.path,
                                                      prompt: SendToLocalization.text("chooseFolder"), delegate: self)
        folderPanel = panel
        panel.beginSheetModal(for: window) { response in
            self.folderPanel = nil
            self.folderRoot = nil
            guard response == .OK, let folder = panel.url else {
                return
            }
            self.acceptFolder(folder, root: root)
        }
    }

    func panel(_ sender: Any, shouldEnable url: URL) -> Bool {
        guard let root = folderRoot else {
            return false
        }
        return url.path == root.url.path || url.path.hasPrefix(root.url.path + "/")
    }

    func panel(_ sender: Any, validate url: URL) throws {
        guard panel(sender, shouldEnable: url) else {
            throw NSError(domain: "JobsSendTo", code: 3,
                           userInfo: [NSLocalizedDescriptionKey: SendToLocalization.text("chooseFolderScope")])
        }
    }

    private func acceptFolder(_ folder: URL, root: SendToVolume) {
        preparingSelection = true
        folderError = nil
        updateText()
        DispatchQueue.global(qos: .userInitiated).async {
            let selection = Result {
                return try SendToCore.selectedDirectory(root: root, folder: folder.standardizedFileURL)
            }
            DispatchQueue.main.async {
                self.preparingSelection = false
                guard self.volumes.indices.contains(self.destination.indexOfSelectedItem),
                      self.volumes[self.destination.indexOfSelectedItem] == root else {
                    self.updateText()
                    return
                }
                switch selection {
                case .success(let target):
                    self.selectedFolder = target
                case .failure(let error):
                    self.folderError = error.localizedDescription
                }
                self.updateText()
            }
        }
    }

    @objc private func copySelected(_ sender: Any?) {
        if let identifier = taskIdentifier, result?.resumeAvailable == true {
            reconnect.resetRetryBudget(taskID: identifier)
            if let pendingRestart {
                startRestart(pendingRestart)
            } else {
                startResume(identifier)
            }
            return
        }
        guard volumes.indices.contains(destination.indexOfSelectedItem) else {
            return
        }
        startCopy(selectedFolder ?? volumes[destination.indexOfSelectedItem])
    }

    private func offerPreviousRequest() {
        guard let request, !isBusy else {
            return
        }
        isBusy = true
        preparingSelection = true
        token = SendToCancellation()
        let preparationToken = token
        updateText()
        onBusyChanged?()
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = Result {
                return try SendToCore.matchingTasks(sources: request.sources, cancel: { preparationToken.isCancelled })
            }
            DispatchQueue.main.async {
                self.isBusy = false
                self.preparingSelection = false
                guard !preparationToken.isCancelled else {
                    self.updateText()
                    self.onBusyChanged?()
                    if self.closeAfterPause { self.window.close() }
                    return
                }
                switch outcome {
                case .success(let matches):
                    if matches.isEmpty {
                        self.updateText()
                        self.onBusyChanged?()
                    } else {
                        self.resolvePrevious(matches, destination: nil)
                    }
                case .failure(let error):
                    self.folderError = error.localizedDescription
                    self.updateText()
                    self.onBusyChanged?()
                }
            }
        }
    }

    private func claimRequest(_ destination: SendToVolume) -> Bool {
        guard requestKey == nil, let request else {
            return requestKey != nil
        }
        let key = destination.identifier + "|" + request.sources.map {
            $0.url.path + "|" + String($0.identity.ino)
        }.sorted().joined(separator: "|")
        guard Self.activeRequests.insert(key).inserted else {
            folderError = SendToLocalization.text("transferAlreadyActive")
            updateText()
            return false
        }
        requestKey = key
        return true
    }

    private func startCopy(_ destination: SendToVolume, replacing: SendToTaskMatch? = nil, matched: Bool = false) {
        guard !isBusy, let request else {
            return
        }
        guard claimRequest(destination) else {
            return
        }
        if let replacing {
            pendingRestart = replacing
            startRestart(replacing)
            return
        }
        if !matched {
            isBusy = true
            preparingSelection = true
            token = SendToCancellation()
            let preparationToken = token
            updateText()
            onBusyChanged?()
            DispatchQueue.global(qos: .userInitiated).async {
                let outcome = Result {
                    let target = try SendToCore.selectedDirectory(root: destination, folder: destination.url,
                                                                   expectedInode: destination.identity.ino)
                    return (target, try SendToCore.matchingTasks(sources: request.sources, destination: target,
                                                                cancel: { preparationToken.isCancelled }))
                }
                DispatchQueue.main.async {
                    self.preparingSelection = false
                    self.isBusy = false
                    guard !preparationToken.isCancelled else {
                        self.releaseRequest()
                        self.updateText()
                        self.onBusyChanged?()
                        if self.closeAfterPause {
                            self.window.close()
                        }
                        return
                    }
                    switch outcome {
                    case .success(let (target, matches)):
                        if !matches.isEmpty {
                            self.resolvePrevious(matches, destination: target)
                        } else {
                            self.startCopy(target, matched: true)
                        }
                    case .failure(let error):
                        self.folderError = error.localizedDescription
                        self.releaseRequest()
                        self.updateText()
                        self.onBusyChanged?()
                    }
                }
            }
            return
        }
        activeDestination = destination
        beginOperation { token, emit in
            let currentDestination: SendToVolume
            do {
                currentDestination = try SendToCore.selectedDirectory(root: destination, folder: destination.url,
                                                                      expectedInode: destination.identity.ino)
            } catch {
                return SendToResult(successes: [], failures: [SendToFailure(source: nil, code: "destination", message: error.localizedDescription)], cancelled: token.isCancelled)
            }
            return SendToCore.copy(sources: request.sources, destination: currentDestination,
                                    cancel: {
                return token.isCancelled
            }, progress: emit)
        }
    }

    private func startRestart(_ match: SendToTaskMatch) {
        guard !isBusy, let request else {
            return
        }
        pendingRestart = match
        activeDestination = match.summary.destination
        beginOperation { token, emit in
            do {
                let target = try SendToCore.resolvedDestination(taskID: match.summary.id)
                guard !token.isCancelled, SendToCore.canCopy(sources: request.sources, destination: target) else {
                    if token.isCancelled { throw SendToCoreError.cancelled }
                    throw SendToCoreError.rejected("重新传输前源或目标已变化，旧断点保留。")
                }
                guard !token.isCancelled else { throw SendToCoreError.cancelled }
                try SendToCore.discard(taskID: match.summary.id)
                return SendToCore.copy(sources: request.sources, destination: target,
                                       cancel: { token.isCancelled }, progress: emit)
            } catch {
                let systemCode: Int32?
                if case SendToCoreError.system(_, _, let code) = error {
                    systemCode = code
                } else {
                    systemCode = nil
                }
                let cancelled: Bool
                if case SendToCoreError.cancelled = error { cancelled = true } else { cancelled = token.isCancelled }
                return SendToResult(failures: cancelled ? [] : [SendToFailure(source: nil, code: "restart", message: error.localizedDescription,
                                                                               systemCode: systemCode)],
                                    cancelled: cancelled, taskID: match.summary.id, resumeAvailable: true)
            }
        }
    }

    private func releaseRequest() {
        if let requestKey {
            Self.activeRequests.remove(requestKey)
            self.requestKey = nil
        }
    }

    private func makeRepeatAlert(_ matches: [SendToTaskMatch], destination: SendToVolume?) -> NSAlert {
        let alert = NSAlert.make()
            .byMessageText(SendToLocalization.text("previousTransfer"))
            .byInformativeText(SendToLocalization.text("previousTransferScope") + "\n\n" +
                                 (destination?.url.path ?? (matches.count == 1 ? matches[0].summary.destination.url.path : "")))
            .byAlertStyle(.warning)
            .byAddButton(SendToLocalization.text("cancelChoice"))
            .byAddButton(SendToLocalization.text("continuePrevious"))
            .byAddButton(SendToLocalization.text("restartTransfer"))
        alert.buttons[2].bySendToDestructive(true)
        if matches.count > 1 {
            let picker = NSPopUpButton.make(frame: NSRect(x: 0, y: 0, width: 540, height: 30))
                .byItems([SendToLocalization.text("choosePreviousTask")] + matches.map {
                    $0.summary.id.uuidString + " · " + $0.summary.updatedAt.description
                })
                .byTarget(self)
                .byAction(#selector(previousTaskChanged(_:)))
            repeatPicker = picker
            alert.byAccessoryView(picker)
            alert.buttons[1].bySendToEnabled(false)
            alert.buttons[2].bySendToEnabled(false)
        } else if let match = matches.first {
            alert.buttons[1].bySendToEnabled(match.canResume)
            alert.buttons[2].bySendToEnabled(match.canRestart)
            if let reason = match.reason {
                alert.byInformativeText(alert.informativeText + "\n\n" + reason)
            }
        }
        return alert
    }

    @objc private func previousTaskChanged(_ sender: NSPopUpButton) {
        guard let alert = repeatAlert else {
            return
        }
        let index = sender.indexOfSelectedItem - 1
        let match = repeatMatches.indices.contains(index) ? repeatMatches[index] : nil
        alert.buttons[1].bySendToEnabled(match?.canResume == true)
        alert.buttons[2].bySendToEnabled(match?.canRestart == true)
        alert.byInformativeText(SendToLocalization.text("previousTransferScope") + "\n\n" +
                                 (match?.summary.destination.url.path ?? "") + (match?.reason.map { "\n\n" + $0 } ?? ""))
    }

    private func resolvePrevious(_ matches: [SendToTaskMatch], destination: SendToVolume?) {
        repeatMatches = matches
        repeatPicker = nil
        let alert = makeRepeatAlert(matches, destination: destination)
        repeatAlert = alert
        let answer = confirmPrevious?(alert) ?? alert.runModal()
        let index = matches.count == 1 ? 0 : (repeatPicker?.indexOfSelectedItem ?? 0) - 1
        let match = matches.indices.contains(index) ? matches[index] : nil
        repeatAlert = nil
        repeatPicker = nil
        repeatMatches = []
        if answer == .alertSecondButtonReturn, let match, match.canResume {
            guard claimRequest(match.summary.destination) else {
                return
            }
            recoveryTask = match.summary
            volumes = [match.summary.destination]
            selectedFolder = match.summary.destination
            rebuildDestinations()
            reconnect.resetRetryBudget(taskID: match.summary.id)
            startResume(match.summary.id)
        } else if answer == .alertThirdButtonReturn, let match, match.canRestart {
            let target = destination ?? match.summary.destination
            selectedFolder = target
            startCopy(target, replacing: match, matched: true)
        } else {
            releaseRequest()
            updateText()
            onBusyChanged?()
        }
    }

    private func startResume(_ identifier: UUID) {
        guard !isBusy else {
            return
        }
        activeDestination = recoveryTask?.destination ?? activeDestination ?? selectedFolder ?? request?.destination
        beginOperation { token, emit in
            return SendToCore.resume(taskID: identifier, cancel: {
                return token.isCancelled
            }, progress: emit)
        }
    }

    private func beginOperation(_ operation: @escaping (SendToCancellation, @escaping (SendToProgress) -> Void) -> SendToResult) {
        scanGeneration += 1
        scanning = false
        isBusy = true
        result = nil
        progress = nil
        token = SendToCancellation()
        updateText()
        onBusyChanged?()
        let token = self.token
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = operation(token, { value in
                DispatchQueue.main.async {
                    guard self.isBusy else {
                        return
                    }
                    self.progress = value
                    self.updateText()
                }
            })
            DispatchQueue.main.async {
                self.isBusy = false
                self.result = outcome
                if let pendingRestart = self.pendingRestart, outcome.taskID != pendingRestart.summary.id {
                    self.pendingRestart = nil
                }
                if self.beginReconnect(outcome) {
                    return
                }
                self.releaseRequest()
                self.updateText()
                self.onBusyChanged?()
                if self.closeAfterPause {
                    self.window.close()
                }
            }
        }
    }

    private func beginReconnect(_ outcome: SendToResult) -> Bool {
        guard let target = activeDestination, let identifier = outcome.taskID, !closeAfterPause,
              SendToReconnectController.isReconnectable(outcome, destination: target) else {
            return false
        }
        reconnecting = true
        isBusy = true
        reconnectGeneration += 1
        let generation = reconnectGeneration
        reconnectText = SendToLocalization.text("reconnectChecking")
        updateText()
        DispatchQueue.global(qos: .utility).async {
            let proof = Result { try SendToCore.destinationProof(taskID: identifier) }
            DispatchQueue.main.async {
                guard self.reconnecting, self.reconnectGeneration == generation else {
                    return
                }
                do {
                    let value = try proof.get()
                    let started = self.reconnect.start(taskID: identifier, proof: value, onState: { state in
                        guard self.reconnecting, self.reconnectGeneration == generation else {
                            return
                        }
                        switch state {
                        case .checking(let attempt):
                            self.reconnectText = SendToLocalization.text("reconnectChecking") + " · \(attempt)"
                        case .mounting(let attempt):
                            self.reconnectText = SendToLocalization.text("reconnectMounting") + " · \(attempt)"
                        case .requestingConnection:
                            self.reconnectText = SendToLocalization.text("reconnectMounting")
                        case .waiting(let attempt, let delay):
                            self.reconnectText = SendToLocalization.text("reconnectWaiting") + " · \(attempt) · \(Int(delay))s"
                        case .ready:
                            self.reconnectText = SendToLocalization.text("reconnectReady")
                        case .cancelled:
                            self.endReconnect(SendToLocalization.text("reconnectPaused"))
                        case .stopped(let reason):
                            self.endReconnect(SendToLocalization.text("reconnectStopped"), diagnostic: reason)
                        }
                        self.updateText()
                    }, onReady: {
                        guard self.reconnecting, self.reconnectGeneration == generation else {
                            return
                        }
                        self.reconnecting = false
                        self.isBusy = false
                        if let pendingRestart = self.pendingRestart {
                            self.startRestart(pendingRestart)
                        } else {
                            self.startResume(identifier)
                        }
                    })
                    if !started && self.reconnecting {
                        self.endReconnect(SendToLocalization.text("reconnectStopped"))
                    }
                } catch {
                    self.endReconnect(SendToLocalization.text("reconnectStopped"), diagnostic: error.localizedDescription)
                }
            }
        }
        return true
    }

    private func endReconnect(_ message: String, diagnostic: String? = nil) {
        reconnecting = false
        isBusy = false
        reconnectText = message
        reconnectDiagnostic = diagnostic
        releaseRequest()
        updateText()
        onBusyChanged?()
        if closeAfterPause {
            window.close()
        }
    }

    private func connectShare() {
        guard !isBusy, let identifier = taskIdentifier else {
            return
        }
        reconnect.cancel()
        reconnect.resetRetryBudget(taskID: identifier)
        reconnecting = true
        reconnectGeneration += 1
        let generation = reconnectGeneration
        token = SendToCancellation()
        let connectionToken = token
        isBusy = true
        updateText()
        onBusyChanged?()
        DispatchQueue.global(qos: .utility).async {
            let proof = Result { try SendToCore.destinationProof(taskID: identifier) }
            DispatchQueue.main.async {
                guard self.reconnecting, self.reconnectGeneration == generation, !connectionToken.isCancelled else {
                    return
                }
                do {
                    self.reconnect.requestInteractiveConnection(proof: try proof.get()) { opened in
                        guard self.reconnecting, self.reconnectGeneration == generation, !connectionToken.isCancelled else {
                            return
                        }
                        self.reconnecting = false
                        self.isBusy = false
                        if opened && !self.closeAfterPause && !self.token.isCancelled {
                            if let pendingRestart = self.pendingRestart {
                                self.startRestart(pendingRestart)
                            } else {
                                self.startResume(identifier)
                            }
                        } else {
                            self.endReconnect(SendToLocalization.text("reconnectStopped"))
                        }
                    }
                } catch {
                    self.endReconnect(SendToLocalization.text("reconnectStopped"), diagnostic: error.localizedDescription)
                }
            }
        }
    }

    @objc private func showRecovery(_ sender: Any?) {
        onShowRecovery?()
    }

    @objc private func cancelSelected(_ sender: Any?) {
        if isBusy {
            cancel()
        } else {
            window.close()
        }
    }

    @objc private func languageChanged(_ sender: NSPopUpButton) {
        let values = ["system"] + SendToLocalization.languages
        guard values.indices.contains(sender.indexOfSelectedItem) else {
            return
        }
        SendToLocalization.defaults.set(values[sender.indexOfSelectedItem], forKey: "language")
        updateText()
    }

    @objc private func themeChanged(_ sender: NSPopUpButton) {
        let values = ["system", "light", "dark"]
        guard values.indices.contains(sender.indexOfSelectedItem) else {
            return
        }
        SendToLocalization.defaults.set(values[sender.indexOfSelectedItem], forKey: "theme")
        updateText()
    }

    private func updateText() {
        SendToLocalization.applyAppearance()
        SendToAppMenu.install()
        window.bySendToTitle(SendToLocalization.text("title"))
        heading.byStringValue(SendToLocalization.text("title"))
        scope.byStringValue(SendToLocalization.text("scope"))
        let sourcePaths = recoveryTask?.sourcePaths ?? request?.sources.map {
            return $0.url.path
        } ?? []
        sourceHeading.byStringValue(SendToLocalization.text("sources") + ": \(sourcePaths.count)")
        destinationHeading.byStringValue(SendToLocalization.text("destination"))
        let canConnect = result?.resumeAvailable == true && activeDestination?.isNetwork == true
        folderButton.bySendToTitle(SendToLocalization.text(canConnect ? "connectShare" : "chooseFolder"))
            .bySendToEnabled(!isBusy && !scanning && !preparingSelection && !volumes.isEmpty && (canConnect || (recoveryTask == nil && result == nil)))
            .bySendToHidden(volumes.isEmpty || scanning)
        let target = recoveryTask?.destination ?? selectedFolder ?? (volumes.indices.contains(destination.indexOfSelectedItem) ? volumes[destination.indexOfSelectedItem] : nil)
        folderText.bySendToText(target?.url.path ?? "")
        folderScroll.bySendToHidden(volumes.isEmpty || scanning)
        reload.bySendToTitle(SendToLocalization.text("reload"))
            .bySendToEnabled(!isBusy && !scanning)
        destination.bySendToEnabled(!isBusy && !scanning && !preparingSelection && !volumes.isEmpty && recoveryTask == nil && result == nil)
        languageLabel.byStringValue(SendToLocalization.text("language"))
        themeLabel.byStringValue(SendToLocalization.text("theme"))
        language.bySendToReplaceItems([SendToLocalization.text("system")] + SendToLocalization.languageNames)
            .bySelectedIndex((["system"] + SendToLocalization.languages).firstIndex(of: SendToLocalization.defaults.string(forKey: "language") ?? "system") ?? 0)
        theme.bySendToReplaceItems(["system", "light", "dark"].map(SendToLocalization.text))
            .bySelectedIndex(["system", "light", "dark"].firstIndex(of: SendToLocalization.defaults.string(forKey: "theme") ?? "system") ?? 0)
        empty.byStringValue(scanning ? SendToLocalization.text("scanning") : "💾 " + SendToLocalization.text(scanError != nil ? "scanFailed" : (noApplicableTargets ? "noTarget" : "emptyTitle")) + "\n" + SendToLocalization.text("emptyBody") + (scanError.map {
            return "\n" + $0
        } ?? ""))
            .bySendToHidden(!volumes.isEmpty && !scanning)
        let copyTitle = result?.resumeAvailable == true ? (pendingRestart == nil ? "resumeTask" : "retryRestart") : "start"
        copyButton.bySendToTitle(SendToLocalization.text(copyTitle))
            .bySendToEnabled(!isBusy && !scanning && !preparingSelection && (result?.resumeAvailable == true || (result == nil && request != nil && !volumes.isEmpty)))
        cancelButton.bySendToTitle(SendToLocalization.text(isBusy ? "pauseTask" : "close"))
            .bySendToEnabled(!isBusy || !token.isCancelled)
        recoveryButton.bySendToTitle(SendToLocalization.text("recoveryTitle"))
        activity.bySendToActive(isBusy || scanning)
        current.byStringValue(reconnecting ? (reconnectText ?? "") : (folderError ?? progress?.currentPath ?? ""))
        if let result {
            let state = result.cancelled ? "cancelled" : (result.failures.isEmpty ? "complete" : "failed")
            status.byStringValue(SendToLocalization.text(state) + " · " + SendToLocalization.text("successes") + ": \(result.successes.count) · " + SendToLocalization.text("failures") + ": \(result.failures.count)")
            let failures = result.failures.map {
                let explanation = $0.code == "destination" ? SendToLocalization.text("destinationChanged") : SendToLocalization.failureText($0.code)
                return ($0.source?.path ?? "") + "\n" + explanation
            }.joined(separator: "\n\n")
            var details = SendToLocalization.text("successes") + ":\n" + result.successes.map(\.path).joined(separator: "\n")
            if !result.failures.isEmpty {
                details += "\n\n" + SendToLocalization.text("failures") + ":\n" + failures +
                    "\n\n" + SendToLocalization.text("rawDiagnostics") + ":\n" + result.failures.map {
                        $0.code + " — " + ($0.source?.path ?? "") + "\n" + $0.message
                    }.joined(separator: "\n\n")
            }
            if let taskID = result.taskID, result.resumeAvailable {
                details += "\n\n" + SendToLocalization.text("resumeSaved") + "\n" + taskID.uuidString
            } else if result.cancelled && result.taskID == nil {
                details += "\n\n" + SendToLocalization.text("preparationStopped")
            }
            if let reconnectText {
                details += "\n\n" + reconnectText
            }
            if let reconnectDiagnostic {
                details += "\n\n" + SendToLocalization.text("rawDiagnostics") + ":\n" + reconnectDiagnostic
            }
            if pendingRestart != nil {
                details += "\n\n" + SendToLocalization.text("restartPending")
            }
            sourceText.bySendToText(details)
        } else {
            let phase = progress?.phase == "copying" ? "copying" : "preparing"
            status.byStringValue(SendToLocalization.text(isBusy ? (token.isCancelled ? "cancelling" : phase) : "ready") +
                (progress.map {
                    return " · \($0.completed) / \($0.total)"
                } ?? ""))
            sourceText.bySendToText(sourcePaths.isEmpty ? SendToLocalization.text("selectSources") : sourcePaths.joined(separator: "\n"))
        }
    }

    private func layout() {
        let width = window.contentView?.bounds.width ?? 760
        let height = window.contentView?.bounds.height ?? 620
        let margin: CGFloat = 24
        let span = width - 2 * margin
        heading.bySendToFrame(NSRect(x: margin, y: height - 54, width: span, height: 30))
        scope.bySendToFrame(NSRect(x: margin, y: height - 120, width: span, height: 60))
        languageLabel.bySendToFrame(NSRect(x: margin, y: height - 154, width: 100, height: 24))
        language.bySendToFrame(NSRect(x: margin + 100, y: height - 154, width: span / 2 - 110, height: 26))
        themeLabel.bySendToFrame(NSRect(x: width / 2 + 10, y: height - 154, width: 100, height: 24))
        theme.bySendToFrame(NSRect(x: width / 2 + 110, y: height - 154, width: span / 2 - 110, height: 26))
        sourceHeading.bySendToFrame(NSRect(x: margin, y: height - 192, width: span, height: 24))
        sourceScroll.bySendToFrame(NSRect(x: margin, y: 340, width: span, height: max(110, height - 538)))
        destinationHeading.bySendToFrame(NSRect(x: margin, y: 306, width: span, height: 24))
        destination.bySendToFrame(NSRect(x: margin, y: 272, width: span - 180, height: 28))
        reload.bySendToFrame(NSRect(x: width - margin - 170, y: 270, width: 170, height: 32))
        folderScroll.bySendToFrame(NSRect(x: margin, y: 208, width: span, height: 54))
        folderButton.bySendToFrame(NSRect(x: margin, y: 166, width: span, height: 32))
        empty.bySendToFrame(NSRect(x: margin, y: 160, width: span, height: 100))
        activity.bySendToFrame(NSRect(x: margin, y: 100, width: 20, height: 20))
        status.bySendToFrame(NSRect(x: margin + 28, y: 96, width: span - 28, height: 26))
        current.bySendToFrame(NSRect(x: margin, y: 65, width: span, height: 24))
        let buttonWidth = (span - 24) / 3
        copyButton.bySendToFrame(NSRect(x: margin, y: 18, width: buttonWidth, height: 34))
        cancelButton.bySendToFrame(NSRect(x: margin + buttonWidth + 12, y: 18, width: buttonWidth, height: 34))
        recoveryButton.bySendToFrame(NSRect(x: margin + 2 * (buttonWidth + 12), y: 18, width: buttonWidth, height: 34))
    }
}
