//
//  SendToRecoveryInterfaceTests.swift
//  JobsSendToTests
//
//  Created by Jobs on 2026年11月18日，星期三.
//

import AppKit
import Foundation
import Darwin

// Storage and copying are replaced only in this separately compiled native-control fixture.
enum SendToCore {

    static var saved: [SendToTaskSummary] = []
    static var readError: Error?
    static var resumed: [UUID] = []
    static var discarded: [UUID] = []
    static var copied = 0
    static var waitForPause = false
    static var matches: [SendToTaskMatch] = []
    static var discovered: [SendToVolume]?
    static var copiedTargets: [SendToVolume] = []
    static var events: [String] = []
    static var discardError: Error?
    static var resumeResults: [SendToResult] = []
    static var destinationError: Error?
    static var proofGate: DispatchSemaphore?
    static var proofStarted = false
    static var proofFinished = false

    static func pendingTasks() throws -> [SendToTaskSummary] {
        if let readError {
            throw readError
        }
        return saved
    }

    static func volumes() throws -> [SendToVolume] {
        return discovered ?? saved.map(\.destination)
    }

    static func selectedDirectory(root: SendToVolume, folder: URL, expectedInode: UInt64? = nil) throws -> SendToVolume {
        if folder.path == root.url.path { return root }
        return SendToVolume(url: folder, name: root.name, identity: SendToIdentity(dev: root.identity.dev, ino: 77),
                            isNetwork: root.isNetwork, rootURL: root.volumeURL, rootIdentity: root.volumeIdentity)
    }

    static func matchingTasks(sources: [SendToSource], destination: SendToVolume? = nil,
                               cancel: () -> Bool = { false }) throws -> [SendToTaskMatch] {
        return matches
    }

    static func destinationProof(taskID: UUID) throws -> SendToVolumeProof {
        proofStarted = true
        if let proofGate { _ = proofGate.wait(timeout: .now() + 2) }
        proofFinished = true
        return SendToVolumeProof(rootURL: URL(fileURLWithPath: "/Volumes/fixture-not-mounted"), uuid: nil,
                                  fsid: "fixture", networkEndpoint: SendToPersistentIO.digest(Data("smbfs:fixture/Share".utf8)),
                                  fsType: "smbfs", rootIno: 2, reconnectURL: URL(string: "smb://fixture/Share")!)
    }

    static func resolvedDestination(taskID: UUID) throws -> SendToVolume {
        events.append("resolve")
        if let destinationError { throw destinationError }
        return matches.first(where: { $0.summary.id == taskID })!.summary.destination
    }

    static func canCopy(sources: [SendToSource], destination: SendToVolume) -> Bool {
        return true
    }

    static func discard(taskID: UUID) throws {
        if let discardError { throw discardError }
        discarded.append(taskID)
        events.append("discard:" + taskID.uuidString)
        saved.removeAll { $0.id == taskID }
    }

    static func copy(sources: [SendToSource], destination: SendToVolume,
                     cancel: @escaping () -> Bool, progress: @escaping (SendToProgress) -> Void) -> SendToResult {
        copied += 1
        copiedTargets.append(destination)
        events.append("copy")
        return SendToResult()
    }

    static func resume(taskID: UUID, cancel: @escaping () -> Bool,
                       progress: @escaping (SendToProgress) -> Void) -> SendToResult {
        resumed.append(taskID)
        if !resumeResults.isEmpty { return resumeResults.removeFirst() }
        let deadline = Date().addingTimeInterval(2)
        while waitForPause && !cancel() && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        return SendToResult(cancelled: true, taskID: taskID, resumeAvailable: true)
    }
}

extension SendToRecoveryWindowController {

    var fixtureLoading: Bool {
        return loading
    }

    var fixtureSelection: UUID? {
        return selectedID
    }

    var fixtureCanResume: Bool {
        return resume.isEnabled
    }

    var fixtureCanDiscard: Bool {
        return discard.isEnabled
    }

    var fixtureDetails: String {
        return detailText.string
    }

    var fixtureDiagnostic: String? {
        return diagnostic
    }

    func fixtureSelect(_ row: Int?) {
        table.bySendToReload(selectedRow: row)
    }

    func fixtureResume() {
        resumeSelected(nil)
    }

    func fixtureDiscard() {
        discardSelected(nil)
    }

    func fixtureAlert(_ task: SendToTaskSummary) -> NSAlert {
        return makeDiscardAlert(task)
    }

