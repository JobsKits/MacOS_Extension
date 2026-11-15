//
//  CommandShortcutHost.swift
//  JobsCommandShortcutCreatorShared
//
//  Created by Jobs on 2026年11月13日，星期五.
//

import Foundation

enum CommandShortcutHost {

    static func applicationURL(forExtension extensionURL: URL) -> URL? {
        guard extensionURL.isFileURL,
              extensionURL.lastPathComponent == "JobsCommandShortcutCreatorFinderSync.appex" else {
            return nil
        }
        let pluginsURL = extensionURL.deletingLastPathComponent()
        let contentsURL = pluginsURL.deletingLastPathComponent()
        let applicationURL = contentsURL.deletingLastPathComponent()
        guard pluginsURL.lastPathComponent == "PlugIns",
              contentsURL.lastPathComponent == "Contents",
              applicationURL.pathExtension == "app",
              let application = Bundle(url: applicationURL),
              application.bundleIdentifier == "com.jobs.commandshortcutcreator",
              application.object(forInfoDictionaryKey: "CFBundleExecutable") as? String == "JobsCommandShortcutCreator",
              application.builtInPlugInsURL?.appendingPathComponent("JobsCommandShortcutCreatorFinderSync.appex").standardizedFileURL == extensionURL.standardizedFileURL else {
            return nil
        }
        return applicationURL.standardizedFileURL
    }
}
