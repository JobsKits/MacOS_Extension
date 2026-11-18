//
//  SendToHost.swift
//  JobsSendToShared
//
//  Created by Jobs on 2026年11月18日，星期三.
//

import Foundation

enum SendToHost {

    static func applicationURL(forExtension extensionURL: URL) -> URL? {
        guard extensionURL.isFileURL,
              extensionURL.lastPathComponent == "JobsSendToFinderSync.appex" else {
            return nil
        }
        let pluginsURL = extensionURL.deletingLastPathComponent()
        let contentsURL = pluginsURL.deletingLastPathComponent()
        let applicationURL = contentsURL.deletingLastPathComponent()
        guard pluginsURL.lastPathComponent == "PlugIns",
              contentsURL.lastPathComponent == "Contents",
              applicationURL.pathExtension == "app",
              let application = Bundle(url: applicationURL),
              application.bundleIdentifier == "com.jobs.sendto",
              application.object(forInfoDictionaryKey: "CFBundleExecutable") as? String == "JobsSendTo",
              application.builtInPlugInsURL?.appendingPathComponent("JobsSendToFinderSync.appex").standardizedFileURL == extensionURL.standardizedFileURL else {
            return nil
        }
        return applicationURL.standardizedFileURL
    }
}