    func fixtureChangeLanguage(_ value: String) {
        language.bySelectedIndex((["system"] + SendToLocalization.languages).firstIndex(of: value)!)
        languageChanged(language)
    }

    func fixtureClose() {
        window.close()
    }
}

extension SendToWindowController {

    func fixtureChangeTheme(_ index: Int) {
        theme.bySelectedIndex(index)
        themeChanged(theme)
    }

    func fixtureConnect() { connectShare() }

    var fixturePreparingSelection: Bool { return preparingSelection }
    var fixtureFolderPath: String { return folderText.string }
    var fixtureReconnecting: Bool { return reconnecting }
    var fixturePendingRestart: UUID? { return pendingRestart?.summary.id }

    func fixtureSelectFolder(_ folder: URL, root: SendToVolume) {
        acceptFolder(folder, root: root)
    }

    func fixtureRepeatAlert(_ matches: [SendToTaskMatch]) -> NSAlert {
        return makeRepeatAlert(matches, destination: nil)
    }

    func fixtureReconnect(_ dependencies: SendToReconnectController.Dependencies) {
        reconnect = SendToReconnectController(dependencies: dependencies)
    }

    func fixtureFolderPanel(_ root: SendToVolume) -> NSOpenPanel {
        folderRoot = root
        return NSOpenPanel.makeSendToFolderPanel(directory: root.url, message: "fixture", prompt: "choose", delegate: self)
    }

    func fixtureChangeLanguage(_ value: String) {
        language.bySelectedIndex((["system"] + SendToLocalization.languages).firstIndex(of: value)!)
        languageChanged(language)
    }

    var fixtureCanContinue: Bool {
        return copyButton.isEnabled
    }

    func fixtureContinue() {
        copySelected(nil)
    }

    func fixtureCloseDuringWork() -> Bool {
        return windowShouldClose(window)
    }

    func fixtureClose() {
        window.close()
    }
}

@main
enum SendToRecoveryInterfaceTests {

    static var checks = 0

