//
//  FileCreationBehaviorTests.swift
//  JobsFileCreatorTests
//
//  Created by Jobs on 2026年10月29日，星期四.
//

import AppKit

// 默认 UI 是硬失败替身；所有对话框和 Finder 定位必须经测试注入。
enum FileCreatorInterface {

    static func askName(_ directory: URL,
                        _ suggestedName: String,
                        _ message: String?) -> String? {
        fatalError("Unexpected real UI")
    }
}

@main
enum FileCreationBehaviorTests {

    private static var assertions = 0

    static func main() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("FileCreationTests-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: root, withIntermediateDirectories: false)
        defer {
            try? manager.removeItem(at: root)
        }
        try verifyContext(root)
        try verifyCreation(root)
        try verifyConcurrentCreation(root)
        try verifyRequests(root)
        try verifyController(root)
        print("PASS: \(assertions) file creation behavior assertions")
    }

    private static func verifyContext(_ root: URL) throws {
        check(FileCreationContext.directory(isContainer: true, targetedURL: root) == root.standardizedFileURL, "directory background is accepted")
        check(FileCreationContext.directory(isContainer: false, targetedURL: root) == nil, "selected-item and toolbar contexts are excluded")
        check(FileCreationContext.directory(isContainer: true, targetedURL: nil) == nil, "missing Finder target is excluded")
        let file = try FileCreationService().create(name: "context.txt", in: root)
        for url in [file, root.appendingPathComponent("missing"), URL(string: "https://example.com")!, URL(string: root.absoluteString + "?query=1")!, URL(string: root.absoluteString + "#fragment")!] {
            check(FileCreationContext.directory(isContainer: true, targetedURL: url) == nil, "invalid or non-directory target is excluded: \(url)")
        }
    }

    private static func verifyCreation(_ root: URL) throws {
        let service = FileCreationService()
        for name in ["未命名.txt", "README", ".gitignore", "中文 ' \" $() `id` \\ (1).md"] {
            let file = try service.create(name: name, in: root)
            check(file.lastPathComponent == name, "filename is preserved without shell interpretation")
            check(try Data(contentsOf: file).isEmpty, "new file starts empty")
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            check(attributes[.type] as? FileAttributeType == .typeRegular, "new object is a regular file")
            check((attributes[.posixPermissions] as! NSNumber).intValue & 0o111 == 0, "new files are not executable")
        }
        for name in ["", " ", "\t", ".", "..", "../escape", "a/b", "a:b", "a\0b", "a\nb", "a\rb", "a\tb", "a\u{2028}b"] {
            do {
                _ = try service.create(name: name, in: root)
                fatalError("Invalid name was accepted")
            } catch FileCreationService.Failure.invalidName {
                check(true, "invalid name is rejected before writing")
            }
        }
        let existing = root.appendingPathComponent("preserve.txt")
        let original = Data("must survive".utf8)
        try original.write(to: existing)
        let directory = root.appendingPathComponent("existing-directory", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let dangling = root.appendingPathComponent("dangling-link")
        try FileManager.default.createSymbolicLink(at: dangling, withDestinationURL: root.appendingPathComponent("absent"))
        let linked = root.appendingPathComponent("existing-link")
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: existing)
        for target in [existing, directory, dangling, linked] {
            do {
                _ = try service.create(name: target.lastPathComponent, in: root)
                fatalError("Occupied path was overwritten")
            } catch FileCreationService.Failure.occupied {
                check(true, "any same-name filesystem object blocks creation")
            }
        }
        check(try Data(contentsOf: existing) == original, "existing contents remain intact")
        check(try FileManager.default.destinationOfSymbolicLink(atPath: dangling.path).hasSuffix("absent"), "dangling link is preserved")
        check(try FileManager.default.destinationOfSymbolicLink(atPath: linked.path) == existing.path, "existing symlink is preserved")
        for destination in [existing, root.appendingPathComponent("missing-parent")] {
            do {
                _ = try service.create(name: "no-write.txt", in: destination)
                fatalError("Invalid directory was accepted")
            } catch FileCreationService.Failure.invalidDirectory {
                check(true, "invalid destination is rejected")
            }
        }
    }

