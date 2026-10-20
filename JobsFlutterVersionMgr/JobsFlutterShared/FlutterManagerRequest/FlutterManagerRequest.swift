//
//  FlutterManagerRequest.swift
//  JobsFlutterShared
//
//  Created by Jobs on 2026年10月19日，星期一.
//

import Foundation

/// Finder 与宿主只交换 URL 数据，不把文件夹路径拼进 Shell 源码。
enum FlutterManagerRequest {
    static let scheme = "jobsflutterversionmgr"

    static func url(for projectURL: URL) -> URL? {
        guard projectURL.isFileURL else {
            return nil
        }
        var components = URLComponents()
        components.scheme = scheme
        components.host = "manage"
        components.queryItems = [URLQueryItem(name: "path", value: projectURL.standardizedFileURL.path)]
        return components.url
    }

    static func projectURL(from requestURL: URL) -> URL? {
        guard let components = URLComponents(url: requestURL, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == scheme,
              components.host == "manage",
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
        return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    }
}
