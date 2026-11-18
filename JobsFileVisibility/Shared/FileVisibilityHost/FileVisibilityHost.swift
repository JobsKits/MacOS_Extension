//
//  FileVisibilityHost.swift
//  JobsFileVisibilityShared
//
//  Created by Jobs on 2026年11月18日，星期三.
//

import Foundation

enum FileVisibilityHost {

    static func applicationURL(forExtension extensionURL: URL) -> URL? {
        guard extensionURL.isFileURL,
              extensionURL.lastPathComponent == "JobsFileVisibilityFinderSync.appex" else {
            return nil
        }
        let pluginsURL = extensionURL.deletingLastPathComponent()
        let contentsURL = pluginsURL.deletingLastPathComponent()
        let applicationURL = contentsURL.deletingLastPathComponent()
        guard pluginsURL.lastPathComponent == "PlugIns",
              contentsURL.lastPathComponent == "Contents",
              applicationURL.pathExtension == "app",
              let application = Bundle(url: applicationURL),
              application.bundleIdentifier == "com.jobs.filevisibility",
              application.object(forInfoDictionaryKey: "CFBundleExecutable") as? String == "JobsFileVisibility",
              application.builtInPlugInsURL?.appendingPathComponent("JobsFileVisibilityFinderSync.appex").standardizedFileURL == extensionURL.standardizedFileURL else {
            return nil
        }
        return applicationURL.standardizedFileURL
    }
}
