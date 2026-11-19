//
//  PermanentDeleteInterface.swift
//  JobsPermanentDeleter
//
//  Created by Jobs on 2026年11月18日，星期三.
//

import AppKit

final class PermanentDeletePanel: NSPanel {

    var cancelHandler: (() -> Void)?

    // Route Escape through the exact same cancellation as the blue button.
    override func cancelOperation(_ sender: Any?) {
        cancelHandler?()
    }
}

final class PermanentDeleteButton: NSButton {

    let fill: NSColor

    init(title: String, fill: NSColor, target: AnyObject?, action: Selector) {
        self.fill = fill
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        setButtonType(.momentaryPushIn)
        isBordered = false
        font = NSFont.systemFont(ofSize: 16, weight: .semibold)
        setAccessibilityLabel(title)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    // Own the full background and title so native accent styling cannot reverse the requested colors.
    override func draw(_ dirtyRect: NSRect) {
        (isHighlighted ? fill.blended(withFraction: 0.18, of: .black) ?? fill : fill).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 8, yRadius: 8).fill()
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [.font: font ?? NSFont.systemFont(ofSize: 16),
                                                          .foregroundColor: NSColor.white,
                                                          .paragraphStyle: paragraph]
        let height = (title as NSString).size(withAttributes: attributes).height
        (title as NSString).draw(in: NSRect(x: 5, y: (bounds.height - height) / 2, width: bounds.width - 10, height: height), withAttributes: attributes)
        if window?.firstResponder === self {
            NSColor.keyboardFocusIndicatorColor.setStroke()
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10)
            ring.lineWidth = 2
            ring.stroke()
        }
    }
}

final class PermanentDeleteInterface: NSObject, NSWindowDelegate {

    private var preferencesChanged = false
    private(set) var window: NSPanel?
    private(set) var confirmButton: PermanentDeleteButton?
    private(set) var cancelButton: PermanentDeleteButton?
    private var confirmed = false

