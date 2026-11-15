//
//  CommandShortcutDialog.swift
//  JobsCommandShortcutCreator
//
//  Created by Jobs on 2026年11月13日，星期五.
//

import AppKit

final class CommandShortcutDialog: NSObject {

    private var didChangePreferences = false

    func ask(directory: URL, name: String, error: String?) -> String? {
        var currentName = name
        repeat {
            didChangePreferences = false
            CommandShortcutLocalization.applyAppearance()
            CommandShortcutInterface.installEditingMenu()
            NSApp.activate(ignoringOtherApps: true)
            let field = NSTextField.make(frame: NSRect(x: 0, y: 0, width: 460, height: 26))
                .byStringValue(currentName)
                .byWidth(460)
            let languages = ["system"] + CommandShortcutLocalization.languages
            let language = NSPopUpButton.make(frame: NSRect(x: 0, y: 0, width: 230, height: 30))
                .byItems([CommandShortcutLocalization.text("system")] + CommandShortcutLocalization.languageNames)
                .bySelectedIndex(languages.firstIndex(of: CommandShortcutLocalization.defaults.string(forKey: "language") ?? "system") ?? 0)
                .byTarget(self)
                .byAction(#selector(languageChanged(_:)))
                .byAccessibilityLabel(CommandShortcutLocalization.text("language"))
                .byWidth(225)
            let theme = NSPopUpButton.make(frame: NSRect(x: 0, y: 0, width: 230, height: 30))
                .byItems(["system", "light", "dark"].map(CommandShortcutLocalization.text))
                .bySelectedIndex(["system", "light", "dark"].firstIndex(of: CommandShortcutLocalization.defaults.string(forKey: "theme") ?? "system") ?? 0)
                .byTarget(self)
                .byAction(#selector(themeChanged(_:)))
                .byAccessibilityLabel(CommandShortcutLocalization.text("theme"))
                .byWidth(225)
            let languageColumn = NSStackView.make(views: [NSTextField.make(labelWithString: CommandShortcutLocalization.text("language")), language])
                .byOrientation(.vertical)
                .byAlignment(.leading)
                .bySpacing(4)
            let themeColumn = NSStackView.make(views: [NSTextField.make(labelWithString: CommandShortcutLocalization.text("theme")), theme])
                .byOrientation(.vertical)
                .byAlignment(.leading)
                .bySpacing(4)
            let controls = NSStackView.make(views: [languageColumn, themeColumn])
                .byOrientation(.horizontal)
                .byDistribution(.fillEqually)
            let stack = NSStackView.make(views: [field, controls])
                .byOrientation(.vertical)
                .byAlignment(.leading)
                .bySpacing(10)
                .byFrame(NSRect(x: 0, y: 0, width: 460, height: 100))
            let alert = NSAlert.make()
                .byMessageText(CommandShortcutLocalization.text("title"))
                .byInformativeText((error ?? CommandShortcutLocalization.text("prompt")) + "\n\n" + directory.deletingLastPathComponent().path)
                .byAlertStyle(error == nil ? .informational : .warning)
                .byAccessoryView(stack)
                .byAddButton(CommandShortcutLocalization.text("create"))
                .byAddButton(CommandShortcutLocalization.text("cancel"))
            alert.window.byInitialFirstResponder(field).byMakeFirstResponder(field)
            field.bySelectText(nil)
            let response = alert.runModal()
            currentName = field.stringValue
            if !didChangePreferences {
                return response == .alertFirstButtonReturn ? currentName : nil
            }
        } while didChangePreferences
        return nil
    }

    @objc private func languageChanged(_ sender: NSPopUpButton) {
        let languages = ["system"] + CommandShortcutLocalization.languages
        guard languages.indices.contains(sender.indexOfSelectedItem) else {
            return
        }
        CommandShortcutLocalization.defaults.set(languages[sender.indexOfSelectedItem], forKey: "language")
        didChangePreferences = true
        NSApp.abortModal()
    }

    @objc private func themeChanged(_ sender: NSPopUpButton) {
        let themes = ["system", "light", "dark"]
        guard themes.indices.contains(sender.indexOfSelectedItem) else {
            return
        }
        CommandShortcutLocalization.defaults.set(themes[sender.indexOfSelectedItem], forKey: "theme")
        didChangePreferences = true
        NSApp.abortModal()
    }
}
