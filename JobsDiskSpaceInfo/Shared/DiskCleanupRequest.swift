//
//  DiskCleanupRequest.swift
//  JobsDiskSpaceInfoShared
//
//  Created by Jobs on 2026年11月15日，星期日.
//

import Foundation

struct DiskCleanupRequest {

    let identifier: UUID

    init(identifier: UUID = UUID()) {
        self.identifier = identifier
    }

    init?(url: URL) {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "jobsdiskspaceinfo",
              parts.host == "clean",
              parts.path.isEmpty,
              parts.user == nil,
              parts.password == nil,
              parts.port == nil,
              parts.fragment == nil,
              let items = parts.queryItems,
              items.count == 1,
              items[0].name == "id",
              let value = items[0].value,
              let identifier = UUID(uuidString: value) else {
            return nil
        }
        self.identifier = identifier
    }

    var url: URL? {
        var parts = URLComponents()
        parts.scheme = "jobsdiskspaceinfo"
        parts.host = "clean"
        parts.queryItems = [URLQueryItem(name: "id", value: identifier.uuidString)]
        return parts.url
    }
}
