//
//  CommandShortcutController.swift
//  JobsCommandShortcutCreator
//
//  Created by Jobs on 2026年11月13日，星期五.
//

import AppKit

struct CommandShortcutController {

    var askName: (URL, String, String?) -> String? = CommandShortcutInterface.askName
    var reveal: (URL) -> Void = { url in
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    var createFile: (String, URL) throws -> URL = { name, directory in
        return try CommandShortcutService().create(name: name, in: directory)
    }

    func run(in directory: URL) {
        var name = directory.deletingPathExtension().lastPathComponent + CommandShortcutLocalization.text("suffix") + ".command"
        var errorMessage: String?
        while let entered = askName(directory, name, errorMessage) {
            name = entered
            do {
                let url = try createFile(entered, directory)
                reveal(url)
                return
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
