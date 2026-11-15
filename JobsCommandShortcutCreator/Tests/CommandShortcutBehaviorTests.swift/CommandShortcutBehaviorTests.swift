//
//  CommandShortcutBehaviorTests.swift
//  JobsCommandShortcutCreatorTests
//
//  Created by Jobs on 2026年11月13日，星期五.
//

import AppKit
import Darwin

// 对话框为硬失败替身；测试必须注入输入，不能触及用户的 Finder 或 UI。
enum CommandShortcutInterface {

    static func askName(directory: URL,
                        name: String,
                        error: String?) -> String? {
        fatalError("Unexpected real UI")
    }
}

@main
enum CommandShortcutBehaviorTests {

    private static var assertions = 0
    private static let manager = FileManager.default

    static func main() throws {
        guard let suite = ProcessInfo.processInfo.environment["JOBS_SHORTCUT_TEST_SUITE"],
              suite.hasPrefix("com.jobs.command-shortcut.tests.") else {
            fatalError("Tests must use an isolated preferences suite")
        }
        defer {
            UserDefaults.standard.removePersistentDomain(forName: suite)
        }
        if CommandLine.arguments.contains("--cleanup") {
            return
        }
        let root = manager.temporaryDirectory.appendingPathComponent("CommandShortcutTests-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: root, withIntermediateDirectories: false)
        defer {
            try? manager.removeItem(at: root)
        }
        try verifyContext(root)
        try verifyCreationAndCollision(root)
        try verifyConcurrentCreation(root)
        try verifyForwardingAndRelocation(root)
        try verifyMissingCompanion(root)
        try verifyRequests(root)
        try verifyController(root)
        verifyLocalization()
        print("PASS: \(assertions) script launcher behavior assertions")
    }

    private static func makePackage(_ root: URL,
                                    _ name: String,
                                    interpreter: String = "#!/bin/zsh",
                                    executable: Bool = false) throws -> URL {
        let package = root.appendingPathComponent(name, isDirectory: true)
        try manager.createDirectory(at: package, withIntermediateDirectories: false)
        let source = package.appendingPathComponent(name)
        let body = interpreter + "\nprintf '%s\\0' \"$PWD\" \"$@\"\nexit 23\n"
        try Data(body.utf8).write(to: source)
        try manager.setAttributes([.posixPermissions: executable ? 0o755 : 0o644], ofItemAtPath: source.path)
        try Data("fixture README".utf8).write(to: package.appendingPathComponent("README.md"))
        return package
    }

    private static func verifyContext(_ root: URL) throws {
        let valid = try makePackage(root, "context.command")
        check(CommandShortcutContext.directory(isContainer: true, targetedURL: valid) == valid.standardizedFileURL, "same-name package is accepted")
        check(CommandShortcutContext.directory(isContainer: false, targetedURL: valid) == nil, "disabled context is excluded")
        check(CommandShortcutContext.directory(isContainer: true, targetedURL: nil) == nil, "missing target is excluded")
        let missing = root.appendingPathComponent("missing.command", isDirectory: true)
        let noScript = root.appendingPathComponent("no-script.command", isDirectory: true)
        try manager.createDirectory(at: noScript, withIntermediateDirectories: false)
        let wrongExtension = try makePackage(root, "wrong.sh")
        let scriptFolder = root.appendingPathComponent("script-folder.command", isDirectory: true)
        try manager.createDirectory(at: scriptFolder.appendingPathComponent("script-folder.command", isDirectory: true), withIntermediateDirectories: true)
        let linkedPackage = root.appendingPathComponent("linked.command", isDirectory: true)
        try manager.createSymbolicLink(at: linkedPackage, withDestinationURL: valid)
        let sourceLinkPackage = root.appendingPathComponent("source-link.command", isDirectory: true)
        try manager.createDirectory(at: sourceLinkPackage, withIntermediateDirectories: false)
        try manager.createSymbolicLink(at: sourceLinkPackage.appendingPathComponent("source-link.command"), withDestinationURL: valid.appendingPathComponent("context.command"))
        let wrongName = root.appendingPathComponent("wrong-name.command", isDirectory: true)
        try manager.createDirectory(at: wrongName, withIntermediateDirectories: false)
        try Data("#!/bin/zsh\n".utf8).write(to: wrongName.appendingPathComponent("different.command"))
        let values = [missing, noScript, wrongExtension, scriptFolder, linkedPackage, sourceLinkPackage, wrongName,
                      valid.appendingPathComponent("context.command"), URL(string: "https://example.com/a.command")!,
                      URL(string: valid.absoluteString + "?query=1")!, URL(string: valid.absoluteString + "#fragment")!]
        for url in values {
            check(CommandShortcutContext.directory(isContainer: true, targetedURL: url) == nil, "invalid target is excluded: \(url.lastPathComponent)")
        }
    }

    private static func verifyCreationAndCollision(_ root: URL) throws {
        let package = try makePackage(root, "create.command")
        let source = package.appendingPathComponent("create.command")
        let original = try Data(contentsOf: source)
        let service = CommandShortcutService()
        let name = "中文 ' \" $() `id` \\ (入口).command"
        let launcher = try service.create(name: name, in: package)
        check(launcher.deletingLastPathComponent() == root, "launcher is beside the selected folder")
        check(launcher.lastPathComponent == name, "custom filename is retained literally")
        let attributes = try manager.attributesOfItem(atPath: launcher.path)
        check(attributes[.type] as? FileAttributeType == .typeRegular, "launcher is a real script, not a Finder alias or symlink")
        check((attributes[.posixPermissions] as! NSNumber).intValue == 0o755, "launcher has execute permission")
        let content = try String(contentsOf: launcher, encoding: .utf8)
        check(content.contains("./create.command/create.command"), "launcher records a relative companion path")
        check(!content.contains(root.path), "launcher contains no original absolute path")
        check(try Data(contentsOf: source) == original, "creation preserves source bytes")
        check(((try manager.attributesOfItem(atPath: source.path))[.posixPermissions] as! NSNumber).intValue == 0o644, "creation preserves source permissions")
        check(try String(contentsOf: package.appendingPathComponent("README.md"), encoding: .utf8) == "fixture README", "creation preserves package README")
        let ordinary = root.appendingPathComponent("ordinary.command")
        let protected = Data("existing data".utf8)
        try protected.write(to: ordinary)
        let dangling = root.appendingPathComponent("dangling.command")
        try manager.createSymbolicLink(at: dangling, withDestinationURL: root.appendingPathComponent("absent"))
        let linked = root.appendingPathComponent("linked-file.command")
        try manager.createSymbolicLink(at: linked, withDestinationURL: ordinary)
        for target in [package, ordinary, dangling, linked, launcher] {
            do {
                _ = try service.create(name: target.lastPathComponent, in: package)
                fatalError("Occupied path was overwritten")
            } catch CommandShortcutService.Failure.occupied {
                check(true, "occupied file, folder and symlink are preserved")
            }
        }
        check(try Data(contentsOf: ordinary) == protected, "existing file data survives all collisions")
        check(try manager.destinationOfSymbolicLink(atPath: dangling.path).hasSuffix("absent"), "dangling link remains unchanged")
        check(try manager.destinationOfSymbolicLink(atPath: linked.path) == ordinary.path, "live link remains unchanged")
        let before = Set(try manager.contentsOfDirectory(atPath: root.path))
        for invalid in ["", " ", ".command", "README", "one.sh", "a/b.command", "../escape.command", "a:b.command", "a\0b.command", "a\nb.command", "a\rb.command", "a\tb.command", "a\u{2028}b.command", String(repeating: "x", count: 256) + ".command"] {
            do {
                _ = try service.create(name: invalid, in: package)
                fatalError("Invalid name was accepted: \(invalid)")
            } catch CommandShortcutService.Failure.invalidName {
                check(true, "invalid name is rejected before writing")
            }
        }
        check(Set(try manager.contentsOfDirectory(atPath: root.path)) == before, "invalid names do not create any files")
    }

    private static func verifyConcurrentCreation(_ root: URL) throws {
        let package = try makePackage(root, "concurrency.command")
        let lock = NSLock()
        var successes = 0
        var collisions = 0
        var unexpected: [String] = []
        DispatchQueue.concurrentPerform(iterations: 20) { _ in
            do {
                _ = try CommandShortcutService().create(name: "one-winner.command", in: package)
                lock.lock()
                successes += 1
                lock.unlock()
            } catch CommandShortcutService.Failure.occupied {
                lock.lock()
                collisions += 1
                lock.unlock()
            } catch {
                lock.lock()
                unexpected.append(error.localizedDescription)
                lock.unlock()
            }
        }
        check(successes == 1 && collisions == 19 && unexpected.isEmpty, "concurrent creation has exactly one winner and preserves it")
        check(try String(contentsOf: root.appendingPathComponent("one-winner.command"), encoding: .utf8) == CommandShortcutService.content(packageName: package.lastPathComponent), "concurrent output is complete")
    }

    private static func run(_ launcher: URL,
                            arguments: [String] = [],
                            cwd: URL) throws -> (Int32, Data, String) {
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = launcher
        process.arguments = arguments
        process.currentDirectoryURL = cwd
        process.standardOutput = output
        process.standardError = error
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let message = error.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, data, String(decoding: message, as: UTF8.self))
    }

