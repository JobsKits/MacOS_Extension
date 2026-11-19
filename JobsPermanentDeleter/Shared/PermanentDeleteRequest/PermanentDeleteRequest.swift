//
//  PermanentDeleteRequest.swift
//  JobsPermanentDeleter
//
//  Created by Jobs on 2026年11月18日，星期三.
//

import Foundation
import Darwin

struct PermanentDeleteRequest {

    let items: [PermanentDeleteContext.Item]
    let identifier: UUID

    init?(urls: [URL], identifier: UUID = UUID()) {
        guard !urls.isEmpty, urls.count <= 128 else {
            return nil
        }
        let snapshots = urls.compactMap(PermanentDeleteContext.snapshot)
        guard snapshots.count == urls.count,
              PermanentDeleteContext.validSelection(snapshots) else {
            return nil
        }
        self.items = snapshots
        self.identifier = identifier
        guard url != nil else {
            return nil
        }
    }

    init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "jobspermanentdelete",
              components.host == "delete",
              components.path.isEmpty,
              components.user == nil, components.password == nil,
              components.port == nil, components.fragment == nil,
              let query = components.queryItems, query.count == 2,
              query.filter({ $0.name == "items" }).count == 1,
              query.filter({ $0.name == "id" }).count == 1,
              let encoded = query.first(where: { $0.name == "items" })?.value,
              !encoded.isEmpty, encoded.utf8.count <= 32768,
              encoded.unicodeScalars.allSatisfy({
                  CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_").contains($0)
              }),
              let rawID = query.first(where: { $0.name == "id" })?.value,
              let identifier = UUID(uuidString: rawID) else {
            return nil
        }
        var base64 = encoded.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64),
              let items = try? JSONDecoder().decode([PermanentDeleteContext.Item].self, from: data),
              !items.isEmpty, items.count <= 128,
              PermanentDeleteContext.validSelection(items),
              items.allSatisfy({
                  $0.path.hasPrefix("/") && $0.path != "/" && !$0.path.contains("\0") &&
                      PermanentDeleteContext.validPath($0.path) &&
                      ($0.kind == UInt16(S_IFREG) || $0.kind == UInt16(S_IFDIR) || $0.kind == UInt16(S_IFLNK))
              }) else {
            return nil
        }
        self.items = items
        self.identifier = identifier
    }

    var url: URL? {
        guard let data = try? JSONEncoder().encode(items) else {
            return nil
        }
        let encoded = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        guard encoded.utf8.count <= 32768 else {
            return nil
        }
        var components = URLComponents()
        components.scheme = "jobspermanentdelete"
        components.host = "delete"
        components.queryItems = [URLQueryItem(name: "items", value: encoded),
                                 URLQueryItem(name: "id", value: identifier.uuidString)]
        return components.url
    }
}
