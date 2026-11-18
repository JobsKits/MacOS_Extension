//
//  FileVisibilityController.swift
//  JobsFileVisibility
//
//  Created by Jobs on 2026年11月18日，星期三.
//

import AppKit

final class FileVisibilityController {

    func run(_ request: FileVisibilityRequest) {
        var succeeded = 0
        var failures: [String] = []
        var dotNames = false
        for item in request.items {
            do {
                try FileVisibilityService.apply(item, hidden: request.hidden)
                succeeded += 1
                dotNames = dotNames || (!request.hidden && item.url.lastPathComponent.hasPrefix("."))
                NSWorkspace.shared.noteFileSystemChanged(item.url.deletingLastPathComponent().path)
            } catch {
                failures.append(item.path + " — " + error.localizedDescription)
            }
        }
        guard !failures.isEmpty || dotNames else {
            return
        }
        FileVisibilityInterface.show(warning: true) {
            var message = FileVisibilityLocalization.text(request.hidden ? "hiddenResult" : "shownResult") + ": \(succeeded)"
            if dotNames {
                message += "\n\n" + FileVisibilityLocalization.text("dotName")
            }
            if !failures.isEmpty {
                message += "\n\n" + FileVisibilityLocalization.text("failed") + ": \(failures.count)\n" + failures.joined(separator: "\n")
            }
            return message
        }
    }
}
