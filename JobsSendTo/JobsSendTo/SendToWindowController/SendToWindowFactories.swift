//
//  SendToWindowFactories.swift
//  JobsSendTo
//
//  Created by Jobs on 2026年11月18日，星期三.
//

import AppKit

extension NSOpenPanel {

    static func makeSendToFolderPanel(directory: URL, message: String, prompt: String,
                                      delegate: NSOpenSavePanelDelegate) -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.resolvesAliases = false
        panel.directoryURL = directory
        panel.message = message
        panel.prompt = prompt
        panel.delegate = delegate
        return panel
    }
}

extension NSView {

    static func makeSendToView() -> NSView {
        return NSView(frame: NSRect(x: 0, y: 0, width: 760, height: 650))
    }

    @discardableResult
    func bySendToFrame(_ value: NSRect) -> Self {
        frame = value
        return self
    }

    @discardableResult
    func bySendToHidden(_ value: Bool) -> Self {
        isHidden = value
        return self
    }

    @discardableResult
    func bySendToAddSubview(_ view: NSView) -> Self {
        addSubview(view)
        return self
    }
}

extension NSWindow {

    static func makeSendToWindow(delegate: NSWindowDelegate) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 650),
                                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                backing: .buffered, defer: false)
        window.delegate = delegate
        window.minSize = NSSize(width: 760, height: 650)
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    @discardableResult
    func bySendToTitle(_ value: String) -> Self {
        title = value
        return self
    }

    @discardableResult
    func bySendToContentView(_ value: NSView) -> Self {
        contentView = value
        return self
    }

    @discardableResult
    func bySendToShow() -> Self {
        makeKeyAndOrderFront(nil)
        return self
    }
}

extension NSTextField {

    static func makeSendToLabel(large: Bool = false) -> NSTextField {
        let field = NSTextField(labelWithString: "")
        field.font = large ? NSFont.boldSystemFont(ofSize: 22) : NSFont.systemFont(ofSize: 13)
        field.textColor = .labelColor
        field.cell?.wraps = true
        field.cell?.isScrollable = false
        field.maximumNumberOfLines = 0
        field.isSelectable = true
        return field
    }
}

extension NSButton {

    static func makeSendToButton(target: AnyObject, action: Selector) -> NSButton {
        let button = NSButton(title: "", target: target, action: action)
        button.bezelStyle = .rounded
        return button
    }

    @discardableResult
    func bySendToTitle(_ value: String) -> Self {
        title = value
        return self
    }

    @discardableResult
    func bySendToEnabled(_ value: Bool) -> Self {
        isEnabled = value
        return self
    }

    @discardableResult
    func bySendToDestructive(_ value: Bool) -> Self {
        hasDestructiveAction = value
        return self
    }
}

extension NSTableView {

    static func makeSendToTaskTable(dataSource: NSTableViewDataSource,
                                     delegate: NSTableViewDelegate) -> NSTableView {
        let table = NSTableView(frame: .zero)
        for key in ["task", "state", "progress", "updated"] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(key))
            column.width = key == "task" ? 230 : (key == "progress" ? 110 : 160)
            column.minWidth = 80
            let cell = NSTextFieldCell(textCell: "")
            cell.wraps = true
            cell.lineBreakMode = .byWordWrapping
            cell.font = NSFont.systemFont(ofSize: 12)
            cell.textColor = .labelColor
            column.dataCell = cell
            table.addTableColumn(column)
        }
        table.dataSource = dataSource
        table.delegate = delegate
        table.allowsMultipleSelection = false
        table.allowsEmptySelection = true
        table.rowHeight = 42
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        return table
    }

    @discardableResult
    func bySendToReload(selectedRow: Int?) -> Self {
        reloadData()
        if let selectedRow {
            selectRowIndexes(IndexSet(integer: selectedRow), byExtendingSelection: false)
        } else {
            deselectAll(nil)
        }
        return self
    }

    @discardableResult
    func bySendToHeaders(_ titles: [String]) -> Self {
        for (column, title) in zip(tableColumns, titles) {
            column.title = title
        }
        return self
    }
}

extension NSPopUpButton {

    @discardableResult
    func bySendToReplaceItems(_ values: [String]) -> Self {
        removeAllItems()
        addItems(withTitles: values)
        return self
    }
}

extension NSTextView {

    static func makeSendToTextView() -> NSTextView {
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 690, height: 180))
        text.isEditable = false
        text.isSelectable = true
        text.isRichText = false
        text.font = NSFont.systemFont(ofSize: 13)
        text.textColor = .textColor
        text.backgroundColor = .textBackgroundColor
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        text.textContainerInset = NSSize(width: 8, height: 8)
        return text
    }

    @discardableResult
    func bySendToText(_ value: String) -> Self {
        if string != value {
            string = value
        }
        return self
    }
}

extension NSScrollView {

    static func makeSendToScroll(text: NSTextView) -> NSScrollView {
        let scroll = NSScrollView(frame: .zero)
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder
        scroll.documentView = text
        return scroll
    }

    static func makeSendToTaskScroll(table: NSTableView) -> NSScrollView {
        let scroll = NSScrollView(frame: .zero)
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder
        scroll.documentView = table
        return scroll
    }
}

extension NSProgressIndicator {

    static func makeSendToActivity() -> NSProgressIndicator {
        let indicator = NSProgressIndicator(frame: .zero)
        indicator.style = .spinning
        indicator.isIndeterminate = true
        indicator.isDisplayedWhenStopped = false
        return indicator
    }

    @discardableResult
    func bySendToActive(_ value: Bool) -> Self {
        if value {
            startAnimation(nil)
        } else {
            stopAnimation(nil)
        }
        return self
    }
}