    private static func verifyForwardingAndRelocation(_ root: URL) throws {
        let arguments = ["空 格", "", "single'quote", "double\"quote", "$(touch SHOULD_NOT_EXIST)", "`touch SHOULD_NOT_EXIST`", "line\nbreak", "--flag", "\\", "*"]
        let folder = root.appendingPathComponent("中文 空格 ' $ `echo nope` \\", isDirectory: true)
        try manager.createDirectory(at: folder, withIntermediateDirectories: false)
        for (index, interpreter) in ["#!/bin/zsh", "#!/bin/bash", "#!/bin/sh", "#!/usr/bin/env zsh", "#!/usr/bin/env bash", "#!/usr/bin/env sh"].enumerated() {
            let package = try makePackage(folder, "中文 ' $ `echo` (\(index)).command", interpreter: interpreter)
            let launcher = try CommandShortcutService().create(name: "入口 \(index).command", in: package)
            let syntax = try run(URL(fileURLWithPath: "/bin/zsh"), arguments: ["-n", launcher.path], cwd: root)
            check(syntax.0 == 0, "generated launcher passes zsh syntax validation")
            let execution = try run(launcher, arguments: arguments, cwd: URL(fileURLWithPath: "/"))
            let fields = execution.1.split(separator: 0, omittingEmptySubsequences: false).dropLast().map { String(decoding: $0, as: UTF8.self) }
            check(execution.0 == 23, "source exit code reaches caller for \(interpreter)")
            check(fields.first.map { sameDirectory($0, folder.path) } == true && Array(fields.dropFirst()) == arguments, "all parameters remain literal and working directory follows launcher for \(interpreter)")
            check(execution.2.isEmpty, "supported source shell emits no wrapper error")
            check(!manager.fileExists(atPath: folder.appendingPathComponent("SHOULD_NOT_EXIST").path), "paths and parameters are never shell-evaluated")
            let mode = try manager.attributesOfItem(atPath: package.appendingPathComponent(package.lastPathComponent).path)[.posixPermissions] as! NSNumber
            check(mode.intValue == 0o644, "launching does not grant source execute permission")
        }
        let moved = root.appendingPathComponent("搬移 后新位置", isDirectory: true)
        try manager.moveItem(at: folder, to: moved)
        let movedLauncher = moved.appendingPathComponent("入口 0.command")
        let result = try run(movedLauncher, arguments: ["after move"], cwd: URL(fileURLWithPath: "/"))
        let fields = result.1.split(separator: 0, omittingEmptySubsequences: false).dropLast().map { String(decoding: $0, as: UTF8.self) }
        check(result.0 == 23 && fields.first.map { sameDirectory($0, moved.path) } == true && Array(fields.dropFirst()) == ["after move"], "complete directory can be relocated and renamed without changing launcher")
    }

