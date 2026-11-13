//
//  FileHashBehaviorTests.swift
//  JobsFileHasherTests
//
//  Created by Jobs on 2026年11月6日，星期五.
//

import Foundation
import Darwin

@main
enum FileHashBehaviorTests {

    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let file = root.appendingPathComponent("中文 '引号' $(touch HACKED) `echo no`; [x]\n\u{1B}[31m.txt")
        try Data("abc".utf8).write(to: file)
        let expected = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        try require(FileHashService.sha256(file) == expected, "SHA-256 known vector")
        let empty = root.appendingPathComponent("empty")
        try Data().write(to: empty)
        try require(FileHashService.sha256(empty) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "empty file")
        let large = root.appendingPathComponent("binary.bin")
        try Data(repeating: 0xa5, count: 3 * 1024 * 1024 + 17).write(to: large)
        let knownLarge = "4dfc2cd504d032c1f86359f63df9b744757d06e0baa7f8a7ac872e8544678db5"
        try require(FileHashService.sha256(large) == knownLarge, "multi-chunk binary")
        try require(FileHashTarget.singleSelection([file]) == file, "one regular file")
        try require(FileHashTarget.singleSelection([file, empty]) == nil, "reject multi-selection")
        try require(FileHashTarget.singleSelection([]) == nil, "reject empty selection")
        try require(FileHashTarget.regularFile(root) == nil, "reject directory")
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        try require(FileHashTarget.regularFile(link) == nil, "reject symlink")
        let fifo = root.appendingPathComponent("fifo")
        try require(mkfifo(fifo.path, 0o600) == 0, "create fifo")
        try require(FileHashTarget.regularFile(fifo) == nil, "reject FIFO without read")
        var copied: [String] = []
        try require(FileHashCommand.run(path: file.path, copy: { copied.append($0) }) == 0, "terminal command success")
        try require(copied == [expected], "copy exact digest without newline")
        for invalid in [root.path, link.path, fifo.path, root.appendingPathComponent("missing").path, "relative"] {
            let oldCount = copied.count
            try require(FileHashCommand.run(path: invalid, copy: { copied.append($0) }) != 0, "reject invalid command")
            try require(copied.count == oldCount, "failed read preserves clipboard")
        }
        try require(FileHashCommand.run(path: file.path, copy: { _ in throw FileHashFailure.message("simulated clipboard failure") }) != 0, "clipboard failure is error")
        let request = FileHashRequest(fileURL: file)!
        let roundTrip = FileHashRequest(url: request.url!)!
        try require(roundTrip.fileURL == file && roundTrip.identifier == request.identifier, "URL round trip preserves unusual path")
        try require(FileHashRequest(url: URL(string: request.url!.absoluteString + "&p=extra")!) == nil, "reject duplicate URL key")
        try require(FileHashRequest(url: URL(string: request.url!.absoluteString.replacingOccurrences(of: "jobsfilehasher:", with: "other:"))!) == nil, "reject foreign scheme")
        let replacement = root.appendingPathComponent("replacement")
        try Data("before".utf8).write(to: replacement)
        let stale = FileHashRequest(fileURL: replacement)!.url!
        try FileManager.default.removeItem(at: replacement)
        try FileManager.default.createSymbolicLink(at: replacement, withDestinationURL: file)
        try require(FileHashRequest(url: stale) == nil, "revalidate URL after selection changes")
        try verifyCarrier(root: root, file: file)
        print("PASS: file hash vectors, guards, clipboard sequencing, URL transport and terminal carrier")
    }

    private static func verifyCarrier(root: URL,
                                      file: URL) throws {
        let captured = root.appendingPathComponent("captured")
        let fake = root.appendingPathComponent("fake 'hash'\napp")
        let script = "#!/bin/zsh\n[[ \"$1\" == --hash-file ]] || exit 9\n/usr/bin/printf '%s' \"$2\" > " + FileHashTerminalLauncher.shellQuote(captured.path) + "\nexit 37\n"
        try script.write(to: fake, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fake.path)
        let carrier = try FileHashTerminalLauncher.prepareCarrier(executable: fake, file: file, temporaryRoot: root)
        let directory = carrier.deletingLastPathComponent()
        let fileMode = try FileManager.default.attributesOfItem(atPath: carrier.path)[.posixPermissions] as! NSNumber
        let dirMode = try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as! NSNumber
        try require(fileMode.intValue == 0o600 && dirMode.intValue == 0o700, "private carrier permissions")
        let process = Process.make(executableURL: URL(fileURLWithPath: "/bin/zsh"), arguments: [carrier.path])
        try process.run()
        process.waitUntilExit()
        try require(process.terminationStatus == 37, "carrier preserves business status")
        try require(Data(contentsOf: captured) == Data(file.path.utf8), "carrier passes path literally")
        try require(!FileManager.default.fileExists(atPath: directory.path), "carrier self cleans")
        try require(!FileManager.default.fileExists(atPath: root.appendingPathComponent("HACKED").path), "no command injection")
        for (signal, expectedStatus) in [("INT", Int32(130)), ("TERM", Int32(143)), ("HUP", Int32(129))] {
            let cancellation = "#!/bin/zsh\n/bin/kill -" + signal + " \"$PPID\"\nexit 0\n"
            try cancellation.write(to: fake, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fake.path)
            let cancellingCarrier = try FileHashTerminalLauncher.prepareCarrier(executable: fake, file: file, temporaryRoot: root)
            let cancellingProcess = Process.make(executableURL: URL(fileURLWithPath: "/bin/zsh"), arguments: [cancellingCarrier.path])
            try cancellingProcess.run()
            cancellingProcess.waitUntilExit()
            try require(cancellingProcess.terminationStatus == expectedStatus, "carrier propagates " + signal)
            try require(!FileManager.default.fileExists(atPath: cancellingCarrier.deletingLastPathComponent().path), "carrier cleans after " + signal)
        }
    }

    private static func require(_ condition: @autoclosure () throws -> Bool,
                                _ message: String) throws {
        guard try condition() else {
            throw FileHashFailure.message("FAIL: " + message)
        }
    }
}
