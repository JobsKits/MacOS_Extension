//
//  ProjectMenuAction.swift
//  JobsProjectTools
//
//  Created by Jobs on 2026年10月24日，星期六.
//

import Foundation
import Darwin

/// IDE 保留一级入口；Git 动作按声明顺序进入同一个子菜单。
enum ProjectMenuAction: String, CaseIterable {
    case androidStudio = "android_studio_opener"
    case vscode = "vscode_opener"
    case xcode = "xcode_opener"
    case gitPull = "git-pull"
    case gitRollback = "git-rollback"
    case gitRemote = "git_remote"
    case gitRemoteCopy = "git_remote_copier"
    case gitProxy = "git-proxy-configure"
    case gitEmptyCommitPush = "git_empty_commit_push"

    var isGitAction: Bool {
        switch self {
        case .gitPull, .gitRollback, .gitRemote, .gitRemoteCopy, .gitProxy, .gitEmptyCommitPush:
            return true
        default:
            return false
        }
    }

    var title: String {
        switch self {
        case .androidStudio: return "用 Android Studio 打开项目"
        case .vscode: return "用 VSCode 打开项目"
        case .xcode: return "用 Xcode 打开项目"
        case .gitPull: return "拉取 Git 到最新"
        case .gitRollback:
            return "Git 提交回退"
        case .gitRemote: return "打开 Git 远程地址"
        case .gitRemoteCopy: return "复制 Git 远程地址"
        case .gitProxy: return "配置 Git 动态代理"
        case .gitEmptyCommitPush: return "在终端创建空白 Commit 并 Push"
        }
    }

    static func visible(at url: URL, enabled: Set<Self>) -> [Self] {
        guard url.isFileURL,
              let values = try? url.resourceValues(forKeys: [.isDirectoryKey]),
              let isDirectory = values.isDirectory else { return [] }
        let directory = isDirectory ? url : url.deletingLastPathComponent()
        let isXcode = XcodeProjectDetector.canOpen(directory)
            || (["xcodeproj", "xcworkspace"].contains(directory.pathExtension.lowercased())
                && XcodeProjectDetector.canOpen(directory.deletingLastPathComponent()))
        let isGit = GitRepositoryValidator().isWorkingDirectory(at: url)
        return allCases.filter { action in
            guard enabled.contains(action) else { return false }
            switch action {
            case .androidStudio, .vscode: return !isXcode
            case .xcode: return isXcode
            case .gitPull, .gitRemote, .gitRemoteCopy, .gitProxy, .gitEmptyCommitPush:
                return isGit
            case .gitRollback:
                return GitRollbackMenuContext().isWorkingDirectory(at: url)
            }
        }
    }
}

enum ProjectMenuConfiguration {
    static var fileURL: URL? {
        return configurationURL(realHomePath: accountHomeDirectory())
    }

    /// Finder 沙盒会重定向 Foundation 的 Home；配置始终使用系统账户的真实目录。
    static func accountHomeDirectory() -> String? {
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
                return lookup.home
            }
            guard lookup.status == ERANGE else {
                return nil
            }
            bufferSize *= 2
        }
        return nil
    }

    /// 单独计算配置地址，便于验证容器别名不会改变用户配置的位置。
    static func configurationURL(realHomePath: String?) -> URL? {
        guard let realHomePath, realHomePath.hasPrefix("/"), !realHomePath.contains("\0") else {
            return nil
        }
        return URL(fileURLWithPath: realHomePath, isDirectory: true)
            .appendingPathComponent("Library/Application Support/JobsProjectTools/EnabledFeatures.txt")
    }

    static func enabledFeatures() -> Set<ProjectMenuAction> {
        return enabledFeatures(at: fileURL)
    }

    /// 配置缺失或不可读时保持关闭，诊断仅记录路径与读取错误。
    static func enabledFeatures(at configurationURL: URL?) -> Set<ProjectMenuAction> {
        guard let configurationURL else {
            NSLog("JobsProjectTools configuration: cannot resolve account Home directory.")
            return []
        }
        do {
            let text = try String(contentsOf: configurationURL, encoding: .utf8)
            return Set(text.split { character in
                character == "," || character.isWhitespace
            }.compactMap { value in
                ProjectMenuAction(rawValue: String(value))
            })
        } catch {
            NSLog("JobsProjectTools configuration read failed at %@: %@", configurationURL.path, error.localizedDescription)
            return []
        }
    }
}

struct ProjectMenuRequest {
    let action: ProjectMenuAction
    let fileURL: URL

    var url: URL? {
        guard fileURL.isFileURL, fileURL.path.hasPrefix("/") else { return nil }
        var components = URLComponents()
        components.scheme = "jobsprojecttools"
        components.host = "perform"
        components.queryItems = [URLQueryItem(name: "action", value: action.rawValue),
                                 URLQueryItem(name: "path", value: fileURL.path)]
        return components.url
    }

    init(action: ProjectMenuAction, fileURL: URL) {
        self.action = action
        self.fileURL = fileURL
    }

    init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "jobsprojecttools", components.host == "perform",
              components.user == nil, components.password == nil, components.port == nil,
              components.path.isEmpty, components.fragment == nil,
              let items = components.queryItems, items.count == 2,
              items.filter({ $0.name == "action" }).count == 1,
              items.filter({ $0.name == "path" }).count == 1,
              let rawAction = items.first(where: { $0.name == "action" })?.value,
              let action = ProjectMenuAction(rawValue: rawAction),
              let path = items.first(where: { $0.name == "path" })?.value,
              path.hasPrefix("/"), !path.contains("\0") else { return nil }
        self.init(action: action, fileURL: URL(fileURLWithPath: path).standardizedFileURL)
    }
}
