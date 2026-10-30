//
//  FileCreatorFactories.swift
//  JobsFileCreatorShared
//
//  Created by Jobs on 2026年10月29日，星期四.
//

import AppKit
import FinderSync

extension NSMenu {

    static func make(title: String = "") -> NSMenu {
        let menu = NSMenu(title: title)
        menu.autoenablesItems = false
        return menu
    }

    @discardableResult
    func byAddItem(_ item: NSMenuItem) -> Self {
        addItem(item)
        return self
    }
}

extension NSMenuItem {

    static func make(title: String,
                     action: Selector? = nil,
                     target: AnyObject? = nil,
                     keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title,
                              action: action,
                              keyEquivalent: keyEquivalent)
        item.target = target
        return item
    }

    @discardableResult
    func bySubmenu(_ value: NSMenu) -> Self {
        submenu = value
        return self
    }

    @discardableResult
    func byTag(_ value: Int) -> Self {
        tag = value
        return self
    }
}

extension NSWorkspace.OpenConfiguration {

    static func make() -> NSWorkspace.OpenConfiguration {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.promptsUserIfNeeded = false
        configuration.addsToRecentItems = false
        configuration.allowsRunningApplicationSubstitution = false
        return configuration
    }
}

extension NSWorkspace {

    @discardableResult
    func byOpenURLs(_ urls: [URL],
                    withApplicationAt applicationURL: URL,
                    configuration: NSWorkspace.OpenConfiguration,
                    completionHandler: @escaping (NSRunningApplication?, Error?) -> Void) -> Self {
        open(urls,
             withApplicationAt: applicationURL,
             configuration: configuration,
             completionHandler: completionHandler)
        return self
    }
}

extension FIFinderSyncController {

    @discardableResult
    func byDirectoryURLs(_ urls: Set<URL>) -> Self {
        directoryURLs = urls
        return self
    }
}

extension NSApplication {

    @discardableResult
    func byDelegate(_ value: NSApplicationDelegate) -> Self {
        delegate = value
        return self
    }

    @discardableResult
    func byMainMenu(_ value: NSMenu) -> Self {
        mainMenu = value
        return self
    }
}

extension NSWindow {

    @discardableResult
    func byInitialFirstResponder(_ value: NSView) -> Self {
        initialFirstResponder = value
        return self
    }

    @discardableResult
    func byMakeFirstResponder(_ value: NSResponder) -> Self {
        makeFirstResponder(value)
        return self
    }
}

extension NSAlert {

    static func make() -> NSAlert {
        return NSAlert()
    }

    @discardableResult
    func byIcon(_ value: NSImage?) -> Self {
        icon = value
        return self
    }

    @discardableResult
    func byMessageText(_ value: String) -> Self {
        messageText = value
        return self
    }

    @discardableResult
    func byInformativeText(_ value: String) -> Self {
        informativeText = value
        return self
    }

    @discardableResult
    func byAlertStyle(_ value: NSAlert.Style) -> Self {
        alertStyle = value
        return self
    }

    @discardableResult
    func byAccessoryView(_ value: NSView) -> Self {
        accessoryView = value
        return self
    }

    @discardableResult
    func byAddButton(_ title: String) -> Self {
        addButton(withTitle: title)
        return self
    }
}

extension NSTextField {

    static func make(frame: NSRect) -> NSTextField {
        return NSTextField(frame: frame)
    }

    @discardableResult
    func byStringValue(_ value: String) -> Self {
        stringValue = value
        return self
    }

    @discardableResult
    func bySelectText(_ sender: Any?) -> Self {
        selectText(sender)
        return self
    }
}
