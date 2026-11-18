//
//  PermanentDeleteHost.swift
//  JobsPermanentDeleterShared
//
//  Created by Jobs on 2026年11月18日，星期三.
//

import Foundation

enum PermanentDeleteHost {

    static func applicationURL(forExtension extensionURL: URL) -> URL? {
        guard extensionURL.isFileURL,
              extensionURL.lastPathComponent == "JobsPermanentDeleterFinderSync.appex" else {
            return nil
        }
        let pluginsURL = extensionURL.deletingLastPathComponent()
        let contentsURL = pluginsURL.deletingLastPathComponent()
        let applicationURL = contentsURL.deletingLastPathComponent()
        guard pluginsURL.lastPathComponent == "PlugIns",
              contentsURL.lastPathComponent == "Contents",
              applicationURL.pathExtension == "app",
              let application = Bundle(url: applicationURL),
              application.bundleIdentifier == "com.jobs.permanentdeleter",
              application.object(forInfoDictionaryKey: "CFBundleExecutable") as? String == "JobsPermanentDeleter",
              application.builtInPlugInsURL?.appendingPathComponent("JobsPermanentDeleterFinderSync.appex").standardizedFileURL == extensionURL.standardizedFileURL else {
            return nil
        }
        return applicationURL.standardizedFileURL
    }
}
