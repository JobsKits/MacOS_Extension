//
//  DiskCleanupFactories.swift
//  JobsDiskSpaceInfoShared
//
//  Created by Jobs on 2026年11月15日，星期日.
//

import AppKit

extension NSWorkspace.OpenConfiguration {

    static func makeDiskCleanupConfiguration() -> NSWorkspace.OpenConfiguration {
        let value = NSWorkspace.OpenConfiguration()
        value.promptsUserIfNeeded = false
        value.addsToRecentItems = false
        value.allowsRunningApplicationSubstitution = false
        return value
    }
}

extension NSWorkspace {

    @discardableResult
    func byOpenDiskCleanup(_ url: URL,
                           application: URL,
                           completion: @escaping (NSRunningApplication?, Error?) -> Void) -> Self {
        open([url], withApplicationAt: application, configuration: .makeDiskCleanupConfiguration(), completionHandler: completion)
        return self
    }
}

extension NSAppleScript {

    static func makeDiskCleanupScript(source: String) -> NSAppleScript? {
        return NSAppleScript(source: source)
    }
}

extension NSAlert {

    static func showDiskCleanupFailure(_ details: String) {
        NSLog("JobsDiskSpaceInfo: %@", details)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = diskCleanupFailureTitle()
        alert.informativeText = details
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private static func diskCleanupFailureTitle() -> String {
        let language = (Locale.preferredLanguages.first ?? "en").lowercased()
        if language.hasPrefix("zh") {
            return language.contains("hant") || language.hasSuffix("-tw") || language.hasSuffix("-hk") ? "磁碟清理未啟動" : "磁盘清理未启动"
        }
        switch language.split(separator: "-").first {
        case "bo":
            return "ཌིས་ཀི་གཙང་སེལ་འགོ་འཛུགས་མ་ཐུབ།"
        case "ja":
            return "ディスククリーンアップを開始できません"
        case "fr":
            return "Le nettoyage du disque n’a pas démarré"
        case "es":
            return "La limpieza del disco no se inició"
        case "de":
            return "Datenträgerbereinigung wurde nicht gestartet"
        case "ru":
            return "Очистка диска не запущена"
        case "ko":
            return "디스크 정리를 시작하지 못했습니다"
        default:
            return "Disk cleanup did not start"
        }
    }
}
