//
//  FileVisibilityBehaviorTests.swift
//  JobsFileVisibilityTests
//
//  Created by Jobs on 2026年11月18日，星期三.
//

import Foundation
import Darwin

@main
struct FileVisibilityBehaviorTests {

    static var assertions = 0

    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        guard condition() else {
            fatalError(message)
        }
    }

    static func flags(_ url: URL) -> UInt32 {
        var value = stat()
        check(lstat(url.path, &value) == 0, "stat")
        return value.st_flags
    }

    static func rejects(_ action: () throws -> Void, _ message: String) {
        do {
            try action()
            fatalError(message)
        } catch {
            assertions += 1
        }
    }

    static func main() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("jobs visibility 中文 '\n$() " + UUID().uuidString)
        try manager.createDirectory(at: root, withIntermediateDirectories: false)
        defer {
            try? manager.removeItem(at: root)
        }
        let file = root.appendingPathComponent("file 中文 '$()\n.txt")
        let folder = root.appendingPathComponent("folder")
        let child = folder.appendingPathComponent("child")
        try Data("unchanged".utf8).write(to: file)
        try manager.createDirectory(at: folder, withIntermediateDirectories: false)
        try Data("child".utf8).write(to: child)
        let item = FileVisibilityContext.snapshot(file)!
        let folderItem = FileVisibilityContext.snapshot(folder)!
        check(chflags(file.path, UInt32(UF_NODUMP)) == 0, "set unrelated flag")
        try FileVisibilityService.apply(item, hidden: true)
        check(flags(file) == UInt32(UF_HIDDEN | UF_NODUMP), "hide preserves unrelated flags")
        try FileVisibilityService.apply(item, hidden: true)
        check(flags(file) == UInt32(UF_HIDDEN | UF_NODUMP), "hide idempotent")
        try FileVisibilityService.apply(folderItem, hidden: true)
        check(flags(folder) & UInt32(UF_HIDDEN) != 0, "folder hidden")
        check(flags(child) & UInt32(UF_HIDDEN) == 0, "no recursion")
        try FileVisibilityService.apply(item, hidden: false)
        try FileVisibilityService.apply(folderItem, hidden: false)
        check(flags(file) == UInt32(UF_NODUMP), "show preserves unrelated flags")
        let content = try Data(contentsOf: file)
        check(content == Data("unchanged".utf8), "contents preserved")
        check(chmod(file.path, 0o400) == 0, "read-only mode")
        try FileVisibilityService.apply(item, hidden: true)
        try FileVisibilityService.apply(item, hidden: false)
        var readOnly = stat()
        check(lstat(file.path, &readOnly) == 0 && readOnly.st_mode & 0o777 == 0o400, "read-only mode preserved")
        check(chmod(file.path, 0) == 0, "inaccessible mode")
        rejects({ try FileVisibilityService.apply(item, hidden: true) }, "no permission escalation")
        check(flags(file) & UInt32(UF_HIDDEN) == 0, "inaccessible target unchanged")
        check(chmod(file.path, 0o600) == 0, "restore test mode")
        let hiddenName = root.appendingPathComponent(".dotfile")
        try Data().write(to: hiddenName)
        try FileVisibilityService.apply(FileVisibilityContext.snapshot(hiddenName)!, hidden: false)
        check(manager.fileExists(atPath: hiddenName.path), "dot filename never renamed")
        let link = root.appendingPathComponent("link")
        try manager.createSymbolicLink(at: link, withDestinationURL: file)
        check(FileVisibilityContext.snapshot(link) == nil, "symlink rejected")
        check(FileVisibilityRequest(urls: [link], hidden: true) == nil, "symlink request rejected")
        let fifo = root.appendingPathComponent("fifo")
        check(mkfifo(fifo.path, 0o600) == 0, "make fifo")
        check(FileVisibilityContext.snapshot(fifo) == nil, "special object rejected")
        check(FileVisibilityContext.snapshot(URL(fileURLWithPath: "/")) == nil, "root rejected")
        check(FileVisibilityContext.snapshot(URL(string: "https://example.com/a")!) == nil, "nonlocal target rejected")
        check(FileVisibilityRequest(urls: [], hidden: true) == nil, "empty selection")
        check(FileVisibilityRequest(urls: Array(repeating: file, count: 129), hidden: true) == nil, "bounded selection")
        check(FileVisibilityRequest(urls: [file, file], hidden: true) == nil, "duplicate selection")
        let maxURLs = try (0..<128).map { index -> URL in
            let target = root.appendingPathComponent("item\(index)")
            try manager.linkItem(at: file, to: target)
            return target
        }
        check(FileVisibilityRequest(urls: maxURLs, hidden: true) != nil, "128 distinct items supported")
        var oversized = URLComponents()
        oversized.scheme = "jobsfilevisibility"
        oversized.host = "hide"
        oversized.queryItems = [URLQueryItem(name: "items", value: String(repeating: "A", count: 32769)),
                                URLQueryItem(name: "id", value: UUID().uuidString)]
        check(FileVisibilityRequest(url: oversized.url!) == nil, "oversized transport rejected")
        let valid = FileVisibilityRequest(urls: [file], hidden: true)!
        var malformed = URLComponents(url: valid.url!, resolvingAgainstBaseURL: false)!
        malformed.host = "toggle"
        check(FileVisibilityRequest(url: malformed.url!) == nil, "ambiguous toggle action rejected")
        malformed = URLComponents(url: valid.url!, resolvingAgainstBaseURL: false)!
        malformed.queryItems?.append(URLQueryItem(name: "id", value: valid.identifier.uuidString))
        check(FileVisibilityRequest(url: malformed.url!) == nil, "duplicate identifier rejected")
        for action in [true, false] {
            let request = FileVisibilityRequest(urls: [file, folder], hidden: action)!
            let decoded = FileVisibilityRequest(url: request.url!)!
            check(decoded.hidden == action, "explicit action roundtrip")
            check(decoded.identifier == request.identifier, "request dedup ID roundtrip")
            check(decoded.items.map(\.path) == [file.path, folder.path], "literal special paths roundtrip")
            check(FileVisibilityRequest(url: URL(string: request.url!.absoluteString + "&unknown=1")!) == nil, "unknown query rejected")
            check(FileVisibilityRequest(url: URL(string: request.url!.absoluteString + "#fragment")!) == nil, "fragment rejected")
        }
        let stale = FileVisibilityContext.snapshot(file)!
        let original = root.appendingPathComponent("original")
        try manager.moveItem(at: file, to: original)
        try Data("replacement".utf8).write(to: file)
        rejects({ try FileVisibilityService.apply(stale, hidden: true) }, "replacement must fail")
        check(flags(file) & UInt32(UF_HIDDEN) == 0, "replacement remains visible")
        try manager.removeItem(at: file)
        try manager.createSymbolicLink(at: file, withDestinationURL: original)
        rejects({ try FileVisibilityService.apply(stale, hidden: true) }, "late symlink must fail")
        check(flags(original) == UInt32(UF_NODUMP), "late symlink target unchanged")
        try manager.removeItem(at: file)
        rejects({ try FileVisibilityService.apply(stale, hidden: true) }, "missing target must fail")
        print("FileVisibility: \(assertions) assertions passed")
    }
}
