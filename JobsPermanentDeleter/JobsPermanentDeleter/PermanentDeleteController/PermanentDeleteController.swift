//
//  PermanentDeleteController.swift
//  JobsPermanentDeleter
//
//  Created by Jobs on 2026年11月18日，星期三.
//

import AppKit

final class PermanentDeleteController {

    static var busy = false

    // The only route to the destructive service is an explicit confirmation for this immutable selection.
    func run(_ request: PermanentDeleteRequest) {
        guard PermanentDeleteInterface().confirm(request.items) else {
            return
        }
        PermanentDeleteDiagnostics.remaining = PermanentDeleteLocalization.text("remaining")
        PermanentDeleteDiagnostics.partial = PermanentDeleteLocalization.text("partial")
        var succeeded = 0
        var failures: [String] = []
        let progress = PermanentDeletePanel.make(contentRect: NSRect(x: 0, y: 0, width: 520, height: 110), styleMask: [.titled])
        progress.title = PermanentDeleteLocalization.text("title")
        let label = NSTextField.make(labelWithString: PermanentDeleteLocalization.text("deleting"))
            .byWrapping(true)
        label.frame = NSRect(x: 20, y: 20, width: 480, height: 70)
        progress.contentView?.addSubview(label)
        progress.center()
        progress.makeKeyAndOrderFront(nil)
        Self.busy = true
        DispatchQueue.global(qos: .userInitiated).async {
            for item in request.items {
                do {
                    try PermanentDeleteService.apply(item)
                    succeeded += 1
                } catch {
                    failures.append(item.path + " — " + error.localizedDescription)
                }
            }
            DispatchQueue.main.async {
                Self.busy = false
                NSApp.stopModal()
            }
        }
        _ = NSApp.runModal(for: progress)
        progress.orderOut(nil)
        for item in request.items {
            NSWorkspace.shared.noteFileSystemChanged(item.url.deletingLastPathComponent().path)
        }
        PermanentDeleteInterface.show(warning: !failures.isEmpty) {
            var message = PermanentDeleteLocalization.text("deleted") + ": \(succeeded)"
            if !failures.isEmpty {
                message += "\n\n" + PermanentDeleteLocalization.text("failed") + ": \(failures.count)\n" + failures.joined(separator: "\n")
            }
            return message
        }
    }
}
