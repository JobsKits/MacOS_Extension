//
//  JobsRevocationFactories.swift
//  JobsRunRevocationShared
//
//  Created by Jobs on 2026年10月24日，星期六.
//

import AppKit
import FinderSync

/// 独立 Finder 工程不引入 iOS Pods，系统对象的创建和配置在本地工厂层收口。
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

extension FileHandle {
    static func make(forWritingTo url: URL) throws -> FileHandle {
        return try FileHandle(forWritingTo: url)
    }
}

extension NSError {
    static func make(domain: String, message: String) -> NSError {
        return NSError(domain: domain, code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

extension DispatchWorkItem {
    static func make(block: @escaping () -> Void) -> DispatchWorkItem {
        return DispatchWorkItem(block: block)
    }
}

extension NSMenu {
    static func make(title: String) -> NSMenu {
        return NSMenu(title: title)
    }

    @discardableResult
    func byAddItem(_ value: NSMenuItem) -> Self {
        addItem(value)
        return self
    }
}

extension NSMenuItem {
    static func make(title: String, action: Selector, keyEquivalent: String, configure: (NSMenuItem) -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        configure(item)
        return item
    }

    @discardableResult
    func byTarget(_ value: AnyObject) -> Self {
        target = value
        return self
    }
}

extension NSAlert {
    static func jobsMake(_ configure: (NSAlert) -> Void) -> NSAlert {
        let alert = NSAlert()
        configure(alert)
        return alert
    }

    @discardableResult
    func byAlertStyle(_ value: NSAlert.Style) -> Self {
        alertStyle = value
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
    func byAddButton(_ title: String) -> Self {
        addButton(withTitle: title)
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

extension FIFinderSyncController {
    @discardableResult
    func byDirectoryURLs(_ value: Set<URL>) -> Self {
        directoryURLs = value
        return self
    }
}
