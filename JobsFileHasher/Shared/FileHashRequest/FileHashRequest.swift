//
//  FileHashRequest.swift
//  JobsFileHasherShared
//
//  Created by Jobs on 2026年11月6日，星期五.
//

import Foundation

struct FileHashRequest {

    let fileURL: URL
    let identifier: UUID

    init?(fileURL: URL,
          identifier: UUID = UUID()) {
        guard let file = FileHashTarget.regularFile(fileURL) else {
            return nil
        }
        self.fileURL = file
        self.identifier = identifier
    }

    init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "jobsfilehasher",
              components.host == "hash",
              components.path.isEmpty,
              components.user == nil,
              components.password == nil,
              components.port == nil,
              components.fragment == nil,
              let items = components.queryItems,
              items.count == 2,
              items.filter({
                  $0.name == "p"
              }).count == 1,
              items.filter({
                  $0.name == "id"
              }).count == 1,
              let encoded = items.first(where: {
                  $0.name == "p"
              })?.value,
              !encoded.isEmpty,
              encoded.utf8.count < 32768,
              encoded.unicodeScalars.allSatisfy({
                  CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_").contains($0)
              }),
              let id = items.first(where: {
                  $0.name == "id"
              })?.value,
              let identifier = UUID(uuidString: id) else {
            return nil
        }
        var base64 = encoded.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64),
              let path = String(data: data, encoding: .utf8),
              path.hasPrefix("/"),
              !path.contains("\0") else {
            return nil
        }
        self.init(fileURL: URL(fileURLWithPath: path), identifier: identifier)
    }

    var url: URL? {
        var components = URLComponents()
        components.scheme = "jobsfilehasher"
        components.host = "hash"
        let encoded = Data(fileURL.path.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        components.queryItems = [
            URLQueryItem(name: "p", value: encoded),
            URLQueryItem(name: "id", value: identifier.uuidString)
        ]
        return components.url
    }
}
