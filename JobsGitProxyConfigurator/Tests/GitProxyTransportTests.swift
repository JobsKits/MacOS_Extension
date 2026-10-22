//
//  GitProxyTransportTests.swift
//  JobsGitProxyConfiguratorTests
//
//  Created by Jobs on 2026年10月20日，星期二.
//

import Foundation
import Darwin

/// 只运行临时假业务脚本，不启动 Terminal、注册扩展或创建真实Git配置。
@main
enum GitProxyTransportTests {
    private static var assertionCount = 0

    static func main() throws {
        try testRequests()
        try testExtensionStatus()
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("GitProxyNativeTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: false)
        defer {
            try? fileManager.removeItem(at: root)
        }
        try testMenuContexts(root: root)
        try testPrivateTransport(root: root)
        print("✔ Git 动态代理固定 URL、仅桌面空白菜单、Shell 转义与私有载体回归通过（\(assertionCount) 条断言）。")
    }

    private static func testRequests() throws {
        try check(GitProxyRequest.isConfigureRequest(GitProxyRequest.canonicalURL), "固定动作请求应接受")
        let invalidRequests = [
            "jobsgitproxyconfigurator://git/configure?path=/tmp",
            "jobsgitproxyconfigurator://git/configure?",
            "jobsgitproxyconfigurator://git/configure#",
            "jobsgitproxyconfigurator://git/configure#fragment",
            "jobsgitproxyconfigurator://user@git/configure",
            "jobsgitproxyconfigurator://user:password@git/configure",
            "jobsgitproxyconfigurator://git:123/configure",
            "jobsgitproxyconfigurator://git/configure/",
            "jobsgitproxyconfigurator://git/other",
            "jobsgitproxyconfigurator://git/%63onfigure",
            "jobsgitproxyconfigurator://git/configure%00",
            "jobsgitproxyconfigurator://git/configure%0A",
            "jobsgitproxyconfigurator://git/configure%252Fextra",
            "jobsgitproxyconfigurator://git/configure/../configure",
            "jobsgitproxyconfigurator:///configure",
            "jobsgitproxyconfigurator://other/configure",
            "https://git/configure"
        ]
        for value in invalidRequests {
            guard let url = URL(string: value) else {
                continue
            }
            try check(!GitProxyRequest.isConfigureRequest(url), "无效请求应拒绝：\(value)")
        }
    }

    private static func testExtensionStatus() throws {
        let identifier = "com.jobs.gitproxyconfigurator.findersync"
        let current = URL(fileURLWithPath: "/Applications/JobsGitProxyConfigurator.app/Contents/PlugIns/JobsGitProxyFinderSync.appex")
        let enabled = "+    \(identifier)(1.0)\n\t            Path = \(current.path)\n\t            UUID = fixture\n"
        try check(GitProxyModel.isCurrentExtensionEnabled(in: enabled, identifier: identifier, extensionURL: current), "本次路径的 + 条目应判定启用")
        let oldEnabled = "+    \(identifier)(1.0)\n\t            Path = /old/JobsGitProxyFinderSync.appex\n\n"
        let currentDisabled = "     \(identifier)(1.0)\n\t            Path = \(current.path)\n"
        try check(!GitProxyModel.isCurrentExtensionEnabled(in: oldEnabled + currentDisabled, identifier: identifier, extensionURL: current), "旧路径启用不能冒充当前路径成功")
        try check(!GitProxyModel.isCurrentExtensionEnabled(in: currentDisabled + oldEnabled, identifier: identifier, extensionURL: current), "状态不能跨注册条目继承")
        try check(!GitProxyModel.isCurrentExtensionEnabled(in: enabled.replacingOccurrences(of: current.path, with: current.path + "-old"), identifier: identifier, extensionURL: current), "扩展路径必须精确匹配")
        try check(!GitProxyModel.isCurrentExtensionEnabled(in: enabled.replacingOccurrences(of: identifier, with: identifier + ".other"), identifier: identifier, extensionURL: current), "Bundle ID 必须精确匹配")
        try check(!GitProxyModel.isCurrentExtensionEnabled(in: "+    \(identifier)(1.0)\n", identifier: identifier, extensionURL: current), "缺少 Path 不得报告成功")
        try check(!GitProxyModel.isCurrentExtensionEnabled(in: "  (no matches)\n", identifier: identifier, extensionURL: current), "未匹配状态不得报告成功")
    }

    private static func testMenuContexts(root: URL) throws {
        let fileManager = FileManager.default
        let desktop = root.appendingPathComponent("Desktop", isDirectory: true)
        let ordinaryDirectory = root.appendingPathComponent("非 iOS 项目", isDirectory: true)
        let desktopChild = desktop.appendingPathComponent("项目", isDirectory: true)
        let sameNameDirectory = ordinaryDirectory.appendingPathComponent("Desktop", isDirectory: true)
        let package = root.appendingPathComponent("Example.app", isDirectory: true)
        let file = root.appendingPathComponent("source.swift")
        let link = root.appendingPathComponent("directory-link", isDirectory: true)
        for directory in [desktop, ordinaryDirectory, package] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: false)
        }
        for directory in [desktopChild, sameNameDirectory] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: false)
        }
        try Data("// file".utf8).write(to: file)
        try fileManager.createSymbolicLink(at: link, withDestinationURL: ordinaryDirectory)
        if let home = getpwuid(getuid())?.pointee.pw_dir {
            let actualDesktop = URL(fileURLWithPath: String(cString: home), isDirectory: true)
                .appendingPathComponent("Desktop", isDirectory: true)
            try check(GitProxyMenuContext.desktopURLs.contains(actualDesktop), "桌面白名单必须包含目录服务取得的真实 Home/Desktop")
            try check(GitProxyMenuContext.desktopURL == actualDesktop, "默认桌面回退应优先真实用户目录")
        }
        try check(GitProxyMenuContext.candidateURL(isContainer: true, targetedURL: URL(string: "https://example.com")!, selectedURLs: nil, desktopURL: desktop) == nil, "非本地 URL 应拒绝")
        try check(GitProxyMenuContext.candidateURL(isContainer: true, targetedURL: package, selectedURLs: nil, desktopURL: desktop) == nil, "未命中桌面白名单的包应拒绝")
        try check(GitProxyMenuContext.candidateURL(isContainer: true, targetedURL: link, selectedURLs: nil, desktopURL: desktop) == nil, "普通文件夹链接不应误认桌面")
        try check(GitProxyMenuContext.candidateURL(isContainer: true, targetedURL: nil, selectedURLs: nil, desktopURL: desktop) == desktop, "桌面空白菜单应回退已知桌面")
        try check(GitProxyMenuContext.candidateURL(isContainer: true, targetedURL: desktop, selectedURLs: nil, desktopURL: desktop) == desktop, "真实桌面容器应显示入口")
        try check(GitProxyMenuContext.candidateURL(isContainer: true, targetedURL: desktop, selectedURLs: [file], desktopURL: desktop) == nil, "显式选中项目不能作为桌面空白请求")
        try check(GitProxyMenuContext.candidateURL(isContainer: true, targetedURL: ordinaryDirectory, selectedURLs: [file], desktopURL: desktop) == nil, "普通文件夹空白处不提供Git配置入口")
        try check(GitProxyMenuContext.candidateURL(isContainer: true, targetedURL: desktopChild, selectedURLs: nil, desktopURL: desktop) == nil, "桌面子文件夹不属于桌面空白")
        try check(GitProxyMenuContext.candidateURL(isContainer: true, targetedURL: sameNameDirectory, selectedURLs: nil, desktopURL: desktop) == nil, "同名 Desktop 普通目录不应误认系统桌面")
        try check(GitProxyMenuContext.candidateURL(isContainer: true, targetedURL: file, selectedURLs: nil, desktopURL: desktop) == nil, "明确的无效 targetedURL 不能误回退桌面")
        try check(GitProxyMenuContext.candidateURL(isContainer: true, targetedURL: nil, selectedURLs: nil, desktopURL: nil) == nil, "系统桌面也无法解析时停止")
        try check(GitProxyMenuContext.candidateURL(isContainer: false, targetedURL: desktop, selectedURLs: [ordinaryDirectory], desktopURL: desktop) == nil, "桌面选中文件夹不显示Git配置入口")
        try check(GitProxyMenuContext.candidateURL(isContainer: false, targetedURL: ordinaryDirectory, selectedURLs: [desktop], desktopURL: desktop) == nil, "选中桌面目录本身也不显示Git配置入口")
        try check(GitProxyMenuContext.candidateURL(isContainer: false, targetedURL: desktop, selectedURLs: [file]) == nil, "选中文件不能误用父目录")
        try check(GitProxyMenuContext.candidateURL(isContainer: false, targetedURL: desktop, selectedURLs: []) == nil, "空选择应拒绝")
        try check(GitProxyMenuContext.candidateURL(isContainer: false, targetedURL: desktop, selectedURLs: [ordinaryDirectory, desktop]) == nil, "多选不提供重复的全局动作")
        let desktopAlias = root.appendingPathComponent("桌面别名", isDirectory: true)
        try fileManager.createSymbolicLink(at: desktopAlias, withDestinationURL: desktop)
        try check(GitProxyMenuContext.candidateURL(isContainer: true, targetedURL: desktopAlias, selectedURLs: nil, desktopURL: desktop)?.path == desktop.resolvingSymlinksInPath().path, "可解析桌面链接应提供兼容")
        try fileManager.removeItem(at: desktop)
        try check(GitProxyMenuContext.candidateURL(isContainer: true, targetedURL: desktop, selectedURLs: nil, desktopURL: desktop) == desktop, "固定桌面路径策略不能依赖目录元数据读取成功")
        try check(GitProxyMenuContext.candidateURL(isContainer: true, targetedURL: nil, selectedURLs: nil, desktopURL: desktop) == desktop, "已知桌面回退不能依赖文件存在检查")
    }

    private static func testPrivateTransport(root: URL) throws {
        let fileManager = FileManager.default
        let launcher = GitProxyTerminalLauncher()
        let temporaryParent = root.appendingPathComponent("中文 空格 ' $() `id` \\ \n\t\u{1B}\u{2028}", isDirectory: true)
        try fileManager.createDirectory(at: temporaryParent, withIntermediateDirectories: false)
        let fakeScript = root.appendingPathComponent("fake.zsh")
        let captured = root.appendingPathComponent("captured")
        try Data("[[ $# == 0 ]] || exit 20\nprintf '%s' 'copied-script' > \"$JOBS_NATIVE_CAPTURE\"\nexit ${JOBS_NATIVE_EXIT:-0}\n".utf8).write(to: fakeScript)
        for exitCode in [0, 7] {
            let request = try launcher.prepare(businessScriptURL: fakeScript, temporaryDirectory: temporaryParent)
            try check(!request.commandLine.contains("\n") && !request.commandLine.contains("\r") && !request.commandLine.contains("\u{2028}"), "Terminal 命令必须为物理单行")
            try check(permission(request.directoryURL) == 0o700, "私有目录权限应为 0700")
            try check(permission(request.carrierURL) == 0o600 && permission(request.businessURL) == 0o600, "载体和业务副本权限应为 0600")
            try check(try Data(contentsOf: request.businessURL) == Data(contentsOf: fakeScript), "业务资源应逐字节复制")
            let result = try runShell(
                command: request.commandLine,
                environment: ["JOBS_NATIVE_CAPTURE": captured.path, "JOBS_NATIVE_EXIT": String(exitCode)]
            )
            try check(result.exitCode == exitCode, "业务脚本退出码应保留：预期 \(exitCode)，实际 \(result.exitCode)，输出 \(result.output)")
            try check(try String(contentsOf: captured, encoding: .utf8) == "copied-script", "带特殊字符的载体路径应精确执行")
            try check(!fileManager.fileExists(atPath: request.directoryURL.path), "业务结束后应清理本次私有目录")
        }
        let first = try launcher.prepare(businessScriptURL: fakeScript, temporaryDirectory: temporaryParent)
        let second = try launcher.prepare(businessScriptURL: fakeScript, temporaryDirectory: temporaryParent)
        try check(first.directoryURL != second.directoryURL, "并发请求应有独立目录")
        launcher.cleanup(first)
        launcher.cleanup(first)
        try check(fileManager.fileExists(atPath: second.carrierURL.path), "重复清理不得影响其它请求")
        launcher.cleanup(second)
        try Data("/bin/kill -TERM \"$PPID\"\nexit 0\n".utf8).write(to: fakeScript)
        let interrupted = try launcher.prepare(businessScriptURL: fakeScript, temporaryDirectory: temporaryParent)
        let interruptedResult = try runShell(command: interrupted.commandLine)
        try check(interruptedResult.exitCode == 143, "终止信号应返回标准退出码")
        try check(!fileManager.fileExists(atPath: interrupted.directoryURL.path), "终止后应清理私有目录")
        let quotedText = "' $() `id` \\ \n\r\t\u{1B}\u{85}\u{2028}\u{2029} 中文"
        let quotedResult = try runShell(command: "printf '%s' \(launcher.shellWord(quotedText))")
        try check(quotedResult.output == quotedText, "Shell 单词转义应逐字节往返")
        try Data().write(to: fakeScript)
        var emptyResourceRejected = false
        do {
            _ = try launcher.prepare(businessScriptURL: fakeScript, temporaryDirectory: temporaryParent)
        } catch {
            emptyResourceRejected = true
        }
        try check(emptyResourceRejected, "空业务资源必须拒绝")
        try check(try fileManager.contentsOfDirectory(atPath: temporaryParent.path).isEmpty, "拒绝或清理后不得遗留私有载体")
    }

    private static func runShell(command: String, environment additions: [String: String] = [:]) throws -> (exitCode: Int32, output: String) {
        let process = Process()
        let output = Pipe()
        var environment = ProcessInfo.processInfo.environment
        environment.merge(additions) { _, newValue in
            return newValue
        }
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-f", "-c", command]
        process.environment = environment
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    private static func permission(_ url: URL) -> Int {
        return ((try? FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions]) as? NSNumber)?.intValue ?? -1
    }

    private static func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        assertionCount += 1
        guard try condition() else {
            throw NSError(domain: "GitProxyTransportTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
}
