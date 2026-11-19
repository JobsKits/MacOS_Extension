//
//  PermanentDeleteControllerTests.swift
//  JobsPermanentDeleter
//
//  Created by Jobs on 2026年11月18日，星期三.
//

import AppKit

@main
struct PermanentDeleteControllerTests {

    // Drive the full confirmation-worker-result loop against only this process's temporary fixture.
    static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let suite = "com.jobs.permanentdelete.controller.tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        PermanentDeleteLocalization.defaults = defaults
        defaults.set("en", forKey: "language")
        defer {
            defaults.removePersistentDomain(forName: suite)
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("JobsDeleteController-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let file = directory.appendingPathComponent("owned-fixture.txt")
        try Data("fixture".utf8).write(to: file)
        let request = PermanentDeleteRequest(urls: [file])!
        var confirmed = false
        var resultDismissed = false
        var timedOut = false
        let start = Date()
        let timer = Timer(timeInterval: 0.05, repeats: true) { timer in
            guard Date().timeIntervalSince(start) < 5 else {
                timedOut = true
                timer.invalidate()
                PermanentDeleteInterface.finishModal()
                return
            }
            guard let window = app.modalWindow else {
                return
            }
            let controls = buttons(window.contentView!)
            if !confirmed, let red = controls.compactMap({ $0 as? PermanentDeleteButton }).first(where: { $0.title == "Confirm" }) {
                confirmed = true
                red.performClick(nil)
            } else if confirmed, !PermanentDeleteController.busy,
                      let ok = controls.first(where: { !($0 is PermanentDeleteButton) && $0.title == "OK" }) {
                resultDismissed = true
                ok.performClick(nil)
                timer.invalidate()
            }
        }
        RunLoop.main.add(timer, forMode: .modalPanel)
        PermanentDeleteController().run(request)
        timer.invalidate()
        precondition(!timedOut, "worker result loop must wake without further user input")
        precondition(confirmed && resultDismissed, "complete confirmation-to-result flow")
        precondition(!PermanentDeleteController.busy, "worker ended")
        precondition(!FileManager.default.fileExists(atPath: file.path), "fixture was deleted only after confirmation")
        print("PermanentDeleteControllerTests: 4 checks passed; background completion woke the modal loop")
    }

    // Search actual nested AppKit controls rather than using screenshot coordinates.
    private static func buttons(_ view: NSView) -> [NSButton] {
        return (view as? NSButton).map { [$0] } ?? view.subviews.flatMap(buttons)
    }
}