    // Stop nested modal sessions and wake AppKit even when the worker produced no input events.
    static func finishModal() {
        NSApp.stopModal()
        if let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [],
                                          timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) {
            NSApp.postEvent(event, atStart: false)
        }
    }

    // Supply the ordinary quit command; closing a confirmation never authorizes deletion.
    static func installEditingMenu() {
        NSApp.byMainMenu(NSMenu.make()
            .byAddItem(NSMenuItem.make(title: PermanentDeleteLocalization.text("title"))
                .bySubmenu(NSMenu.make()
                    .byAddItem(NSMenuItem.make(title: PermanentDeleteLocalization.text("quit"),
                                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")))))
    }

    // All exit paths begin cancelled; only the red button can grant this particular request.
    func confirm(_ items: [PermanentDeleteContext.Item]) -> Bool {
        repeat {
            preferencesChanged = false
            confirmed = false
            buildConfirmation(items)
            NSApp.activate(ignoringOtherApps: true)
            guard let window else {
                return false
            }
            window.makeKeyAndOrderFront(nil)
            _ = NSApp.runModal(for: window)
            window.orderOut(nil)
            if !preferencesChanged {
                return confirmed
            }
        } while preferencesChanged
        return false
    }

    // Build native controls separately so tests can exercise the real color, key and close behavior.
    func buildConfirmation(_ items: [PermanentDeleteContext.Item]) {
        PermanentDeleteLocalization.applyAppearance()
        Self.installEditingMenu()
        let panel = PermanentDeletePanel.make(contentRect: NSRect(x: 0, y: 0, width: 680, height: 465),
                                 styleMask: [.titled, .closable])
        panel.title = PermanentDeleteLocalization.text("title")
        panel.delegate = self
        panel.cancelHandler = { [weak self] in
            self?.cancelClicked(nil)
        }
        panel.isReleasedWhenClosed = false
        let content = panel.contentView!
        let heading = NSTextField.make(labelWithString: PermanentDeleteLocalization.text("warning"))
        heading.font = NSFont.boldSystemFont(ofSize: 19)
        heading.frame = NSRect(x: 24, y: 420, width: 632, height: 28)
        let warning = NSTextField.make(labelWithString: PermanentDeleteLocalization.text("scope"))
            .byWrapping(true)
        warning.frame = NSRect(x: 24, y: 341, width: 632, height: 74)
        let text = NSTextField.make(labelWithString: items.map(\.path).joined(separator: "\n"))
            .byWrapping(true)
        let scroll = NSScrollView.make(document: text, frame: NSRect(x: 24, y: 128, width: 632, height: 202))
        scroll.setAccessibilityLabel(PermanentDeleteLocalization.text("targets"))
        let language = NSPopUpButton.make(frame: NSRect(x: 24, y: 87, width: 310, height: 30))
            .byItems([PermanentDeleteLocalization.text("system")] + PermanentDeleteLocalization.languageNames)
            .bySelectedIndex((["system"] + PermanentDeleteLocalization.languages).firstIndex(of: PermanentDeleteLocalization.defaults.string(forKey: "language") ?? "system") ?? 0)
            .byTarget(self)
            .byAction(#selector(languageChanged(_:)))
            .byAccessibilityLabel(PermanentDeleteLocalization.text("language"))
        let theme = NSPopUpButton.make(frame: NSRect(x: 346, y: 87, width: 310, height: 30))
            .byItems(["system", "light", "dark"].map(PermanentDeleteLocalization.text))
            .bySelectedIndex(["system", "light", "dark"].firstIndex(of: PermanentDeleteLocalization.defaults.string(forKey: "theme") ?? "system") ?? 0)
            .byTarget(self)
            .byAction(#selector(themeChanged(_:)))
            .byAccessibilityLabel(PermanentDeleteLocalization.text("theme"))
        let confirm = PermanentDeleteButton(title: PermanentDeleteLocalization.text("confirm"),
                                           fill: NSColor(srgbRed: 180 / 255, green: 35 / 255, blue: 24 / 255, alpha: 1),
                                           target: self, action: #selector(confirmClicked(_:)))
        confirm.frame = NSRect(x: 24, y: 23, width: 310, height: 48)
        let cancel = PermanentDeleteButton(title: PermanentDeleteLocalization.text("cancel"),
                                          fill: NSColor(srgbRed: 23 / 255, green: 92 / 255, blue: 211 / 255, alpha: 1),
                                          target: self, action: #selector(cancelClicked(_:)))
        cancel.frame = NSRect(x: 346, y: 23, width: 310, height: 48)
        cancel.keyEquivalent = "\r"
        panel.defaultButtonCell = cancel.cell as? NSButtonCell
        confirm.nextKeyView = cancel
        cancel.nextKeyView = language
        language.nextKeyView = theme
        theme.nextKeyView = confirm
        [heading, warning, scroll, language, theme, confirm, cancel].forEach(content.addSubview)
        panel.center()
        panel.initialFirstResponder = cancel
        self.window = panel
        self.confirmButton = confirm
        self.cancelButton = cancel
    }

    // Present complete results while preserving raw filesystem diagnostics and exact remaining paths.
    static func show(warning: Bool, message: () -> String) {
        PermanentDeleteLocalization.applyAppearance()
        let text = NSTextField.make(labelWithString: message()).byWrapping(true)
        let scroll = NSScrollView.make(document: text, frame: NSRect(x: 0, y: 0, width: 570, height: 250))
        NSAlert.make()
            .byMessageText(PermanentDeleteLocalization.text("title"))
            .byAccessoryView(scroll)
            .byAlertStyle(warning ? .warning : .informational)
            .byAddButton(PermanentDeleteLocalization.text("ok"))
            .runModal()
    }

    @objc private func confirmClicked(_ sender: Any?) {
        confirmed = true
        Self.finishModal()
    }

    @objc private func cancelClicked(_ sender: Any?) {
        confirmed = false
        Self.finishModal()
    }

    // Escape is routed by the panel responder chain to the same cancelled outcome.
    @objc func cancelOperation(_ sender: Any?) {
        cancelClicked(sender)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        cancelClicked(sender)
        return true
    }

    @objc private func languageChanged(_ sender: NSPopUpButton) {
        let values = ["system"] + PermanentDeleteLocalization.languages
        guard values.indices.contains(sender.indexOfSelectedItem) else {
            return
        }
        PermanentDeleteLocalization.defaults.set(values[sender.indexOfSelectedItem], forKey: "language")
        preferencesChanged = true
        Self.finishModal()
    }

    @objc private func themeChanged(_ sender: NSPopUpButton) {
        let values = ["system", "light", "dark"]
        guard values.indices.contains(sender.indexOfSelectedItem) else {
            return
        }
        PermanentDeleteLocalization.defaults.set(values[sender.indexOfSelectedItem], forKey: "theme")
        preferencesChanged = true
        Self.finishModal()
    }
}

extension PermanentDeletePanel {

    // Construct one modal window without relying on a storyboard or another installed application.
    static func make(contentRect: NSRect, styleMask: NSWindow.StyleMask) -> PermanentDeletePanel {
        return PermanentDeletePanel(contentRect: contentRect, styleMask: styleMask, backing: .buffered, defer: false)
    }
}
