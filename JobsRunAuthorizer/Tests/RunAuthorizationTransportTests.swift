//
//  RunAuthorizationTransportTests.swift
//  JobsRunAuthorizerTests
//
//  Created by Jobs on 2026年10月22日，星期四.
//

import Foundation

/// 临时文件与假业务脚本验证路径传递；不启动 Terminal 或注册扩展。
@main
enum RunAuthorizationTransportTests {
    private static var assertions = 0

    static func main() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("RunAuthorizationTests-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: root, withIntermediateDirectories: false)
        defer {
            try? manager.removeItem(at: root)
        }
        let file = root.appendingPathComponent("中文 空格 ' \" $() `id` \\ \n\t\u{1B}\u{2028}.command")
        try Data("echo should-never-run".utf8).write(to: file)
        let directory = root.appendingPathComponent("Example.app", isDirectory: true)
        try manager.createDirectory(at: directory, withIntermediateDirectories: false)
        let link = root.appendingPathComponent("file-link")
        try manager.createSymbolicLink(at: link, withDestinationURL: file)
        let validator = RunAuthorizationValidator()
        try check(validator.selectedFile(from: [file]) == file, "单文件应允许")
        for urls: [URL]? in [nil, [], [file, file], [directory], [link], [root.appendingPathComponent("missing")], [URL(string: "https://example.com/file")!]] {
            try check(validator.selectedFile(from: urls) == nil, "非单普通文件应拒绝")
        }
        guard let request = RunAuthorizationRequest.url(for: file) else {
            throw failure("无法生成有效请求")
        }
        try check(RunAuthorizationRequest.fileURL(from: request)?.path == file.path, "特殊字符路径必须逐字往返")
        try check(RunAuthorizationRequest.url(for: directory) == nil, "目录不能生成请求")
        for value in [
            "jobsrunauthorizer://authorize?path=/tmp&path=/var",
            "jobsrunauthorizer://authorize?path=relative",
            "jobsrunauthorizer://authorize?path=/tmp%00bad",
            "jobsrunauthorizer://authorize?path=/tmp&other=x",
            "jobsrunauthorizer://user@authorize?path=/tmp",
            "jobsrunauthorizer://authorize:123?path=/tmp",
            "jobsrunauthorizer://authorize/?path=/tmp",
            "jobsrunauthorizer://authorize?path=/tmp#fragment",
            "jobsrunauthorizer://other?path=/tmp",
            "https://authorize?path=/tmp"
        ] {
            try check(RunAuthorizationRequest.fileURL(from: URL(string: value)!) == nil, "畸形请求应拒绝")
        }
        let fake = root.appendingPathComponent("fake.zsh")
        let capture = root.appendingPathComponent("captured")
        try Data("[[ $# == 2 && $1 == --file ]] || exit 20\nprintf '%s' \"$2\" > \"$JOBS_NATIVE_CAPTURE\"\nexit ${JOBS_NATIVE_EXIT:-0}\n".utf8).write(to: fake)
        let launcher = RunAuthorizationLauncher()
        for exitCode in [0, 7] {
            let prepared = try launcher.prepare(fileURL: file, businessScriptURL: fake)
            try check(!prepared.commandLine.contains("\n") && !prepared.commandLine.contains("\r"), "Terminal 命令必须物理单行")
            try check(permission(prepared.directoryURL) == 0o700, "私有目录必须 0700")
            try check(permission(prepared.carrierURL) == 0o600 && permission(prepared.businessURL) == 0o600, "私有脚本必须 0600")
            try check(try Data(contentsOf: prepared.businessURL) == Data(contentsOf: fake), "业务资源必须逐字节复制")
            let process = Process.jobsMake {
                $0.byExecutableURL(URL(fileURLWithPath: "/bin/zsh"))
                    .byArguments(["-c", prepared.commandLine])
            }
            var environment = ProcessInfo.processInfo.environment
            environment["JOBS_NATIVE_CAPTURE"] = capture.path
            environment["JOBS_NATIVE_EXIT"] = String(exitCode)
            process.environment = environment
            try process.run()
            process.waitUntilExit()
            try check(process.terminationStatus == exitCode, "业务退出码必须保留")
            try check(try String(contentsOf: capture, encoding: .utf8) == file.path, "路径必须作为独立参数原样传递")
            try check(!manager.fileExists(atPath: prepared.directoryURL.path), "完成后应精确清理本次载体")
        }
        let first = try launcher.prepare(fileURL: file, businessScriptURL: fake)
        let second = try launcher.prepare(fileURL: file, businessScriptURL: fake)
        launcher.cleanup(first)
        launcher.cleanup(first)
        try check(manager.fileExists(atPath: second.businessURL.path), "重复清理不能影响另一次请求")
        launcher.cleanup(second)
        try Data("/bin/kill -TERM \"$PPID\"\nexit 0\n".utf8).write(to: fake)
        let interrupted = try launcher.prepare(fileURL: file, businessScriptURL: fake)
        let process = Process.jobsMake {
            $0.byExecutableURL(URL(fileURLWithPath: "/bin/zsh"))
                .byArguments([interrupted.carrierURL.path])
        }
        try process.run()
        process.waitUntilExit()
        try check(process.terminationStatus == 143, "终止信号应保留标准退出码")
        try check(!manager.fileExists(atPath: interrupted.directoryURL.path), "终止后应清理本次载体")
        try manager.removeItem(at: file)
        do {
            _ = try launcher.prepare(fileURL: file, businessScriptURL: fake)
            throw failure("已删除文件不应通过派发前校验")
        } catch {
            try check((error as NSError).domain != "RunAuthorizationTransportTests", "失效目标应停止")
        }
        print("✔ 单文件资格、请求 URL、私有载体与特殊路径通过（\(assertions) 条断言）。")
    }

    private static func permission(_ url: URL) -> Int {
        return ((try? FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions]) as? NSNumber)?.intValue ?? -1
    }

    private static func failure(_ message: String) -> NSError {
        return NSError.make(domain: "RunAuthorizationTransportTests", message: message)
    }

    private static func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else {
            throw failure(message)
        }
        assertions += 1
    }
}
