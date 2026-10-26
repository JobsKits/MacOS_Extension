//
//  SourcetreeApplication.swift
//  JobsProjectTools
//
//  Created by Jobs on 2026年10月26日，星期一.
//

import AppKit

/// 每次查询实际安装，避免卸载后仍因 LaunchServices 的旧登记显示菜单。
enum SourcetreeApplication {
    static let bundleIdentifier = "com.torusknot.SourceTreeNotMAS"

    static func installedURL() -> URL? {
        return NSWorkspace.shared.urlsForApplications(withBundleIdentifier: bundleIdentifier).first {
            isUsableApplication(at: $0)
        }
    }

    static func isUsableApplication(at url: URL) -> Bool {
        guard url.isFileURL,
              let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isApplicationKey]),
              values.isDirectory == true,
              values.isApplication == true,
              let bundle = Bundle(url: url),
              bundle.bundleIdentifier == bundleIdentifier,
              let executable = bundle.executableURL else {
            return false
        }
        return FileManager.default.isExecutableFile(atPath: executable.path)
    }
}
