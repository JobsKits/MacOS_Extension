//
//  PermanentDeleteInterfaceTests.swift
//  JobsPermanentDeleter
//
//  Created by Jobs on 2026年11月18日，星期三.
//

import AppKit

@main
struct PermanentDeleteInterfaceTests {

    // Exercise actual AppKit buttons and keyboard routing; never call the deletion controller.
    static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let suite = "com.jobs.permanentdelete.tests." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        PermanentDeleteLocalization.defaults = preferences
        defer {
            preferences.removePersistentDomain(forName: suite)
        }
        preferences.set("zh-Hans", forKey: "language")
        preferences.set("light", forKey: "theme")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("JobsDeleteUITest-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let file = directory.appendingPathComponent("仅用于确认框验证.txt")
        try Data("must remain".utf8).write(to: file)
        let item = PermanentDeleteContext.snapshot(file)!
        let ui = PermanentDeleteInterface()
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ reason: String) {
            precondition(condition(), reason)
            checks += 1
        }
        ui.buildConfirmation([item])
        check(ui.confirmButton!.frame.maxX < ui.cancelButton!.frame.minX, "confirm on left")
        check(ui.confirmButton!.fill.redComponent > ui.confirmButton!.fill.blueComponent, "confirm red background")
        check(ui.cancelButton!.fill.blueComponent > ui.cancelButton!.fill.redComponent, "cancel blue background")
        check(ui.window!.defaultButtonCell === ui.cancelButton!.cell, "default is cancel")
        for key in ["title", "confirm", "scope", "warning", "menu", "remaining", "partial", "deleting", "deleted", "invalidTarget"] {
            check(PermanentDeleteLocalization.translations[key]?.count == 10, "complete language table: " + key)
        }
        func run(_ action: @escaping () -> Void) -> Bool {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: action)
            return ui.confirm([item])
        }
        check(!run { ui.cancelButton!.performClick(nil) }, "blue cancels")
        check(!run { ui.window!.performClose(nil) }, "close cancels")
        let preview = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/JobsPermanentDeleteConfirmation.png"
        check(!run {
            ui.window!.makeFirstResponder(ui.confirmButton!)
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                         windowNumber: ui.window!.windowNumber, context: nil,
                                         characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
            app.sendEvent(event)
        }, "Return cancels even when red button focused")
        check(!run {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                         windowNumber: ui.window!.windowNumber, context: nil,
                                         characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
            app.sendEvent(event)
        }, "Escape cancels")
        check(run { ui.confirmButton!.performClick(nil) }, "only explicit red confirms")
        check(!run {
            let capture = Process()
            capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            capture.arguments = ["-x", "-l", String(ui.window!.windowNumber), preview]
            try! capture.run()
            capture.waitUntilExit()
            ui.cancelButton!.performClick(nil)
        }, "preview capture cancels safely")
        check(FileManager.default.fileExists(atPath: file.path), "UI never deletes")
        print("PermanentDeleteInterfaceTests: \(checks) checks passed; preview: \(preview)")
    }
}
