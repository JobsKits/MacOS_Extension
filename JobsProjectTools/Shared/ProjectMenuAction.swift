//
//  ProjectMenuAction.swift
//  JobsProjectTools
//
//  Created by Jobs on 2026年10月24日，星期六.
//

import Foundation

/// IDE 保留一级入口；Git 动作按声明顺序进入同一个子菜单。
enum ProjectMenuAction: String, CaseIterable {
    case androidStudio = "android_studio_opener"
    case vscode = "vscode_opener"
    case xcode = "xcode_opener"
    case gitPull = "git-pull"
    case gitRemote = "git_remote"
    case gitRemoteCopy = "git_remote_copier"
    case gitProxy = "git-proxy-configure"
    case gitEmptyCommitPush = "git_empty_commit_push"

    var isGitAction: Bool {
        switch self {
        case .gitPull, .gitRemote, .gitRemoteCopy, .gitProxy, .gitEmptyCommitPush:
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
            }
        }
    }
}

enum ProjectMenuConfiguration {
    static var fileURL: URL? {
        guard let home = NSHomeDirectoryForUser(NSUserName()) else { return nil }
        return URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent("Library/Application Support/JobsProjectTools/EnabledFeatures.txt")
    }

    static func enabledFeatures() -> Set<ProjectMenuAction> {
        guard let fileURL, let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
            // 未安装 / 配置不可读时不意外启用用户没有选择的菜单。
            return []
        }
        return Set(text.split(whereSeparator: { $0 == "," || $0.isWhitespace })
            .compactMap { ProjectMenuAction(rawValue: String($0)) })
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
