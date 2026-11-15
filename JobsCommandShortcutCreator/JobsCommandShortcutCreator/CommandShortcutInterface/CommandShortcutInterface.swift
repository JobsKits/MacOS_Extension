//
//  CommandShortcutInterface.swift
//  JobsCommandShortcutCreator
//
//  Created by Jobs on 2026年11月13日，星期五.
//

import AppKit

enum CommandShortcutInterface {

    static func installEditingMenu() {
        let editMenu = NSMenu.make(title: CommandShortcutLocalization.text("edit"))
        for (key, selector, equivalent) in [
            ("cut", #selector(NSText.cut(_:)), "x"),
            ("copy", #selector(NSText.copy(_:)), "c"),
            ("paste", #selector(NSText.paste(_:)), "v"),
            ("selectAll", #selector(NSText.selectAll(_:)), "a")
        ] {
            editMenu.byAddItem(NSMenuItem.make(title: CommandShortcutLocalization.text(key), action: selector, keyEquivalent: equivalent))
        }
        NSApp.byMainMenu(NSMenu.make()
            .byAddItem(NSMenuItem.make(title: CommandShortcutLocalization.text("title"))
                .bySubmenu(NSMenu.make()
                    .byAddItem(NSMenuItem.make(title: CommandShortcutLocalization.text("quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))))
            .byAddItem(NSMenuItem.make(title: CommandShortcutLocalization.text("edit")).bySubmenu(editMenu)))
    }

    static func askName(directory: URL, name: String, error: String?) -> String? {
        return CommandShortcutDialog().ask(directory: directory, name: name, error: error)
    }

    static func showFailure(_ message: String) {
        CommandShortcutLocalization.applyAppearance()
        NSApp.activate(ignoringOtherApps: true)
        NSAlert.make()
            .byMessageText(CommandShortcutLocalization.text("failureTitle"))
            .byInformativeText(message)
            .byAlertStyle(.warning)
            .byAddButton(CommandShortcutLocalization.text("ok"))
            .runModal()
    }
}
