//
//  IOSSimulatorMenuContext.swift
//  JobsIOSSimulatorShared
//
//  Created by Jobs on 2026年10月20日，星期二.
//

import Foundation
import Darwin

/// 模拟器入口只属于系统桌面的空白菜单，选中项目或普通文件夹时不提供。
enum IOSSimulatorMenuContext {
    static var desktopURLs: [URL] {
        var directories = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)
        // Foundation 的用户 Home API 也可能被沙盒重定向，目录服务保留真实用户位置。
        if let homeURL = userHomeDirectoryURL() {
            let desktop = homeURL.appendingPathComponent("Desktop", isDirectory: true)
            directories.insert(desktop, at: 0)
        }
        return directories
    }

    static var desktopURL: URL? {
        return desktopURLs.first
    }

    static func candidateURL(isContainer: Bool, targetedURL: URL?, selectedURLs: [URL]?, desktopURL: URL? = Self.desktopURL) -> URL? {
        guard isContainer, let candidate = targetedURL ?? desktopURL, candidate.isFileURL else {
            return nil
        }
        var knownDesktops = Self.desktopURLs
        if let desktopURL {
            knownDesktops.append(desktopURL)
        }
        guard let candidatePath = lexicalPath(candidate) else {
            return nil
        }
        // 全局 simctl 动作不读取桌面数据，已知路径命中不能依赖沙盒内的元数据权限。
        let matchesKnownDesktop = knownDesktops.contains { knownDesktop in
            return lexicalPath(knownDesktop) == candidatePath
        }
        if matchesKnownDesktop {
            return URL(fileURLWithPath: candidatePath, isDirectory: true)
        }
        // 只为可解析的桌面别名提供兼容；解析失败不影响上面的精确白名单匹配。
        let resolvedCandidate = candidate.resolvingSymlinksInPath()
        guard let resolvedPath = lexicalPath(resolvedCandidate) else {
            return nil
        }
        let matchesResolvedDesktop = knownDesktops.contains { knownDesktop in
            return lexicalPath(knownDesktop.resolvingSymlinksInPath()) == resolvedPath
        }
        guard matchesResolvedDesktop else {
            return nil
        }
        return resolvedCandidate
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
