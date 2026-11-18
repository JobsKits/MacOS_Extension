//
//  SendToRequest.swift
//  JobsSendTo
//
//  Created by Jobs on 2026年11月18日，星期三.
//

import Foundation

struct SendToRequest {

    let sources: [SendToSource]
    let destination: SendToVolume?
    let identifier: UUID

    init?(sources: [SendToSource], destination: SendToVolume?, identifier: UUID = UUID()) {
        guard Self.validSources(sources),
              destination.map({ Self.localURL($0.url) && $0.rootURL == nil && $0.rootIdentity == nil }) ?? true else {
            return nil
        }
        self.sources = sources
        self.destination = destination
        self.identifier = identifier
        guard url != nil else {
            return nil
        }
    }

    init?(url: URL) {
        guard url.absoluteString.utf8.count <= 65536,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "jobssendto",
              parts.host == "copy" || parts.host == "choose",
              parts.path.isEmpty,
              parts.user == nil, parts.password == nil,
              parts.port == nil, parts.fragment == nil,
              let items = parts.queryItems,
              items.count == (parts.host == "copy" ? 3 : 2),
              Set(items.map(\.name)) == (parts.host == "copy" ? ["sources", "destination", "id"] : ["sources", "id"]),
              let rawID = items.first(where: { $0.name == "id" })?.value,
              let identifier = UUID(uuidString: rawID),
              let rawSources = items.first(where: { $0.name == "sources" })?.value,
              let sourceData = Self.decode(rawSources),
              Self.strictSources(sourceData),
              let sources = try? JSONDecoder().decode([SendToSource].self, from: sourceData),
              Self.validSources(sources) else {
            return nil
        }
        let destination: SendToVolume?
        if parts.host == "copy" {
            guard let raw = items.first(where: { $0.name == "destination" })?.value,
                  let data = Self.decode(raw),
                  Self.strictVolume(data),
                  let volume = try? JSONDecoder().decode(SendToVolume.self, from: data),
                  Self.localURL(volume.url) else {
                return nil
            }
            destination = volume
        } else {
            destination = nil
        }
        self.sources = sources
        self.destination = destination
        self.identifier = identifier
    }

    var url: URL? {
        guard let sourceData = try? JSONEncoder().encode(sources) else {
            return nil
        }
        var items = [URLQueryItem(name: "sources", value: Self.encode(sourceData)),
                     URLQueryItem(name: "id", value: identifier.uuidString)]
        if let destination {
            guard let data = try? JSONEncoder().encode(destination) else {
                return nil
            }
            items.append(URLQueryItem(name: "destination", value: Self.encode(data)))
        }
        var parts = URLComponents()
        parts.scheme = "jobssendto"
        parts.host = destination == nil ? "choose" : "copy"
        parts.queryItems = items
        guard let result = parts.url, result.absoluteString.utf8.count <= 65536 else {
            return nil
        }
        return result
    }

    private static func validSources(_ sources: [SendToSource]) -> Bool {
        return !sources.isEmpty && sources.count <= 128 &&
            Set(sources.map { $0.url.path }).count == sources.count &&
            sources.allSatisfy { localURL($0.url) && $0.url.path != "/" }
    }

    private static func localURL(_ url: URL) -> Bool {
        return url.isFileURL && url.path.hasPrefix("/") && !url.path.contains("\0") &&
            url.standardizedFileURL.path == url.path && url.query == nil && url.fragment == nil &&
            (url.host == nil || url.host == "" || url.host == "localhost")
    }

    private static func encode(_ data: Data) -> String {
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func decode(_ text: String) -> Data? {
        guard !text.isEmpty, text.utf8.count <= 65536,
              text.unicodeScalars.allSatisfy({
                  CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_").contains($0)
              }) else {
            return nil
        }
        var value = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        value += String(repeating: "=", count: (4 - value.count % 4) % 4)
        guard let data = Data(base64Encoded: value), encode(data) == text else {
            return nil
        }
        return data
    }

    private static func strictSources(_ data: Data) -> Bool {
        guard let values = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            return false
        }
        return values.allSatisfy {
            Set($0.keys) == ["url", "identity", "kind"] && strictIdentity($0["identity"])
        }
    }

    private static func strictVolume(_ data: Data) -> Bool {
        guard let value = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return false
        }
        return Set(value.keys) == ["url", "name", "identity", "isNetwork"] && strictIdentity(value["identity"])
    }

    private static func strictIdentity(_ value: Any?) -> Bool {
        guard let identity = value as? [String: Any] else {
            return false
        }
        return Set(identity.keys) == ["dev", "ino"]
    }
}
