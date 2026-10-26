//
//  RunRevocationRequest.swift
//  JobsRunRevocationShared
//
//  Created by Jobs on 2026年10月24日，星期六.
//

import Foundation

/// 路径通过 URL 数据传递，宿主收到后再次检查文件类型。
enum RunRevocationRequest {
    static let scheme = "jobsrunrevoker"

    static func url(for fileURL: URL) -> URL? {
        guard RunRevocationValidator().isExecutableFormat(at: fileURL) else {
            return nil
        }
        var components = URLComponents()
        components.scheme = scheme
        components.host = "revoke"
        components.queryItems = [URLQueryItem(name: "path", value: fileURL.standardizedFileURL.path)]
        return components.url
    }

    static func fileURL(from requestURL: URL) -> URL? {
        guard let components = URLComponents(url: requestURL, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == scheme,
              components.host == "revoke",
              components.user == nil,
              components.password == nil,
              components.port == nil,
              components.path.isEmpty,
              components.fragment == nil,
              let items = components.queryItems,
              items.count == 1,
              items[0].name == "path",
              let path = items[0].value,
              path.hasPrefix("/"),
              !path.utf8.contains(0) else {
            return nil
        }
        return URL(fileURLWithPath: path, isDirectory: false).standardizedFileURL
    }
}
