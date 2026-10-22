//
//  FlutterPackagingRequest.swift
//  JobsFlutterPackagingShared
//
//  Created by Jobs on 2026年10月22日，星期四.
//

import Foundation

/// Finder 与宿主只交换 URL 数据，不把文件夹路径拼进 Shell 源码。
enum FlutterPackagingRequest {
    static let scheme = "jobsflutterpackager"

    static func url(for projectURL: URL) -> URL? {
        guard projectURL.isFileURL else {
            return nil
        }
        var components = URLComponents()
        components.scheme = scheme
        components.host = "package"
        components.path = "/run"
        components.queryItems = [URLQueryItem(name: "project", value: projectURL.standardizedFileURL.path)]
        return components.url
    }

    static func projectURL(from requestURL: URL) -> URL? {
        guard let components = URLComponents(url: requestURL, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == scheme,
              components.host == "package",
              components.user == nil,
              components.password == nil,
              components.port == nil,
              components.path == "/run",
              components.fragment == nil,
              let items = components.queryItems,
              items.count == 1,
              items[0].name == "project",
              let path = items[0].value,
              path.hasPrefix("/"),
              !path.utf8.contains(0) else {
            return nil
        }
        return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    }
}
