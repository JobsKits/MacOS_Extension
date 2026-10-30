//
//  FileCreationRequest.swift
//  JobsFileCreatorShared
//
//  Created by Jobs on 2026年10月29日，星期四.
//

import Foundation

struct FileCreationRequest {

    let directoryURL: URL
    let identifier: UUID

    init?(directoryURL: URL,
          identifier: UUID = UUID()) {
        guard let directory = FileCreationContext.directory(isContainer: true,
                                                            targetedURL: directoryURL) else {
            return nil
        }
        self.directoryURL = directory
        self.identifier = identifier
    }

    init?(url: URL) {
        guard let components = URLComponents(url: url,
                                              resolvingAgainstBaseURL: false),
              components.scheme == "jobsfilecreator",
              components.host == "create",
              components.path.isEmpty,
              components.user == nil,
              components.password == nil,
              components.port == nil,
              components.fragment == nil,
              let items = components.queryItems,
              items.count == 2,
              items.filter({ $0.name == "p" }).count == 1,
              items.filter({ $0.name == "id" }).count == 1,
              let encoded = items.first(where: { $0.name == "p" })?.value,
              !encoded.isEmpty,
              encoded.utf8.count < 32768,
              encoded.unicodeScalars.allSatisfy({
                  CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_").contains($0)
              }),
              let idValue = items.first(where: { $0.name == "id" })?.value,
              let identifier = UUID(uuidString: idValue) else {
            return nil
        }
        var base64 = encoded.replacingOccurrences(of: "-",
                                                  with: "+")
            .replacingOccurrences(of: "_",
                                   with: "/")
        base64 += String(repeating: "=",
                         count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64),
              let path = String(data: data,
                                encoding: .utf8),
              path.hasPrefix("/"),
              !path.contains("\0") else {
            return nil
        }
        self.init(directoryURL: URL(fileURLWithPath: path,
                                    isDirectory: true),
                  identifier: identifier)
    }

    var url: URL? {
        var components = URLComponents()
        components.scheme = "jobsfilecreator"
        components.host = "create"
        let path = Data(directoryURL.path.utf8).base64EncodedString()
            .replacingOccurrences(of: "+",
                                   with: "-")
            .replacingOccurrences(of: "/",
                                   with: "_")
            .replacingOccurrences(of: "=",
                                   with: "")
        components.queryItems = [
            URLQueryItem(name: "p", value: path),
            URLQueryItem(name: "id", value: identifier.uuidString)
        ]
        return components.url
    }
}
