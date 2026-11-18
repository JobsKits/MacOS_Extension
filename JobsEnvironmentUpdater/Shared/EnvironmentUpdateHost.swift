//
//  EnvironmentUpdateHost.swift
//  JobsEnvironmentUpdaterShared
//
//  Created by Jobs on 2026年11月17日，星期二.
//

import Foundation

enum EnvironmentUpdateHost {

    static func applicationURL(forExtension extensionURL: URL) -> URL? {
        guard extensionURL.isFileURL,
              extensionURL.lastPathComponent == "JobsEnvironmentUpdaterFinderSync.appex" else {
            return nil
        }
        let plugins = extensionURL.deletingLastPathComponent()
        let contents = plugins.deletingLastPathComponent()
        let app = contents.deletingLastPathComponent()
        guard plugins.lastPathComponent == "PlugIns",
              contents.lastPathComponent == "Contents",
              app.pathExtension == "app",
              let bundle = Bundle.makeEnvironmentUpdateBundle(url: app),
              bundle.bundleIdentifier == "com.jobs.environmentupdater",
              bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String == "JobsEnvironmentUpdater",
              bundle.builtInPlugInsURL?.appendingPathComponent("JobsEnvironmentUpdaterFinderSync.appex").standardizedFileURL == extensionURL.standardizedFileURL else {
            return nil
        }
        return app.standardizedFileURL
    }
}

private extension Bundle {

    static func makeEnvironmentUpdateBundle(url: URL) -> Bundle? {
        return Bundle(url: url)
    }
}
