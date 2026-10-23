//
//  IPAResignRequest.swift
//  JobsIPAResignShared
//
//  Created by Jobs on 2026年10月23日，星期五.
//

import Foundation

/// 路径通过 URL 数据传递，宿主收到后再次检查文件类型。
enum IPAResignRequest {
    static let scheme = "jobsiparesigner"

    static func url(for fileURL: URL) -> URL? {
        guard IPAResignValidator().isRegularFile(at: fileURL) else {
            return nil
        }
        var components = URLComponents()
        components.scheme = scheme
        components.host = "resign"
        components.queryItems = [URLQueryItem(name: "path", value: fileURL.standardizedFileURL.path)]
        return components.url
    }

    static func fileURL(from requestURL: URL) -> URL? {
        guard let components = URLComponents(url: requestURL, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == scheme,
              components.host == "resign",
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
        let fileURL = URL(fileURLWithPath: path, isDirectory: false).standardizedFileURL
        guard IPAResignValidator().isRegularFile(at: fileURL) else {
            return nil
        }
        return fileURL
    }
}