    static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        precondition(value(), message)
    }

    static func wait(_ predicate: () -> Bool) {
        let deadline = Date().addingTimeInterval(4)
        while !predicate() && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        expect(predicate(), "bounded native-control worker must settle")
    }

    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        precondition(CommandLine.arguments.count == 2 && CommandLine.arguments[1].hasPrefix("com.jobs.sendto.ui-fixture."))
        defer {
            UserDefaults.standard.removePersistentDomain(forName: CommandLine.arguments[1])
        }
        SendToLocalization.defaults.set("en", forKey: "language")
        let target = SendToVolume(url: URL(fileURLWithPath: "/Volumes/fixture-not-mounted"),
                                  name: "fixture", identity: SendToIdentity(dev: 1, ino: 2), isNetwork: true)
        let paused = SendToTaskSummary(id: UUID(), destination: target, sourcePaths: ["/fixture/source"],
                                        state: "paused", completed: 1, total: 3, updatedAt: Date(), detail: nil, isBusy: false)
        var busy = paused
        busy = SendToTaskSummary(id: UUID(), destination: target, sourcePaths: ["/fixture/busy"],
                                  state: "running", completed: 0, total: 1, updatedAt: Date(), detail: nil, isBusy: true)
        let blocked = SendToTaskSummary(id: UUID(), destination: target, sourcePaths: ["/fixture/changed"],
                                         state: "blocked", completed: 0, total: 1, updatedAt: Date(),
                                         detail: "fixture: manifest identity changed", isBusy: false)
        SendToCore.saved = [paused, busy, blocked]
        let recovery = SendToRecoveryWindowController()
        recovery.show()
        wait { !recovery.fixtureLoading }
        expect(recovery.fixtureSelection == nil, "startup reads persistent records without selecting or resuming")
        expect(!recovery.fixtureCanResume && !recovery.fixtureCanDiscard, "empty selection disables both mutations")
        expect(SendToCore.resumed.isEmpty && SendToCore.copied == 0, "startup never resumes or copies automatically")
        recovery.fixtureResume()
        recovery.fixtureDiscard()
        expect(SendToCore.resumed.isEmpty && SendToCore.discarded.isEmpty, "direct empty-selection actions stay inert")
        recovery.fixtureSelect(1)
        expect(!recovery.fixtureCanResume && !recovery.fixtureCanDiscard, "a live locked task cannot resume twice or be discarded")
        recovery.fixtureResume()
        recovery.fixtureDiscard()
        expect(SendToCore.discarded.isEmpty, "busy direct dispatch does not reach discard")
        recovery.fixtureSelect(2)
        expect(recovery.fixtureDetails.contains("manifest identity changed"), "blocked tasks remain inspectable")
        recovery.fixtureSelect(0)
        expect(recovery.fixtureSelection == paused.id && recovery.fixtureCanResume, "selection binds stable task UUID")
        let alert = recovery.fixtureAlert(paused)
        expect(alert.buttons[0].title == SendToLocalization.text("cancel"), "discard confirmation defaults to cancel")
        expect(alert.buttons[1].hasDestructiveAction, "cleanup action is explicitly destructive")
        recovery.confirmDiscard = { _ in false }
        recovery.fixtureDiscard()
        expect(SendToCore.discarded.isEmpty, "cancelling confirmation cannot discard a task")
        recovery.fixtureChangeLanguage("zh-Hans")
        expect(recovery.fixtureSelection == paused.id && recovery.fixtureCanResume, "language change preserves selected task UUID and state")
        var selected: UUID?
        recovery.onResume = { selected = $0.id }
        recovery.fixtureResume()
        wait { !recovery.fixtureLoading }
        expect(selected == paused.id && SendToCore.copied == 0, "continue emits the original task, never a new copy request")
        recovery.confirmDiscard = { _ in true }
        recovery.fixtureDiscard()
        wait { !recovery.isBusy && !recovery.fixtureLoading }
        expect(SendToCore.discarded == [paused.id], "confirmed cleanup targets exactly the selected original task")
        expect(recovery.fixtureSelection == nil, "removed task never silently selects the next task")
        SendToCore.readError = NSError(domain: "fixture-bad-journal", code: 1)
        recovery.refresh()
        wait { !recovery.fixtureLoading }
        expect(recovery.fixtureDiagnostic != nil, "failed journal discovery is shown, not treated as an empty task store")
        SendToCore.readError = nil
        recovery.refresh()
        wait { !recovery.fixtureLoading }
        expect(recovery.fixtureDiagnostic == nil, "successful reload clears only the previous read error")
        let running = SendToWindowController(task: blocked)
        running.show()
        wait { !running.isBusy }
        expect(SendToCore.resumed.last == blocked.id && SendToCore.copied == 0, "restored window invokes resume with persisted UUID")
        expect(running.taskIdentifier == blocked.id && running.fixtureCanContinue, "paused result remains associated with the original task")
        running.fixtureContinue()
        wait { !running.isBusy }
        expect(SendToCore.resumed.filter { $0 == blocked.id }.count == 2 && SendToCore.copied == 0,
               "continue after pause still resumes the same task")
        running.fixtureClose()
        SendToCore.waitForPause = true
        let closing = SendToWindowController(task: blocked)
        var closed = false
        closing.onClose = { closed = true }
        closing.show()
        wait { closing.isBusy }
        expect(!closing.fixtureCloseDuringWork(), "closing while copying first asks the worker to pause")
        wait { closed && !closing.isBusy }
        expect(SendToCore.copied == 0, "pause/close never falls back to a new copy")
        recovery.fixtureClose()
        targetSelectionTests(target, paused: paused)
        print("PASS: \(checks) recovery interface assertions")
    }

    static func targetSelectionTests(_ target: SendToVolume, paused: SendToTaskSummary) {
        SendToCore.waitForPause = false
        SendToCore.matches = []
        SendToCore.discovered = [target]
        let source = SendToSource(url: URL(fileURLWithPath: "/fixture/source"), identity: SendToIdentity(dev: 1, ino: 3), kind: .file)
        let request = SendToRequest(sources: [source], destination: target)!
        let count = SendToCore.copied
        let chooser = SendToWindowController(request: request)
        chooser.show()
        wait { !chooser.isBusy }
        expect(SendToCore.copied == count, "clicking a device opens a target chooser without starting root copying")
        let panel = chooser.fixtureFolderPanel(target)
        expect(panel.canChooseDirectories && !panel.canChooseFiles && !panel.allowsMultipleSelection && !panel.canCreateDirectories,
               "native picker selects one existing folder without performing target writes")
        expect(!chooser.panel(panel, shouldEnable: URL(fileURLWithPath: "/fixture/arbitrary-local")),
               "native chooser does not offer arbitrary local locations as device targets")
        let folder = target.url.appendingPathComponent("JobsMacStorage/deep folder")
        chooser.fixtureSelectFolder(folder, root: target)
        wait { !chooser.fixturePreparingSelection }
        expect(chooser.fixtureFolderPath == folder.path, "scrollable target text exposes the complete chosen folder path")
        for language in SendToLocalization.languages {
            chooser.fixtureChangeLanguage(language)
            expect(chooser.fixtureFolderPath == folder.path, "language changes keep the anchored folder selection")
        }
        for index in 0..<3 {
            chooser.fixtureChangeTheme(index)
            expect(chooser.fixtureFolderPath == folder.path, "all three themes preserve selected target directory")
        }
        chooser.fixtureContinue()
        wait { !chooser.isBusy }
        expect(SendToCore.copiedTargets.last?.url.path == folder.path, "actual copy receives chosen subdirectory, not volume root")
        chooser.fixtureClose()

        let task = SendToTaskSummary(id: paused.id, destination: target, sourcePaths: [source.url.path],
                                     state: "paused", completed: 0, total: 1, updatedAt: Date(), detail: nil, isBusy: false)
        SendToCore.matches = [SendToTaskMatch(summary: task, canResume: true, reason: nil, canRestart: false)]
        SendToCore.discovered = []
        let offline = SendToWindowController(request: SendToRequest(sources: [source], destination: nil)!)
        var prompted = false
        offline.confirmPrevious = { alert in
            prompted = true
            expect(alert.buttons[0].title == SendToLocalization.text("cancelChoice"), "repeat transfer defaults to cancel")
            expect(!alert.buttons[2].isEnabled, "starting over is unavailable until original target is ready")
            expect(alert.informativeText.contains(target.url.path), "offline repeat prompt shows original complete target")
            return .alertSecondButtonReturn
        }
        let resumed = SendToCore.resumed.count
        offline.show()
        wait { !offline.isBusy }
        expect(prompted && SendToCore.resumed.count == resumed + 1 && SendToCore.resumed.last == task.id,
               "same sources discover and continue an old task even with no mounted devices in the GUI")
        expect(SendToCore.copied == count + 1, "offline repeat does not create a replacement task")
        offline.fixtureClose()

        SendToCore.discovered = [target]
        SendToCore.matches = [SendToTaskMatch(summary: task, canResume: false, reason: "fixture source changed")]
        let restart = SendToWindowController(request: request)
        restart.confirmPrevious = { alert in
            expect(!alert.buttons[1].isEnabled && alert.informativeText.contains("source changed"), "source change explains why old checkpoint cannot continue")
            return .alertThirdButtonReturn
        }
        SendToCore.events = []
        restart.show()
        wait { !restart.isBusy }
        expect(SendToCore.events == ["resolve", "discard:" + task.id.uuidString, "copy"], "restart verifies target and discards selected old task safely before a new copy")
        restart.fixtureClose()

        SendToCore.discardError = NSError(domain: "fixture-unknown-staging-owner", code: 1)
        let failedRestart = SendToWindowController(request: request)
        failedRestart.confirmPrevious = { _ in .alertThirdButtonReturn }
        SendToCore.events = []
        failedRestart.show()
        wait { !failedRestart.isBusy }
        expect(SendToCore.events == ["resolve"], "failed safe discard prevents new copy and preserves unknown temporary data")
        failedRestart.fixtureClose()
        SendToCore.discardError = nil

        SendToCore.matches = [SendToTaskMatch(summary: task, canResume: true, reason: nil),
                               SendToTaskMatch(summary: paused, canResume: true, reason: nil)]
        let multiple = SendToWindowController(request: request)
        multiple.confirmPrevious = { alert in
            expect(!alert.buttons[1].isEnabled && !alert.buttons[2].isEnabled && alert.accessoryView is NSPopUpButton,
                   "multiple previous transfers require explicit selection before any action")
            return .alertFirstButtonReturn
        }
        SendToCore.events = []
        multiple.show()
        wait { !multiple.isBusy }
        expect(SendToCore.events.isEmpty, "cancelling a multiple-match prompt preserves original tasks")
        multiple.fixtureClose()

        SendToCore.matches = []
        SendToCore.resumeResults = [SendToResult(failures: [SendToFailure(source: nil, code: "resume-blocked", message: "network fixture", systemCode: ENOTCONN)],
                                                 taskID: task.id, resumeAvailable: true), SendToResult(taskID: task.id)]
        var dependencies = SendToReconnectController.Dependencies.live(openShare: { _, completion in completion(false) })
        dependencies.probe = { _, completion in completion(.success(.ready)) }
        dependencies.mountShare = { _, _ in preconditionFailure("ready fake share must not mount a real device") }
        dependencies.schedule = { _, action in DispatchQueue.main.async(execute: action); return {} }
        let reconnecting = SendToWindowController(task: task)
        reconnecting.fixtureReconnect(dependencies)
        let beforeReconnect = SendToCore.resumed.count
        reconnecting.show()
        wait { !reconnecting.isBusy && SendToCore.resumed.count >= beforeReconnect + 2 }
        expect(SendToCore.resumed.suffix(2).allSatisfy { $0 == task.id }, "network recovery resumes the same task ID after proof readiness")
        reconnecting.fixtureClose()

        SendToCore.matches = [SendToTaskMatch(summary: task, canResume: true, reason: nil)]
        SendToCore.discovered = []
        SendToCore.destinationError = SendToCoreError.system("offline fixture", target.url.path, ENOTCONN)
        var restartDependencies = dependencies
        restartDependencies.probe = { _, completion in
            SendToCore.destinationError = nil
            completion(.success(.ready))
        }
        let offlineRestart = SendToWindowController(request: request)
        offlineRestart.fixtureReconnect(restartDependencies)
        offlineRestart.confirmPrevious = { alert in
            expect(alert.buttons[2].isEnabled, "offline restart remains an explicit selectable intent")
            return .alertThirdButtonReturn
        }
        SendToCore.events = []
        let beforeRestartResume = SendToCore.resumed.count
        offlineRestart.show()
        wait { !offlineRestart.isBusy && SendToCore.events.contains("copy") }
        expect(SendToCore.events == ["resolve", "resolve", "discard:" + task.id.uuidString, "copy"],
               "offline restart reconnects then revalidates target before safe discard and a new copy")
        expect(SendToCore.resumed.count == beforeRestartResume, "offline restart never calls resume on the old task")
        offlineRestart.fixtureClose()

        SendToCore.destinationError = SendToCoreError.system("offline fixture", target.url.path, ENOTCONN)
        var waitingDependencies = dependencies
        waitingDependencies.schedule = { _, _ in return {} }
        let pausedRestart = SendToWindowController(request: request)
        pausedRestart.fixtureReconnect(waitingDependencies)
        pausedRestart.confirmPrevious = { _ in .alertThirdButtonReturn }
        SendToCore.events = []
        pausedRestart.show()
        wait { pausedRestart.fixtureReconnecting }
        pausedRestart.cancel()
        wait { !pausedRestart.isBusy }
        expect(pausedRestart.fixturePendingRestart == task.id && SendToCore.events == ["resolve"],
               "cancelling offline restart retains its intent and all old temporary data")
        pausedRestart.fixtureContinue()
        wait { pausedRestart.fixtureReconnecting }
        pausedRestart.cancel()
        expect(SendToCore.resumed.count == beforeRestartResume && SendToCore.events == ["resolve", "resolve"],
               "explicit retry after cancelling restart preserves restart intent instead of resuming old task")
        pausedRestart.fixtureClose()

        var deniedDependencies = dependencies
        deniedDependencies.probe = { _, completion in
            completion(.failure(SendToCoreError.system("permission fixture", target.url.path, EACCES)))
        }
        let failedOfflineRestart = SendToWindowController(request: request)
        failedOfflineRestart.fixtureReconnect(deniedDependencies)
        failedOfflineRestart.confirmPrevious = { _ in .alertThirdButtonReturn }
        SendToCore.events = []
        failedOfflineRestart.show()
        wait { !failedOfflineRestart.isBusy }
        expect(failedOfflineRestart.fixturePendingRestart == task.id && SendToCore.events == ["resolve"] &&
               SendToCore.resumed.count == beforeRestartResume,
               "permission failure while reconnecting restart neither discards nor resumes nor creates a copy")
        failedOfflineRestart.fixtureClose()
        SendToCore.destinationError = nil

        let explicitConnection = SendToWindowController(task: task)
        explicitConnection.show()
        wait { !explicitConnection.isBusy }
        var opened = 0
        let explicitDependencies = SendToReconnectController.Dependencies.live(openShare: { _, completion in
            opened += 1
            completion(false)
        })
        explicitConnection.fixtureReconnect(explicitDependencies)
        let gate = DispatchSemaphore(value: 0)
        SendToCore.proofGate = gate
        SendToCore.proofStarted = false
        SendToCore.proofFinished = false
        explicitConnection.fixtureConnect()
        wait { SendToCore.proofStarted }
        explicitConnection.cancel()
        gate.signal()
        wait { SendToCore.proofFinished }
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        expect(opened == 0 && !explicitConnection.isBusy, "late proof after cancelling explicit connection never opens a system share window")
        SendToCore.proofGate = nil
        explicitConnection.fixtureClose()
    }
}
