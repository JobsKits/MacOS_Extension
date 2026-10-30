//
//  FileCreatorInterface.swift
//  JobsFileCreator
//
//  Created by Jobs on 2026年10月29日，星期四.
//

import AppKit
import UniformTypeIdentifiers

enum FileCreatorInterface {

    static var fileIcon: NSImage {
        return NSWorkspace.shared.icon(for: UTType.data)
    }

    static func installEditingMenu() {
        let appMenu = NSMenu.make(title: "新建文件")
            .byAddItem(NSMenuItem.make(title: "退出新建文件",
                                        action: #selector(NSApplication.terminate(_:)),
                                        keyEquivalent: "q"))
        let editMenu = NSMenu.make(title: "编辑")
            .byAddItem(NSMenuItem.make(title: "剪切",
                                        action: #selector(NSText.cut(_:)),
                                        keyEquivalent: "x"))
            .byAddItem(NSMenuItem.make(title: "复制",
                                        action: #selector(NSText.copy(_:)),
                                        keyEquivalent: "c"))
            .byAddItem(NSMenuItem.make(title: "粘贴",
                                        action: #selector(NSText.paste(_:)),
                                        keyEquivalent: "v"))
            .byAddItem(NSMenuItem.make(title: "全选",
                                        action: #selector(NSText.selectAll(_:)),
                                        keyEquivalent: "a"))
        NSApp.byMainMenu(NSMenu.make()
            .byAddItem(NSMenuItem.make(title: "新建文件")
                .bySubmenu(appMenu))
            .byAddItem(NSMenuItem.make(title: "编辑")
                .bySubmenu(editMenu)))
    }

    static func askName(directory: URL,
                        name: String,
                        error: String?) -> String? {
        NSApp.activate(ignoringOtherApps: true)
        let field = NSTextField.make(frame: NSRect(x: 0, y: 0, width: 380, height: 24))
            .byStringValue(name)
        let alert = NSAlert.make()
            .byIcon(fileIcon)
            .byMessageText("新建文件")
            .byInformativeText(error ?? "位置：\(directory.path)\n请输入文件名，可自行修改扩展名。")
            .byAlertStyle(error == nil ? .informational : .warning)
            .byAccessoryView(field)
            .byAddButton("创建")
            .byAddButton("取消")
        alert.window.byInitialFirstResponder(field)
            .byMakeFirstResponder(field)
        field.bySelectText(nil)
        guard alert.runModal() == .alertFirstButtonReturn else {
            return nil
        }
        return field.stringValue
    }

    static func showFailure(_ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        NSAlert.make()
            .byMessageText("新建文件未完成")
            .byInformativeText(message)
            .byAlertStyle(.warning)
            .byAddButton("好")
            .runModal()
    }
}
