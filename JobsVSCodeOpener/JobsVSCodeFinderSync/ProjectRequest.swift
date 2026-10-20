//
//  ProjectRequest.swift
//  JobsVSCodeFinderSync
//
//  Created by Jobs on 2026年10月19日，星期一.
//

import Foundation

/// Finder 扩展与宿主 App 之间的打开请求编解码。
///
/// 扩展进程运行在沙盒里，直接调用 LaunchServices 启动 IDE 可能静默失败，
/// 因此菜单点击只负责把路径交给宿主，查找 IDE、打开项目与错误提示都由宿主完成。
enum ProjectRequest {
    static let scheme = "jobsvscodeopener"
    static let host = "open"
    static let notificationName = Notification.Name("com.jobs.JobsVSCodeOpener.openProject")
    static let distributedObject = "com.jobs.JobsVSCodeOpener"
    static let pathUserInfoKey = "path"

    private static let pathQueryName = "p"

    static func url(forPath path: String) -> URL? {
        let encoded = encode(path)
        guard !encoded.isEmpty else {
            return nil
        }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.queryItems = [URLQueryItem(name: pathQueryName, value: encoded)]
        return components.url
    }

    static func path(from url: URL) -> String? {
        guard url.scheme?.lowercased() == scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let encoded = components.queryItems?.first(where: { $0.name == pathQueryName })?.value else {
            return nil
        }
        return decode(encoded)
    }

    /// base64url（`+`→`-`、`/`→`_`、去掉 `=`），只含 URL 安全字符。
    /// 不能预先百分号转义：`URLComponents` 会再编码一次 `%`，导致解不回来。
    private static func encode(_ path: String) -> String {
        Data(path.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func decode(_ encoded: String) -> String? {
        var base64 = encoded
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: base64),
              let path = String(data: data, encoding: .utf8),
              !path.isEmpty else {
            return nil
        }
        return path
    }
}