    private static func verifyMissingCompanion(_ root: URL) throws {
        let package = try makePackage(root, "missing-companion.command")
        let launcher = try CommandShortcutService().create(name: "missing-launcher.command", in: package)
        let source = package.appendingPathComponent(package.lastPathComponent)
        try manager.removeItem(at: source)
        let absent = try run(launcher, cwd: root)
        check(absent.0 != 0 && !absent.2.isEmpty, "removed companion fails with a useful diagnostic")
        let outside = root.appendingPathComponent("outside-script")
        try Data("#!/bin/zsh\nprintf 'should not execute'\n".utf8).write(to: outside)
        try manager.createSymbolicLink(at: source, withDestinationURL: outside)
        let sourceLink = try run(launcher, cwd: root)
        check(sourceLink.0 != 0 && sourceLink.1.isEmpty, "substituted source symlink is rejected before execution")
        try manager.removeItem(at: package)
        let externalPackage = try makePackage(root, "external.command")
        try manager.createSymbolicLink(at: package, withDestinationURL: externalPackage)
        let packageLink = try run(launcher, cwd: root)
        check(packageLink.0 != 0 && packageLink.1.isEmpty, "substituted package symlink is rejected before execution")
    }

    private static func verifyRequests(_ root: URL) throws {
        let special = try makePackage(root, "请求 中文 空格 ' $ `id` \\.command")
        let identifier = UUID()
        let request = CommandShortcutRequest(directoryURL: special, identifier: identifier)!
        let url = request.url!
        let restored = CommandShortcutRequest(url: url)
        check(restored?.directoryURL == special.standardizedFileURL && restored?.identifier == identifier, "path and click identity round-trip exactly")
        let valid = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        for mutate in [
            { (c: inout URLComponents) in c.scheme = "https" },
            { (c: inout URLComponents) in c.host = "other" },
            { (c: inout URLComponents) in c.user = "user" },
            { (c: inout URLComponents) in c.password = "value" },
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
            check(CommandShortcutRequest(url: malformed.url!) == nil, "malformed URL cannot create a launcher")
        }
        try manager.removeItem(at: special)
        check(CommandShortcutRequest(url: url) == nil, "a request is revalidated against the live filesystem at receipt")
    }

