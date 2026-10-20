//
//  GitPullTransportTests.swift
//  JobsGitPullerTests
//
//  Created by Jobs on 2026年10月19日，星期一.
//

import Foundation

/// 在临时目录验证 URL 与 Terminal 私有载体；不会拉取真实仓库或启动 Terminal。
@main
enum GitPullTransportTests {
    static func main() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("GitPullNativeTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: false)
        defer {
            try? fileManager.removeItem(at: root)
        }
        let folder = root.appendingPathComponent("中文 空格 ' $() `id` \\ \n\t\u{1B}", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: false)
        let file = root.appendingPathComponent("ordinary-file")
        try Data("sample".utf8).write(to: file)
        let link = root.appendingPathComponent("shortcut", isDirectory: true)
        try fileManager.createSymbolicLink(at: link, withDestinationURL: folder)
        let validator = GitFolderValidator()
        try check(validator.isFolder(at: folder), "普通文件夹应交给脚本进一步判定 Git")
        try check(!validator.isFolder(at: file), "普通文件不应接受")
        try check(!validator.isFolder(at: link), "目录链接不应作为普通文件夹接受")
        try check(!validator.isFolder(at: root.appendingPathComponent("missing")), "不存在的目录不应接受")

        guard let requestURL = GitPullRequest.url(for: folder) else {
            throw failure("无法编码请求 URL")
        }
        try check(GitPullRequest.projectURL(from: requestURL)?.path == folder.path, "特殊路径必须精确往返")
        for value in [
            "jobsgitpuller://pull?path=/tmp&path=/var",
            "jobsgitpuller://pull?path=relative",
            "jobsgitpuller://pull?path=/tmp%00bad",
            "jobsgitpuller://manage?path=/tmp",
            "jobsgitpuller://pull/extra?path=/tmp",
            "jobsgitpuller://pull?path=/tmp#extra",
            "https://pull?path=/tmp"
        ] {
            try check(GitPullRequest.projectURL(from: URL(string: value)!) == nil, "畸形请求未拒绝：\(value)")
        }

        let fakeScript = root.appendingPathComponent("fake.zsh")
        let capture = root.appendingPathComponent("captured")
        try Data("[[ $# == 1 ]] || exit 2\nprintf '%s' \"$1\" > \"$JOBS_NATIVE_CAPTURE\"\nexit ${JOBS_NATIVE_EXIT:-0}\n".utf8).write(to: fakeScript)
        let launcher = GitPullTerminalLauncher()
        for exitCode in [0, 7] {
            let request = try launcher.prepare(projectURL: folder, businessScriptURL: fakeScript)
            try check(!request.commandLine.contains("\n") && !request.commandLine.contains("\r"), "Terminal 命令必须保持单行")
            try check(permission(request.directoryURL) == 0o700, "目录权限必须为 0700")
            try check(permission(request.carrierURL) == 0o600 && permission(request.businessURL) == 0o600, "文件权限必须为 0600")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = [request.carrierURL.path]
            var environment = ProcessInfo.processInfo.environment
            environment["JOBS_NATIVE_CAPTURE"] = capture.path
            environment["JOBS_NATIVE_EXIT"] = String(exitCode)
            process.environment = environment
            try process.run()
            process.waitUntilExit()
            try check(process.terminationStatus == exitCode, "业务退出码未保留")
            try check(try String(contentsOf: capture, encoding: .utf8) == folder.path, "私有载体未精确传递路径")
            try check(!fileManager.fileExists(atPath: request.directoryURL.path), "载体执行后未清理")
        }
        let first = try launcher.prepare(projectURL: folder, businessScriptURL: fakeScript)
        let second = try launcher.prepare(projectURL: folder, businessScriptURL: fakeScript)
        launcher.cleanup(first)
        launcher.cleanup(first)
        try check(fileManager.fileExists(atPath: second.businessURL.path), "精确清理不得影响另一请求")
        launcher.cleanup(second)

        try Data("/bin/kill -TERM \"$PPID\"\nexit 0\n".utf8).write(to: fakeScript)
        let interrupted = try launcher.prepare(projectURL: folder, businessScriptURL: fakeScript)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [interrupted.carrierURL.path]
        try process.run()
        process.waitUntilExit()
        try check(process.terminationStatus == 143, "TERM 标准退出码未保留")
        try check(!fileManager.fileExists(atPath: interrupted.directoryURL.path), "TERM 后未精确清理")
        print("✔ Git 拉取 URL、普通目录、私有载体、特殊路径与退出清理验证通过。")
    }

    private static func permission(_ url: URL) -> Int {
        ((try? FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions]) as? NSNumber)?.intValue ?? -1
    }

    private static func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else {
            throw failure(message)
        }
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "GitPullTransportTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
