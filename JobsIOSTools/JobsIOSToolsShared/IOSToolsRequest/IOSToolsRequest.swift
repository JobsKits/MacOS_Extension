//
//  IOSToolsRequest.swift
//  JobsIOSToolsShared
//
//  Created by Jobs on 2026年10月23日，星期五.
//

import Foundation

enum IOSToolsAction: String, CaseIterable {
    case cleanCache = "ios-clean-cache"
    case disableSandbox = "ios-disable-sandbox"
    case installCocoapods = "ios-install-cocoapods"
    case sourceGithub = "ios-pods-source-github"
    case extractPods = "ios-extract-pods"
    case podUpdate = "ios-pod-update"
    case dependencies = "ios-xcode-dependencies"
    case repoUpdate = "ios-pod-repo-update"
    case podBuildCheck = "ios-pod-build-check"
    case codeSnippets = "ios-code-snippets"

    var title: String {
        switch self {
        case .cleanCache:
            return "清理 iOS 缓存"
        case .disableSandbox:
            return "禁用 Xcode 脚本沙盒"
        case .installCocoapods:
            return "安装 CocoaPods"
        case .sourceGithub:
            return "CocoaPods 源：CDN → GitHub"
        case .extractPods:
            return "提取项目中所有 Pod 相关文件"
        case .podUpdate:
            return "Pod Update"
        case .dependencies:
            return "查询 Xcode 工程依赖关系"
        case .repoUpdate:
            return "更新 CocoaPods 本地仓库"
        case .podBuildCheck:
            return "自检当前本地 Pod 能否编译"
        /// 安装或升级当前用户 Xcode 的 Jobs 代码片段。
        case .codeSnippets:
            return "安装 / 升级 JobsCodeSnippets"
        }
    }
}

enum IOSToolsRequest {
    static let scheme = "jobsiostools"

    static func url(for projectURL: URL, action: IOSToolsAction) -> URL? {
        guard projectURL.isFileURL else {
            return nil
        }
        var components = URLComponents()
        components.scheme = scheme
        components.host = action.rawValue
        components.queryItems = [URLQueryItem(name: "path", value: projectURL.standardizedFileURL.path)]
        return components.url
    }

    static func action(from requestURL: URL) -> IOSToolsAction? {
        guard projectURL(from: requestURL) != nil, let host = requestURL.host else {
            return nil
        }
        return IOSToolsAction(rawValue: host)
    }

    static func projectURL(from requestURL: URL) -> URL? {
        guard let c = URLComponents(url: requestURL, resolvingAgainstBaseURL: false),
              c.scheme?.lowercased() == scheme, let host = c.host, IOSToolsAction(rawValue: host) != nil,
              c.user == nil, c.password == nil, c.port == nil, c.path.isEmpty, c.fragment == nil,
              let items = c.queryItems, items.count == 1, items[0].name == "path",
              let path = items[0].value, path.hasPrefix("/"), !path.utf8.contains(0) else {
            return nil
        }
        return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    }
}
