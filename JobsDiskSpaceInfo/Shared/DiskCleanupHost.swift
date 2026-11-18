//
//  DiskCleanupHost.swift
//  JobsDiskSpaceInfoShared
//
//  Created by Jobs on 2026年11月15日，星期日.
//

import Foundation

enum DiskCleanupHost {

    static func applicationURL(forExtension extensionURL: URL) -> URL? {
        guard extensionURL.isFileURL,
              extensionURL.lastPathComponent == "JobsDiskSpaceInfoFinderSync.appex" else {
            return nil
        }
        let plugins = extensionURL.deletingLastPathComponent()
        let contents = plugins.deletingLastPathComponent()
        let app = contents.deletingLastPathComponent()
        guard plugins.lastPathComponent == "PlugIns",
              contents.lastPathComponent == "Contents",
              app.pathExtension == "app",
              let bundle = Bundle.makeDiskCleanupBundle(url: app),
              bundle.bundleIdentifier == "com.jobs.diskspaceinfo",
              bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String == "JobsDiskSpaceInfo",
              bundle.builtInPlugInsURL?.appendingPathComponent("JobsDiskSpaceInfoFinderSync.appex").standardizedFileURL == extensionURL.standardizedFileURL else {
            return nil
        }
        return app.standardizedFileURL
    }
}

private extension Bundle {

    static func makeDiskCleanupBundle(url: URL) -> Bundle? {
        return Bundle(url: url)
    }
}