    private static func verifyController(_ root: URL) throws {
        let package = try makePackage(root, "controller.command")
        var prompts = 0
        var writes = 0
        var reveals: [URL] = []
        var cancel = CommandShortcutController()
        cancel.askName = { directory, name, error in
            prompts += 1
            check(directory == package, "prompt remains bound to clicked folder")
            check(name == "controller" + CommandShortcutLocalization.text("suffix") + ".command" && error == nil, "default avoids the occupied directory name")
            return nil
        }
        cancel.createFile = { _, _ in
            writes += 1
            fatalError("Cancellation cannot write")
        }
        cancel.reveal = { reveals.append($0) }
        cancel.run(in: package)
        check(prompts == 1 && writes == 0 && reveals.isEmpty, "cancel creates nothing and does not reveal an unrelated path")
        var answers = ["controller.command", "controller-launcher.command"]
        var retry = CommandShortcutController()
        retry.askName = { directory, name, error in
            if answers.count == 1 {
                check(name == "controller.command" && error?.isEmpty == false, "collision preserves input and displays the reason")
            }
            return answers.isEmpty ? nil : answers.removeFirst()
        }
        retry.createFile = { name, directory in
            writes += 1
            return try CommandShortcutService().create(name: name, in: directory)
        }
        retry.reveal = { reveals.append($0) }
        retry.run(in: package)
        check(writes == 2 && reveals == [root.appendingPathComponent("controller-launcher.command")], "retry writes one complete launcher and reveals only the successful result")
        check(answers.isEmpty, "successful creation stops the input loop")
    }

    private static func verifyLocalization() {
        check(CommandShortcutLocalization.languages.count == 10 && Set(CommandShortcutLocalization.languages).count == 10, "ten required languages are available")
        check(CommandShortcutLocalization.languageNames.count == 10, "every language has a visible selection label")
        for (index, language) in CommandShortcutLocalization.languages.enumerated() {
            CommandShortcutLocalization.defaults.set(language, forKey: "language")
            check(CommandShortcutLocalization.language == language, "selected language is honored: \(language)")
            for (key, values) in CommandShortcutLocalization.translations {
                check(CommandShortcutLocalization.text(key) == values[index], "selected locale returns its own translation: \(language)/\(key)")
            }
        }
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        for (theme, appearance) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
            CommandShortcutLocalization.defaults.set(theme, forKey: "theme")
            CommandShortcutLocalization.applyAppearance()
            check(application.appearance?.name == appearance, "selected theme is applied: \(theme)")
        }
        CommandShortcutLocalization.defaults.set("system", forKey: "theme")
        CommandShortcutLocalization.applyAppearance()
        check(application.appearance == nil, "system theme clears the app override")
        for (key, values) in CommandShortcutLocalization.translations {
            check(values.count == 10 && values.allSatisfy { !$0.isEmpty }, "every text key has a nonempty translation in all ten languages: \(key)")
        }
        check(["zh-Hans", "zh-Hant", "bo", "en", "ja", "fr", "es", "de", "ru", "ko"] == CommandShortcutLocalization.languages, "the required language set is exact")
    }

    private static func sameDirectory(_ first: String,
                                      _ second: String) -> Bool {
        var left = stat()
        var right = stat()
        guard stat(first, &left) == 0,
              stat(second, &right) == 0 else {
            return false
        }
        return left.st_dev == right.st_dev && left.st_ino == right.st_ino
    }

    private static func check(_ condition: Bool,
                              _ message: String) {
        assertions += 1
        guard condition else {
            fatalError(message)
        }
    }
}
