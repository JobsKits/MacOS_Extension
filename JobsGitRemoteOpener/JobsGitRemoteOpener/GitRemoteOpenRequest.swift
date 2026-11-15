//
//  GitRemoteOpenRequest.swift
//  JobsGitRemoteOpener
//
//  Created by Jobs on 2026年11月13日，星期五.
//

import Foundation

/// Finder 与宿主只传目录数据，远程选择由非沙盒宿主负责。
struct GitRemoteOpenRequest {

    let projectURL: URL

    init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "jobsgitremoteopener",
              components.host == "open",
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
        let projectURL = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        guard Self.isOrdinaryDirectory(projectURL) else {
            return nil
        }
        self.projectURL = projectURL
    }

    static func url(for projectURL: URL) -> URL? {
        guard isOrdinaryDirectory(projectURL) else {
            return nil
        }
        var components = URLComponents()
        components.scheme = "jobsgitremoteopener"
        components.host = "open"
        components.queryItems = [URLQueryItem(name: "path", value: projectURL.standardizedFileURL.path)]
        return components.url
    }

    private static func isOrdinaryDirectory(_ url: URL) -> Bool {
        guard url.isFileURL,
              url.host == nil || url.host == "" || url.host?.lowercased() == "localhost",
              url.query == nil,
              url.fragment == nil,
              !url.path.utf8.contains(0),
              let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isAliasFileKey, .isPackageKey]),
              values.isDirectory == true,
              values.isSymbolicLink != true,
              values.isAliasFile != true,
              values.isPackage != true else {
            return false
        }
        return true
    }
}
