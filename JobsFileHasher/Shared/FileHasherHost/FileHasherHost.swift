//
//  FileHasherHost.swift
//  JobsFileHasherShared
//
//  Created by Jobs on 2026年11月6日，星期五.
//

import Foundation

enum FileHasherHost {

    // 只唤起当前扩展实际所属宿主，避免旧副本或默认 URL 处理器替换。
    static func applicationURL(forExtension extensionURL: URL) -> URL? {
        guard extensionURL.isFileURL,
              extensionURL.lastPathComponent == "JobsFileHasherFinderSync.appex" else {
            return nil
        }
        let plugins = extensionURL.deletingLastPathComponent()
        let contents = plugins.deletingLastPathComponent()
        let app = contents.deletingLastPathComponent()
        guard plugins.lastPathComponent == "PlugIns",
              contents.lastPathComponent == "Contents",
              app.pathExtension == "app",
              let bundle = Bundle.make(url: app),
              bundle.bundleIdentifier == "com.jobs.filehasher",
              bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String == "JobsFileHasher",
              bundle.builtInPlugInsURL?.appendingPathComponent("JobsFileHasherFinderSync.appex").standardizedFileURL == extensionURL.standardizedFileURL else {
            return nil
        }
        return app.standardizedFileURL
    }
}
