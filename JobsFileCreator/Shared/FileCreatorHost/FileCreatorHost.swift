//
//  FileCreatorHost.swift
//  JobsFileCreatorShared
//
//  Created by Jobs on 2026年10月29日，星期四.
//

import Foundation

enum FileCreatorHost {

    static func applicationURL(forExtension extensionURL: URL) -> URL? {
        guard extensionURL.isFileURL,
              extensionURL.lastPathComponent == "JobsFileCreatorFinderSync.appex" else {
            return nil
        }
        let pluginsURL = extensionURL.deletingLastPathComponent()
        let contentsURL = pluginsURL.deletingLastPathComponent()
        let applicationURL = contentsURL.deletingLastPathComponent()
        guard pluginsURL.lastPathComponent == "PlugIns",
              contentsURL.lastPathComponent == "Contents",
              applicationURL.pathExtension == "app",
              let application = Bundle(url: applicationURL),
              application.bundleIdentifier == "com.jobs.filecreator",
              application.object(forInfoDictionaryKey: "CFBundleExecutable") as? String == "JobsFileCreator",
              application.builtInPlugInsURL?.appendingPathComponent("JobsFileCreatorFinderSync.appex").standardizedFileURL == extensionURL.standardizedFileURL else {
            return nil
        }
        return applicationURL.standardizedFileURL
    }
}
