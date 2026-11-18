//
//  SendToAppMenu.swift
//  JobsSendTo
//
//  Created by Jobs on 2026年11月18日，星期三.
//

import AppKit

enum SendToAppMenu {

    static func install() {
        let edit = NSMenu.make(title: SendToLocalization.text("edit"))
            .byAddItem(NSMenuItem.make(title: SendToLocalization.text("copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
            .byAddItem(NSMenuItem.make(title: SendToLocalization.text("selectAll"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        NSApp.byMainMenu(NSMenu.make()
            .byAddItem(NSMenuItem.make(title: SendToLocalization.text("title"))
                .bySubmenu(NSMenu.make()
                    .byAddItem(NSMenuItem.make(title: SendToLocalization.text("recoveryTitle"),
                                                action: #selector(AppDelegate.showRecovery(_:)),
                                                target: NSApp.delegate as AnyObject?))
                    .byAddItem(NSMenuItem.make(title: SendToLocalization.text("quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))))
            .byAddItem(NSMenuItem.make(title: SendToLocalization.text("edit")).bySubmenu(edit)))
    }
}
