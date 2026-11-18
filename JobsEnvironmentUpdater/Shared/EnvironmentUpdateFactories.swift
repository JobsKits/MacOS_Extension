//
//  EnvironmentUpdateFactories.swift
//  JobsEnvironmentUpdaterShared
//
//  Created by Jobs on 2026年11月17日，星期二.
//

import AppKit

extension NSWorkspace.OpenConfiguration {

    static func makeEnvironmentUpdateConfiguration() -> NSWorkspace.OpenConfiguration {
        let value = NSWorkspace.OpenConfiguration()
        value.promptsUserIfNeeded = false
        value.addsToRecentItems = false
        value.allowsRunningApplicationSubstitution = false
        return value
    }
}

extension NSWorkspace {

    @discardableResult
    func byOpenEnvironmentUpdate(_ url: URL,
                           application: URL,
                           completion: @escaping (NSRunningApplication?, Error?) -> Void) -> Self {
        open([url], withApplicationAt: application, configuration: .makeEnvironmentUpdateConfiguration(), completionHandler: completion)
        return self
    }
}

extension NSAppleScript {

    static func makeEnvironmentUpdateScript(source: String) -> NSAppleScript? {
        return NSAppleScript(source: source)
    }
}

extension NSAlert {

    static func showEnvironmentUpdateFailure(_ details: String) {
        NSLog("JobsEnvironmentUpdater: %@", details)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = environmentUpdateFailureTitle()
        alert.informativeText = details
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private static func environmentUpdateFailureTitle() -> String {
        let language = (Locale.preferredLanguages.first ?? "en").lowercased()
        if language.hasPrefix("zh") {
            return language.contains("hant") || language.hasSuffix("-tw") || language.hasSuffix("-hk") ? "開發環境更新未啟動" : "开发环境更新未启动"
        }
        switch language.split(separator: "-").first {
        case "bo":
            return "གསར་སྒྱུར་འགོ་འཛུགས་མ་ཐུབ།"
        case "ja":
            return "開発環境の更新を開始できません"
        case "fr":
            return "La mise à jour n’a pas démarré"
        case "es":
            return "La actualización no se inició"
        case "de":
            return "Die Aktualisierung wurde nicht gestartet"
        case "ru":
            return "Обновление не запущено"
        case "ko":
            return "업데이트를 시작하지 못했습니다"
        default:
            return "Environment update did not start"
        }
    }
}
