//
//  SendToRecoveryWindowController.swift
//  JobsSendTo
//
//  Created by Jobs on 2026年11月18日，星期三.
//

import AppKit

final class SendToRecoveryWindowController: NSObject,
                                          NSWindowDelegate,
                                          NSTableViewDataSource,
                                          NSTableViewDelegate {

    private var tasks: [SendToTaskSummary] = []
    private var selectedID: UUID?
    private var generation = 0
    private var loading = false
    private(set) var isBusy = false
    private var diagnostic: String?
    private var messageKey: String?
    private var mountedCount: Int?
    var onResume: ((SendToTaskSummary) -> Void)?
    var onClose: (() -> Void)?
    var onBusyChanged: (() -> Void)?
    var confirmDiscard: ((SendToTaskSummary) -> Bool)?

    private lazy var window = NSWindow.makeSendToWindow(delegate: self)
    private lazy var content = NSView.makeSendToView()
    private lazy var title = NSTextField.makeSendToLabel(large: true)
    private lazy var explanation = NSTextField.makeSendToLabel()
    private lazy var heading = NSTextField.makeSendToLabel()
    private lazy var table = NSTableView.makeSendToTaskTable(dataSource: self, delegate: self)
    private lazy var tableScroll = NSScrollView.makeSendToTaskScroll(table: table)
    private lazy var empty = NSTextField.makeSendToLabel()
    private lazy var detailText = NSTextView.makeSendToTextView()
    private lazy var detailScroll = NSScrollView.makeSendToScroll(text: detailText)
    private lazy var reload = NSButton.makeSendToButton(target: self, action: #selector(reloadTasks(_:)))
    private lazy var rescan = NSButton.makeSendToButton(target: self, action: #selector(rescanDestinations(_:)))
    private lazy var resume = NSButton.makeSendToButton(target: self, action: #selector(resumeSelected(_:)))
    private lazy var discard = NSButton.makeSendToButton(target: self, action: #selector(discardSelected(_:)))
    private lazy var close = NSButton.makeSendToButton(target: self, action: #selector(closeWindow(_:)))
    private lazy var activity = NSProgressIndicator.makeSendToActivity()
    private lazy var status = NSTextField.makeSendToLabel()
    private lazy var languageLabel = NSTextField.makeSendToLabel()
    private lazy var themeLabel = NSTextField.makeSendToLabel()
    private lazy var language = NSPopUpButton.make(frame: .zero)
    private lazy var theme = NSPopUpButton.make(frame: .zero)

    func show() {
        for view in [title, explanation, heading, tableScroll, empty, detailScroll, reload, rescan, resume, discard,
                     close, activity, status, languageLabel, themeLabel, language, theme] {
            content.bySendToAddSubview(view)
        }
        language.byTarget(self)
            .byAction(#selector(languageChanged(_:)))
        theme.byTarget(self)
            .byAction(#selector(themeChanged(_:)))
        discard.bySendToDestructive(true)
        window.bySendToContentView(content)
        updateText()
        layout()
        focus()
        reloadTasks(nil)
    }

    func focus() {
        window.bySendToShow()
        NSApp.activate(ignoringOtherApps: true)
    }

    func refresh() {
        guard !isBusy else {
            return
        }
        reloadTasks(nil)
    }

    private var selectedTask: SendToTaskSummary? {
        return tasks.first {
            return $0.id == selectedID
        }
    }

    @objc private func reloadTasks(_ sender: Any?) {
        guard !isBusy else {
            return
        }
        generation += 1
        let current = generation
        loading = true
        updateText()
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = Result {
                return try SendToCore.pendingTasks()
            }
            DispatchQueue.main.async {
                guard current == self.generation else {
                    return
                }
                self.loading = false
                switch outcome {
                /// The local journal is the source of unfinished tasks after a fresh process launch.
                case .success(let tasks):
                    self.tasks = tasks
                    if self.messageKey == "recoveryReadFailed" {
                        self.messageKey = nil
                        self.diagnostic = nil
                    }
                /// Keep an explicit error and a reload action; do not report a failed read as an empty journal.
                case .failure(let error):
                    self.tasks = []
                    self.diagnostic = error.localizedDescription
                    self.messageKey = "recoveryReadFailed"
                }
                let row = self.tasks.firstIndex {
                    return $0.id == self.selectedID
                }
                if row == nil {
                    self.selectedID = nil
                }
                self.table.bySendToReload(selectedRow: row)
                self.updateText()
            }
        }
    }

    @objc private func rescanDestinations(_ sender: Any?) {
        guard !isBusy && !loading else {
            return
        }
        loading = true
        diagnostic = nil
        updateText()
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = Result {
                return try SendToCore.volumes()
            }
            DispatchQueue.main.async {
                self.loading = false
                switch outcome {
                /// A rescan reports mounted targets; resume still checks the task's original destination identity.
                case .success(let volumes):
                    self.mountedCount = volumes.count
                    self.messageKey = "recoveryRescanDone"
                /// A disconnected device does not turn into a new destination or a new copy task.
                case .failure(let error):
                    self.mountedCount = nil
                    self.diagnostic = error.localizedDescription
                    self.messageKey = "scanFailed"
                }
                self.reloadTasks(nil)
            }
        }
    }

    @objc private func resumeSelected(_ sender: Any?) {
        guard !isBusy, !loading, let task = selectedTask, !task.isBusy, task.state != "completed" else {
            return
        }
        onResume?(task)
        reloadTasks(nil)
    }

    @objc private func discardSelected(_ sender: Any?) {
        guard !isBusy, !loading, let task = selectedTask, !task.isBusy else {
            return
        }
        let confirmed = confirmDiscard?(task) ?? (makeDiscardAlert(task).runModal() == .alertSecondButtonReturn)
        guard confirmed else {
            return
        }
        isBusy = true
        messageKey = "discardingTask"
        updateText()
        onBusyChanged?()
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = Result {
                return try SendToCore.discard(taskID: task.id)
            }
            DispatchQueue.main.async {
                self.isBusy = false
                switch outcome {
                /// Completed copies and source files remain untouched when an unfinished task is abandoned.
                case .success:
                    self.messageKey = "discardedTask"
                    self.diagnostic = nil
                /// A failed identity or ownership check keeps the task for review and a later explicit retry.
                case .failure(let error):
                    self.messageKey = "discardFailed"
                    self.diagnostic = error.localizedDescription
                }
                self.onBusyChanged?()
                self.reloadTasks(nil)
            }
        }
    }

    private func makeDiscardAlert(_ task: SendToTaskSummary) -> NSAlert {
        // The first/default button cancels; only the explicit destructive action authorizes this task's cleanup.
        let scope = SendToLocalization.text("discardScope") + "\n\n" + task.id.uuidString + "\n" +
            SendToLocalization.taskDestination(task) + "\n\n" + task.sourcePaths.joined(separator: "\n")
        let text = NSTextField.make(labelWithString: scope)
            .byWrapping(true)
        let alert = NSAlert.make()
            .byMessageText(SendToLocalization.text("discardTitle"))
            .byAccessoryView(NSScrollView.make(document: text, frame: NSRect(x: 0, y: 0, width: 520, height: 230)))
            .byAlertStyle(.warning)
            .byAddButton(SendToLocalization.text("cancel"))
            .byAddButton(SendToLocalization.text("discardTask"))
        alert.buttons[1].bySendToDestructive(true)
        return alert
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        return tasks.count
    }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        guard tasks.indices.contains(row) else {
            return nil
        }
        let task = tasks[row]
        switch tableColumn?.identifier.rawValue {
        /// Show the first source name and count while keeping the stable UUID in the detail pane.
        case "task":
            let name = task.sourcePaths.first.map {
                return URL(fileURLWithPath: $0).lastPathComponent
            } ?? task.id.uuidString
            return name + " (\(task.total))"
        /// Busy is derived from the live core lock, not a stale PID or the persisted running string.
        case "state":
            return SendToLocalization.taskState(task.isBusy ? "busy" : task.state)
        /// Completed top-level objects are kept and will not be copied again on resume.
        case "progress":
            return "\(task.completed) / \(task.total)"
        /// Dates follow the selected interface language.
        case "updated":
            return DateFormatter.sendToTimestamp(task.updatedAt)
        /// Unknown columns have no corresponding task field.
        default:
            return nil
        }
    }

    func selectionShouldChange(in tableView: NSTableView) -> Bool {
        return !loading && !isBusy
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        selectedID = tasks.indices.contains(table.selectedRow) ? tasks[table.selectedRow].id : nil
        updateText()
    }

    @objc private func languageChanged(_ sender: NSPopUpButton) {
        let values = ["system"] + SendToLocalization.languages
        guard values.indices.contains(sender.indexOfSelectedItem) else {
            return
        }
        SendToLocalization.defaults.set(values[sender.indexOfSelectedItem], forKey: "language")
        table.bySendToReload(selectedRow: tasks.firstIndex {
            return $0.id == selectedID
        })
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

    @objc private func closeWindow(_ sender: Any?) {
        window.close()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        return !isBusy
    }

    func windowWillClose(_ notification: Notification) {
        generation += 1
        onClose?()
    }

    func windowDidResize(_ notification: Notification) {
        layout()
    }

    private func updateText() {
        SendToLocalization.applyAppearance()
        SendToAppMenu.install()
        window.bySendToTitle(SendToLocalization.text("recoveryTitle"))
        title.byStringValue(SendToLocalization.text("recoveryTitle"))
        explanation.byStringValue(SendToLocalization.text("recoveryIntro"))
        heading.byStringValue(SendToLocalization.text("taskList") + ": \(tasks.count)")
        table.bySendToHeaders(["taskColumn", "stateColumn", "progressColumn", "updatedColumn"].map(SendToLocalization.text))
        tableScroll.bySendToHidden(tasks.isEmpty)
        empty.byStringValue("🗂 " + SendToLocalization.text(diagnostic == nil ? "recoveryEmptyTitle" : "recoveryReadFailed") + "\n\n" + SendToLocalization.text("recoveryEmptyBody"))
            .bySendToHidden(!tasks.isEmpty)
        reload.bySendToTitle(SendToLocalization.text("reloadTasks"))
            .bySendToEnabled(!isBusy && !loading)
        rescan.bySendToTitle(SendToLocalization.text("rescanTaskTargets"))
            .bySendToEnabled(!isBusy && !loading)
        resume.bySendToTitle(SendToLocalization.text("resumeTask"))
            .bySendToEnabled(!isBusy && !loading && selectedTask != nil && selectedTask?.isBusy == false && selectedTask?.state != "completed")
        discard.bySendToTitle(SendToLocalization.text("discardTask"))
            .bySendToEnabled(!isBusy && !loading && selectedTask != nil && selectedTask?.isBusy == false)
        close.bySendToTitle(SendToLocalization.text("close"))
            .bySendToEnabled(!isBusy)
        languageLabel.byStringValue(SendToLocalization.text("language"))
        themeLabel.byStringValue(SendToLocalization.text("theme"))
        language.bySendToReplaceItems([SendToLocalization.text("system")] + SendToLocalization.languageNames)
            .bySelectedIndex((["system"] + SendToLocalization.languages).firstIndex(of: SendToLocalization.defaults.string(forKey: "language") ?? "system") ?? 0)
        theme.bySendToReplaceItems(["system", "light", "dark"].map(SendToLocalization.text))
            .bySelectedIndex(["system", "light", "dark"].firstIndex(of: SendToLocalization.defaults.string(forKey: "theme") ?? "system") ?? 0)
        activity.bySendToActive(loading || isBusy)
        status.byStringValue(SendToLocalization.text(loading ? "loadingTasks" : (messageKey ?? "recoveryReady")) +
            (messageKey == "recoveryRescanDone" ? (mountedCount.map {
                return " (\($0))"
            } ?? "") : ""))
        var details = SendToLocalization.text("selectTask")
        if let task = selectedTask {
            details = task.id.uuidString + "\n" + SendToLocalization.taskState(task.isBusy ? "busy" : task.state) +
                "\n" + SendToLocalization.text("destination") + ": " + SendToLocalization.taskDestination(task) +
                "\n" + SendToLocalization.text("sources") + ":\n" + task.sourcePaths.joined(separator: "\n")
            if let detail = task.detail, !detail.isEmpty {
                details += "\n\n" + SendToLocalization.text("recoveryCheckHint") + "\n" +
                    SendToLocalization.text("rawDiagnostics") + ":\n" + detail
            }
        }
        if let diagnostic {
            details += "\n\n" + SendToLocalization.text("rawDiagnostics") + ":\n" + diagnostic
        }
        detailText.bySendToText(details)
    }

    private func layout() {
        let width = window.contentView?.bounds.width ?? 760
        let height = window.contentView?.bounds.height ?? 650
        let margin: CGFloat = 24
        let span = width - 2 * margin
        title.bySendToFrame(NSRect(x: margin, y: height - 54, width: span, height: 30))
        explanation.bySendToFrame(NSRect(x: margin, y: height - 124, width: span, height: 66))
        languageLabel.bySendToFrame(NSRect(x: margin, y: height - 157, width: 100, height: 24))
        language.bySendToFrame(NSRect(x: margin + 100, y: height - 157, width: span / 2 - 110, height: 26))
        themeLabel.bySendToFrame(NSRect(x: width / 2 + 10, y: height - 157, width: 100, height: 24))
        theme.bySendToFrame(NSRect(x: width / 2 + 110, y: height - 157, width: span / 2 - 110, height: 26))
        heading.bySendToFrame(NSRect(x: margin, y: height - 194, width: span, height: 24))
        let listRect = NSRect(x: margin, y: 307, width: span, height: max(110, height - 511))
        tableScroll.bySendToFrame(listRect)
        empty.bySendToFrame(listRect)
        reload.bySendToFrame(NSRect(x: margin, y: 267, width: (span - 12) / 2, height: 32))
        rescan.bySendToFrame(NSRect(x: width / 2 + 6, y: 267, width: (span - 12) / 2, height: 32))
        detailScroll.bySendToFrame(NSRect(x: margin, y: 105, width: span, height: 150))
        activity.bySendToFrame(NSRect(x: margin, y: 72, width: 20, height: 20))
        status.bySendToFrame(NSRect(x: margin + 28, y: 64, width: span - 28, height: 32))
        let buttonWidth = (span - 24) / 3
        resume.bySendToFrame(NSRect(x: margin, y: 18, width: buttonWidth, height: 34))
        discard.bySendToFrame(NSRect(x: margin + buttonWidth + 12, y: 18, width: buttonWidth, height: 34))
        close.bySendToFrame(NSRect(x: margin + 2 * (buttonWidth + 12), y: 18, width: buttonWidth, height: 34))
    }
}

private extension DateFormatter {

    static func sendToTimestamp(_ value: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: SendToLocalization.language)
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: value)
    }
}
