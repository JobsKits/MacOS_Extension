//
//  FlutterProjectBehaviorTests.swift
//  JobsFlutterVersionMgrTests
//
//  Created by Jobs on 2026年10月19日，星期一.
//

import Foundation

/// 使用临时目录和假业务脚本；从不启动 Terminal、安装工具或注册扩展。
@main
enum FlutterProjectBehaviorTests {
    static func main() throws {
        let validator = FlutterProjectValidator()
        let accepted = [
            "name: app\ndependencies:\n  flutter:\n    sdk: flutter\n",
            "description: |\n  sdk: flutter\ndependencies:\n    cupertino_icons: any\n    flutter:\n      sdk: flutter # SDK\n",
            "dependencies:\n  flutter: {sdk: flutter}\n",
            "dependencies: {flutter: {sdk: flutter}, collection: any}\n",
            "'dependencies':\n  \"flutter\": { 'sdk': 'flutter' }\n"
        ]
        let rejected = [
            "# dependencies:\n#   flutter:\n#     sdk: flutter\n",
            "description: |\n  dependencies:\n    flutter:\n      sdk: flutter\n",
            "dev_dependencies:\n  flutter_test:\n    sdk: flutter\n",
            "dependencies:\n  flutter_test:\n    sdk: flutter\n",
            "dependencies:\n  flutter: flutter\n",
            "dependencies:\n  other:\n    flutter:\n      sdk: flutter\n",
            "dependencies:\n  flutter:\n    nested:\n      sdk: flutter\n",
            "dependencies:\n  flutter:\n    sdk: dart\n",
            "dependencies: {flutter: {sdk: flutter}, flutter: {sdk: dart}}\n",
            "dependencies:\n  flutter:\n    sdk: flutter\ndependencies: {}\n",
            "dependencies:\n  flutter:\n    sdk: flutter\n    sdk: dart\n"
        ]
        for text in accepted {
            try check(validator.declaresFlutterSDK(in: text), "合法声明被拒绝：\(text)")
        }
        for text in rejected {
            try check(!validator.declaresFlutterSDK(in: text), "无效声明被误认：\(text)")
        }

        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("FlutterNativeTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: false)
        defer {
            try? fileManager.removeItem(at: root)
        }
        let project = root.appendingPathComponent("中文 空格 ' $() `id` \\ \n\t\u{1B}", isDirectory: true)
        try fileManager.createDirectory(at: project, withIntermediateDirectories: false)
        try Data(accepted[0].utf8).write(to: project.appendingPathComponent("pubspec.yaml"))
        try check(validator.isFlutterProject(at: project), "真实 Flutter 项目未识别")
        let link = root.appendingPathComponent("shortcut", isDirectory: true)
        try fileManager.createSymbolicLink(at: link, withDestinationURL: project)
        try check(!validator.isFlutterProject(at: link), "符号链接不应作为普通项目")
        try check(!validator.isFlutterProject(at: project.appendingPathComponent("pubspec.yaml")), "普通文件不应识别")
        try check(!validator.isFlutterProject(at: root), "不得递归查找子项目")

        let requestURL = try FlutterManagerRequest.url(for: project).unwrap("无法生成请求 URL")
        try check(FlutterManagerRequest.projectURL(from: requestURL)?.path == project.path, "特殊字符路径未精确往返")
        for text in ["jobsflutterversionmgr://manage?path=/tmp&path=/var", "jobsflutterversionmgr://manage?path=relative", "jobsflutterversionmgr://manage?path=/tmp%00bad", "jobsflutterversionmgr://other?path=/tmp", "https://manage?path=/tmp"] {
            try check(FlutterManagerRequest.projectURL(from: URL(string: text)!) == nil, "畸形请求未拒绝：\(text)")
        }

        let fakeScript = root.appendingPathComponent("fake.zsh")
        let captured = root.appendingPathComponent("captured")
        try Data("[[ \"$1\" == --project ]] || exit 2\nprintf '%s' \"$2\" > \"$JOBS_NATIVE_CAPTURE\"\nexit ${JOBS_NATIVE_EXIT:-0}\n".utf8).write(to: fakeScript)
        let launcher = FlutterTerminalLauncher()
        for exitCode in [0, 7] {
            let prepared = try launcher.prepare(projectURL: project, businessScriptURL: fakeScript)
            try check(!prepared.commandLine.contains("\n") && !prepared.commandLine.contains("\r"), "Terminal 命令必须保持物理单行")
            try check(permission(prepared.directoryURL) == 0o700, "私有目录权限错误")
            try check(permission(prepared.carrierURL) == 0o600 && permission(prepared.businessURL) == 0o600, "私有文件权限错误")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = [prepared.carrierURL.path]
            var environment = ProcessInfo.processInfo.environment
            environment["JOBS_NATIVE_CAPTURE"] = captured.path
            environment["JOBS_NATIVE_EXIT"] = String(exitCode)
            process.environment = environment
            try process.run()
            process.waitUntilExit()
            try check(process.terminationStatus == exitCode, "业务退出码未保留")
            try check(try String(contentsOf: captured, encoding: .utf8) == project.path, "载体没有精确传递项目路径")
            try check(!fileManager.fileExists(atPath: prepared.directoryURL.path), "退出后未清理私有目录")
        }
        let first = try launcher.prepare(projectURL: project, businessScriptURL: fakeScript)
        let second = try launcher.prepare(projectURL: project, businessScriptURL: fakeScript)
        launcher.cleanup(first)
        launcher.cleanup(first)
        try check(fileManager.fileExists(atPath: second.carrierURL.path), "清理影响了其它请求")
        launcher.cleanup(second)
        try Data("/bin/kill -TERM \"$PPID\"\nexit 0\n".utf8).write(to: fakeScript)
        let interrupted = try launcher.prepare(projectURL: project, businessScriptURL: fakeScript)
        let interruptedProcess = Process()
        interruptedProcess.executableURL = URL(fileURLWithPath: "/bin/zsh")
        interruptedProcess.arguments = [interrupted.carrierURL.path]
        try interruptedProcess.run()
        interruptedProcess.waitUntilExit()
        try check(interruptedProcess.terminationStatus == 143, "终止信号未保留标准退出码")
        try check(!fileManager.fileExists(atPath: interrupted.directoryURL.path), "终止信号后未清理私有目录")
        print("✔ 共享 Flutter 判定、URL 路径往返、私有载体权限与精确清理回归通过。")
    }

    private static func permission(_ url: URL) -> Int {
        ((try? FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions]) as? NSNumber)?.intValue ?? -1
    }

    private static func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else {
            throw NSError(domain: "FlutterProjectBehaviorTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
}

private extension Optional {
    func unwrap(_ message: String) throws -> Wrapped {
        guard let value = self else {
            throw NSError(domain: "FlutterProjectBehaviorTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
        return value
    }
}
