//
//  FileVisibilityInterface.swift
//  JobsFileVisibility
//
//  Created by Jobs on 2026年11月18日，星期三.
//

import AppKit

final class FileVisibilityInterface: NSObject {

    private var preferencesChanged = false

    static func installEditingMenu() {
        NSApp.byMainMenu(NSMenu.make()
            .byAddItem(NSMenuItem.make(title: FileVisibilityLocalization.text("title"))
                .bySubmenu(NSMenu.make()
                    .byAddItem(NSMenuItem.make(title: FileVisibilityLocalization.text("quit"),
                                                action: #selector(NSApplication.terminate(_:)),
                                                keyEquivalent: "q")))))
    }

    static func show(warning: Bool, message: () -> String) {
        FileVisibilityInterface().present(warning: warning, message: message)
    }

    private func present(warning: Bool, message: () -> String) {
        repeat {
            preferencesChanged = false
            FileVisibilityLocalization.applyAppearance()
            Self.installEditingMenu()
            NSApp.activate(ignoringOtherApps: true)
            let languages = ["system"] + FileVisibilityLocalization.languages
            let language = NSPopUpButton.make(frame: NSRect(x: 0, y: 0, width: 250, height: 30))
                .byItems([FileVisibilityLocalization.text("system")] + FileVisibilityLocalization.languageNames)
                .bySelectedIndex(languages.firstIndex(of: FileVisibilityLocalization.defaults.string(forKey: "language") ?? "system") ?? 0)
                .byTarget(self)
                .byAction(#selector(languageChanged(_:)))
                .byAccessibilityLabel(FileVisibilityLocalization.text("language"))
            let theme = NSPopUpButton.make(frame: NSRect(x: 0, y: 0, width: 250, height: 30))
                .byItems(["system", "light", "dark"].map(FileVisibilityLocalization.text))
                .bySelectedIndex(["system", "light", "dark"].firstIndex(of: FileVisibilityLocalization.defaults.string(forKey: "theme") ?? "system") ?? 0)
                .byTarget(self)
                .byAction(#selector(themeChanged(_:)))
                .byAccessibilityLabel(FileVisibilityLocalization.text("theme"))
            let text = NSTextField.make(labelWithString: message())
                .byWrapping(true)
            let scroll = NSScrollView.make(document: text,
                                            frame: NSRect(x: 0, y: 0, width: 520, height: 220))
            let controls = NSStackView.make(views: [language, theme])
                .byOrientation(.horizontal)
                .byDistribution(.fillEqually)
            let stack = NSStackView.make(views: [scroll, controls])
                .byOrientation(.vertical)
                .byAlignment(.leading)
                .bySpacing(10)
                .byFrame(NSRect(x: 0, y: 0, width: 520, height: 265))
            let alert = NSAlert.make()
                .byMessageText(FileVisibilityLocalization.text("title"))
                .byAlertStyle(warning ? .warning : .informational)
                .byAccessoryView(stack)
                .byAddButton(FileVisibilityLocalization.text("ok"))
            _ = alert.runModal()
            if !preferencesChanged {
                return
            }
        } while preferencesChanged
    }

    @objc private func languageChanged(_ sender: NSPopUpButton) {
        let values = ["system"] + FileVisibilityLocalization.languages
        guard values.indices.contains(sender.indexOfSelectedItem) else {
            return
        }
        FileVisibilityLocalization.defaults.set(values[sender.indexOfSelectedItem], forKey: "language")
        preferencesChanged = true
        NSApp.abortModal()
    }

    @objc private func themeChanged(_ sender: NSPopUpButton) {
        let values = ["system", "light", "dark"]
        guard values.indices.contains(sender.indexOfSelectedItem) else {
            return
        }
        FileVisibilityLocalization.defaults.set(values[sender.indexOfSelectedItem], forKey: "theme")
        preferencesChanged = true
        NSApp.abortModal()
    }
}
