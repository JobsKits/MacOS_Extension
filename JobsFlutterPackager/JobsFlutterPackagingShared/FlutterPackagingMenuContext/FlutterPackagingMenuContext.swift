//
//  FlutterPackagingMenuContext.swift
//  JobsFlutterPackagingShared
//
//  Created by Jobs on 2026年10月22日，星期四.
//

import Foundation
import Darwin

/// 仅接受单选项目目录或项目背景；真实桌面空白始终排除。
enum FlutterPackagingMenuContext {
    static var desktopURLs: [URL] {
        var directories = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)
        // Foundation 的用户 Home API 也可能被沙盒重定向，目录服务保留真实用户位置。
        if let homeURL = userHomeDirectoryURL() {
            let desktop = homeURL.appendingPathComponent("Desktop", isDirectory: true)
            directories.insert(desktop, at: 0)
        }
        return directories
    }

    static func candidateURL(isItems: Bool, isContainer: Bool, targetedURL: URL?, selectedURLs: [URL]?, desktopURLs: [URL] = Self.desktopURLs) -> URL? {
        if isItems {
            guard let selectedURLs, selectedURLs.count == 1, let selected = selectedURLs.first,
                  selected.isFileURL else {
                return nil
            }
            return selected
        }
        guard isContainer, let candidate = targetedURL, candidate.isFileURL,
              !isDesktopContainer(candidate, desktopURLs: desktopURLs) else {
            return nil
        }
        return candidate
    }

    static func isDesktopContainer(_ candidate: URL, desktopURLs: [URL] = Self.desktopURLs) -> Bool {
        guard let candidatePath = lexicalPath(candidate) else {
            return false
        }
        // 沙盒中的 Foundation Home 可能重定向；优先纯路径匹配目录服务取得的真实桌面。
        if desktopURLs.contains(where: { lexicalPath($0) == candidatePath }) {
            return true
        }
        let resolvedPath = lexicalPath(candidate.resolvingSymlinksInPath())
        return desktopURLs.contains {
            lexicalPath($0.resolvingSymlinksInPath()) == resolvedPath
        }
    }

    private static func userHomeDirectoryURL() -> URL? {
        var bufferSize = max(16_384, Int(sysconf(_SC_GETPW_R_SIZE_MAX)))
        while bufferSize <= 1_048_576 {
            var account = passwd()
            var result: UnsafeMutablePointer<passwd>?
            var buffer = [CChar](repeating: 0, count: bufferSize)
            let lookup = buffer.withUnsafeMutableBufferPointer { storage -> (status: Int32, home: String?) in
                let status = getpwuid_r(getuid(), &account, storage.baseAddress, storage.count, &result)
                guard status == 0, let home = result?.pointee.pw_dir else {
                    return (status, nil)
                }
                return (status, String(cString: home))
            }
            if lookup.status == 0 {
                guard let home = lookup.home, home.hasPrefix("/") else {
                    return nil
                }
                return URL(fileURLWithPath: home, isDirectory: true)
            }
            guard lookup.status == ERANGE else {
                return nil
            }
            bufferSize *= 2
        }
        return nil
    }

    private static func lexicalPath(_ url: URL) -> String? {
        guard url.isFileURL, url.path.hasPrefix("/"),
              url.host == nil || url.host == "" || url.host == "localhost" else {
            return nil
        }
        var components: [Substring] = []
        for component in url.path.split(separator: "/", omittingEmptySubsequences: true) {
            if component == ".." {
                if !components.isEmpty {
                    components.removeLast()
                }
            } else if component != "." {
                components.append(component)
            }
        }
        return "/" + components.joined(separator: "/")
    }
}