    private static func verifyConcurrentCreation(_ root: URL) throws {
        let lock = NSLock()
        var successes = 0
        var collisions = 0
        var unexpected: [String] = []
        DispatchQueue.concurrentPerform(iterations: 24) { _ in
            do {
                _ = try FileCreationService().create(name: "concurrent.txt", in: root)
                lock.lock()
                successes += 1
                lock.unlock()
            } catch FileCreationService.Failure.occupied {
                lock.lock()
                collisions += 1
                lock.unlock()
            } catch {
                lock.lock()
                unexpected.append(error.localizedDescription)
                lock.unlock()
            }
        }
        check(successes == 1 && collisions == 23 && unexpected.isEmpty, "exclusive creation has exactly one winner")
        check(try Data(contentsOf: root.appendingPathComponent("concurrent.txt")).isEmpty, "racing attempts never alter winner contents")
    }

    private static func verifyRequests(_ root: URL) throws {
        let special = root.appendingPathComponent("中文 空格 ' \" $() `id` \\ \n目录", isDirectory: true)
        try FileManager.default.createDirectory(at: special, withIntermediateDirectories: false)
        let identifier = UUID()
        let request = FileCreationRequest(directoryURL: special, identifier: identifier)!
        let url = request.url!
        let restored = FileCreationRequest(url: url)
        check(restored?.directoryURL.path == special.path, "special directory path round-trips exactly")
        check(restored?.identifier == identifier, "click identifier round-trips exactly")
        let valid = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        for mutate in [
            { (c: inout URLComponents) in c.scheme = "https" },
            { (c: inout URLComponents) in c.host = "other" },
            { (c: inout URLComponents) in c.user = "user" },
            { (c: inout URLComponents) in c.password = "secret" },
            { (c: inout URLComponents) in c.port = 123 },
            { (c: inout URLComponents) in c.path = "/" },
            { (c: inout URLComponents) in c.fragment = "fragment" },
            { (c: inout URLComponents) in c.queryItems!.append(URLQueryItem(name: "extra", value: "x")) },
            { (c: inout URLComponents) in c.queryItems!.append(c.queryItems![0]) },
            { (c: inout URLComponents) in c.queryItems!.removeLast() },
            { (c: inout URLComponents) in c.queryItems![0].value = "" },
            { (c: inout URLComponents) in c.queryItems![0].value = "++++" },
            { (c: inout URLComponents) in c.queryItems![0].value = "A" },
            { (c: inout URLComponents) in c.queryItems![0].value = String(repeating: "A", count: 32768) },
            { (c: inout URLComponents) in c.queryItems![0].value = "cmVsYXRpdmU" },
            { (c: inout URLComponents) in c.queryItems![0].value = "L3RtcAA" },
            { (c: inout URLComponents) in c.queryItems![1].value = "not-a-uuid" }
        ] {
            var malformed = valid
            mutate(&malformed)
            check(FileCreationRequest(url: malformed.url!) == nil, "malformed transport cannot trigger creation")
        }
        try FileManager.default.removeItem(at: special)
        check(FileCreationRequest(url: url) == nil, "request to a deleted directory is rejected at receipt")
    }

    private static func verifyController(_ root: URL) throws {
        var created = 0
        var revealed: [URL] = []
        var prompts: [(String, String?)] = []
        var cancel = FileCreationController()
        cancel.askName = { _, name, message in
            prompts.append((name, message))
            return nil
        }
        cancel.createFile = { _, _ in
            created += 1
            fatalError("Cancel cannot create a file")
        }
        cancel.reveal = { revealed.append($0) }
        cancel.run(in: root)
        check(created == 0 && revealed.isEmpty, "cancel does not create or reveal anything")
        check(prompts.count == 1 && prompts[0].0 == "未命名.txt" && prompts[0].1 == nil, "initial prompt has a useful default and no stale error")
        var answers = ["preserve.txt", "controller-created.md"]
        var retry = FileCreationController()
        retry.askName = { directory, name, message in
            check(directory == root, "retry remains in the clicked folder")
            if answers.count == 1 {
                check(name == "preserve.txt" && message?.isEmpty == false, "failed filename and reason remain visible for correction")
            }
            return answers.isEmpty ? nil : answers.removeFirst()
        }
        retry.createFile = { name, directory in
            created += 1
            return try FileCreationService().create(name: name, in: directory)
        }
        retry.reveal = { revealed.append($0) }
        retry.run(in: root)
        check(created == 2 && revealed == [root.appendingPathComponent("controller-created.md")], "retry creates once after collision and reveals only the result")
        check(answers.isEmpty, "successful creation stops the prompt loop")
    }

    private static func check(_ condition: Bool,
                              _ message: String) {
        assertions += 1
        guard condition else {
            fatalError(message)
        }
    }
}
