//
//  FileHashFactories.swift
//  JobsFileHasherShared
//
//  Created by Jobs on 2026年11月6日，星期五.
//

import AppKit
import FinderSync

extension NSMenu {

    static func make() -> NSMenu {
        let menu = NSMenu()
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
                     action: Selector,
                     target: AnyObject,
                     tag: Int) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = target
        item.tag = tag
        return item
    }
}

extension FIFinderSyncController {

    @discardableResult
    func byDirectoryURLs(_ urls: Set<URL>) -> Self {
        directoryURLs = urls
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
                    withApplicationAt app: URL,
                    configuration: NSWorkspace.OpenConfiguration,
                    completionHandler: @escaping (NSRunningApplication?, Error?) -> Void) -> Self {
        open(urls, withApplicationAt: app, configuration: configuration, completionHandler: completionHandler)
        return self
    }
}

extension NSApplication {

    @discardableResult
    func byDelegate(_ value: NSApplicationDelegate) -> Self {
        delegate = value
        return self
    }
}

extension NSAlert {

    static func make(message: String,
                     details: String) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = details
        alert.alertStyle = .warning
        alert.addButton(withTitle: "好")
        return alert
    }
}

extension NSAppleScript {

    static func make(source: String) -> NSAppleScript? {
        return NSAppleScript(source: source)
    }
}

extension Pipe {

    static func make() -> Pipe {
        return Pipe()
    }
}

extension Process {

    static func make(executableURL: URL,
                     arguments: [String] = [],
                     standardInput: Any? = nil) -> Process {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardInput = standardInput
        return process
    }
}

extension Bundle {

    static func make(url: URL) -> Bundle? {
        return Bundle(url: url)
    }
}
