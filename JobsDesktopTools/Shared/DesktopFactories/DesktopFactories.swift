//
//  DesktopFactories.swift
//  JobsDesktopToolsShared
//
//  Created by Jobs on 2026年10月26日，星期一.
//

import AppKit
import FinderSync

extension NSMenu {
    static func make(title: String) -> NSMenu {
        let menu = NSMenu(title: title)
        menu.autoenablesItems = false
        return menu
    }
}

extension NSMenuItem {
    static func make(title: String, action: Selector?, target: AnyObject, enabled: Bool = true) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = target
        item.isEnabled = enabled
        return item
    }
}

enum DesktopAlert {
    static func show(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "桌面工具操作未完成"
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}

extension Process {
    static func jobsMake(_ configure: (Process) -> Void) -> Process {
        let process = Process()
        configure(process)
        return process
    }

    @discardableResult
    func byExecutableURL(_ value: URL) -> Self {
        executableURL = value
        return self
    }

    @discardableResult
    func byArguments(_ value: [String]) -> Self {
        arguments = value
        return self
    }

    @discardableResult
    func byEnvironment(_ value: [String: String]) -> Self {
        environment = value
        return self
    }

    @discardableResult
    func byStandardOutput(_ value: Any) -> Self {
        standardOutput = value
        return self
    }

    @discardableResult
    func byStandardError(_ value: Any) -> Self {
        standardError = value
        return self
    }
}

extension Pipe {
    static func make() -> Pipe {
        return Pipe()
    }
}

extension NSError {
    static func make(domain: String, message: String) -> NSError {
        return NSError(domain: domain, code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}


extension FIFinderSyncController {
    @discardableResult
    func byDirectoryURLs(_ value: Set<URL>) -> Self {
        directoryURLs = value
        return self
    }
}

extension NSMenu {
    @discardableResult
    func byAddItem(_ value: NSMenuItem) -> Self {
        addItem(value)
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
