//
//  GitRollbackTransportTests.swift
//  JobsGitRollbackerTests
//
//  Created by Jobs on 2026年10月26日，星期一.
//

import Foundation

/// 在临时目录验证 URL 与 Terminal 私有载体；不会回退真实仓库或启动 Terminal。
@main
enum GitRollbackTransportTests {
    static func main() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("GitRollbackNativeTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: false)
        defer {
            try? fileManager.removeItem(at: root)
        }
        let folder = root.appendingPathComponent("中文 空格 ' $() `id` \\ \n\t\u{1B}", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: false)
        try runGit(["init", "--quiet", folder.path])
        let file = root.appendingPathComponent("ordinary-file")
        try Data("sample".utf8).write(to: file)
        let link = root.appendingPathComponent("shortcut", isDirectory: true)
        try fileManager.createSymbolicLink(at: link, withDestinationURL: folder)
        let validator = GitRollbackMenuContext()
        try check(validator.isFolder(at: folder), "有效 Git 工作树应被接受")
        try check(!validator.isFolder(at: file), "普通文件不应接受")
        try check(!validator.isFolder(at: link), "目录链接不应作为普通文件夹接受")
        try check(!validator.isFolder(at: root.appendingPathComponent("missing")), "不存在的目录不应接受")

        try check(!validator.isFolder(at: root), "非 Git 目录应被拒绝")
        let child = folder.appendingPathComponent("子目录", isDirectory: true)
        try fileManager.createDirectory(at: child, withIntermediateDirectories: false)
        try check(validator.isFolder(at: child), "工作树内普通子目录应被接受")
        try check(!validator.isFolder(at: folder.appendingPathComponent(".git")), "Git 元数据不能显示菜单")
        let broken = child.appendingPathComponent(".git")
        try Data("gitdir: missing\n".utf8).write(to: broken)
        try check(!validator.isFolder(at: child), "无效内层 Git 不能借外层仓库通过")
        try fileManager.removeItem(at: broken)
        let bundle = folder.appendingPathComponent("Demo.app", isDirectory: true)
        try fileManager.createDirectory(at: bundle, withIntermediateDirectories: false)
        try check(!validator.isFolder(at: bundle), "应用包不能当作普通文件夹接受")
        let bare = root.appendingPathComponent("bare.git", isDirectory: true)
        try runGit(["init", "--quiet", "--bare", bare.path])
        try check(!validator.isFolder(at: bare), "裸仓库不能显示工作树操作")
        let external = root.appendingPathComponent("external.git", isDirectory: true)
        try runGit(["init", "--quiet", "--bare", external.path])
        let linked = root.appendingPathComponent("gitfile", isDirectory: true)
        try fileManager.createDirectory(at: linked, withIntermediateDirectories: false)
        try Data("gitdir: ../external.git\n".utf8).write(to: linked.appendingPathComponent(".git"))
        try check(validator.isFolder(at: linked), "gitfile 相对引用应被接受")
        let perWorktree = external.appendingPathComponent("worktrees/linked", isDirectory: true)
        try fileManager.createDirectory(at: perWorktree, withIntermediateDirectories: true)
        try Data("ref: refs/heads/main\n".utf8).write(to: perWorktree.appendingPathComponent("HEAD"))
        try Data("../..\n".utf8).write(to: perWorktree.appendingPathComponent("commondir"))
        try Data("gitdir: ../external.git/worktrees/linked\n".utf8).write(to: linked.appendingPathComponent(".git"))
        try check(validator.isFolder(at: linked), "linked worktree 应解析 commondir")
        try Data("../missing\n".utf8).write(to: perWorktree.appendingPathComponent("commondir"))
        try check(!validator.isFolder(at: linked), "失效 commondir 应拒绝")

        guard let requestURL = GitRollbackRequest.url(for: folder) else {
            throw failure("无法编码请求 URL")
        }
        try check(GitRollbackRequest.projectURL(from: requestURL)?.path == folder.path, "特殊路径必须精确往返")
        for value in [
            "jobsgitrollback://rollback?path=/tmp&path=/var",
            "jobsgitrollback://rollback?path=relative",
            "jobsgitrollback://rollback?path=/tmp%00bad",
            "jobsgitrollback://manage?path=/tmp",
            "jobsgitrollback://rollback/extra?path=/tmp",
            "jobsgitrollback://rollback?path=/tmp#extra",
            "https://rollback?path=/tmp"
        ] {
            try check(GitRollbackRequest.projectURL(from: URL(string: value)!) == nil, "畸形请求未拒绝：\(value)")
        }

        let fakeScript = root.appendingPathComponent("fake.zsh")
        let capture = root.appendingPathComponent("captured")
        try Data("[[ $# == 1 ]] || exit 2\nprintf '%s' \"$1\" > \"$JOBS_NATIVE_CAPTURE\"\nexit ${JOBS_NATIVE_EXIT:-0}\n".utf8).write(to: fakeScript)
        let launcher = GitRollbackTerminalLauncher()
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

        try Data("printf '%s' \"$1\" > \"$JOBS_NATIVE_CAPTURE\"\n".utf8).write(to: fakeScript)
        let bound = root.appendingPathComponent("bound", isDirectory: true)
        let sibling = root.appendingPathComponent("sibling", isDirectory: true)
        try runGit(["init", "--quiet", bound.path])
        try fileManager.createDirectory(at: sibling, withIntermediateDirectories: false)
        let validChild = bound.appendingPathComponent("ordinary-child", isDirectory: true)
        try fileManager.createDirectory(at: validChild, withIntermediateDirectories: false)
        let childRequest = try launcher.prepare(projectURL: validChild, businessScriptURL: fakeScript)
        launcher.cleanup(childRequest)
        let nested = bound.appendingPathComponent("nested", isDirectory: true)
        try runGit(["init", "--quiet", nested.path])
        let nestedRequest = try launcher.prepare(projectURL: nested, businessScriptURL: fakeScript)
        launcher.cleanup(nestedRequest)
        try check(validator.identity(at: nested)?.rootURL.path == nested.standardizedFileURL.resolvingSymlinksInPath().path, "嵌套 Git 必须使用最近根目录")

        try runGit(["-C", bound.path, "config", "core.worktree", sibling.path])
        var rejectedBinding = false
        do {
            let unexpected = try launcher.prepare(projectURL: validChild, businessScriptURL: fakeScript)
            launcher.cleanup(unexpected)
        } catch {
            rejectedBinding = true
        }
        try check(rejectedBinding, "core.worktree 指向兄弟目录必须在 prepare 拒绝")
        try runGit(["config", "--file", bound.appendingPathComponent(".git/config").path, "--unset-all", "core.worktree"])

        let delayed = try launcher.prepare(projectURL: validChild, businessScriptURL: fakeScript)
        try runGit(["-C", bound.path, "config", "core.worktree", sibling.path])
        let identityCapture = root.appendingPathComponent("identity-capture")
        let delayedProcess = Process()
        delayedProcess.executableURL = URL(fileURLWithPath: "/bin/zsh")
        delayedProcess.arguments = [delayed.carrierURL.path]
        var delayedEnvironment = ProcessInfo.processInfo.environment
        delayedEnvironment["JOBS_NATIVE_CAPTURE"] = identityCapture.path
        delayedProcess.environment = delayedEnvironment
        try delayedProcess.run()
        delayedProcess.waitUntilExit()
        try check(delayedProcess.terminationStatus == 65, "派发后 core.worktree 改绑必须在 carrier 拒绝")
        try check(!fileManager.fileExists(atPath: identityCapture.path), "身份变化时不得运行任何业务")
        try check(!fileManager.fileExists(atPath: delayed.directoryURL.path), "身份拒绝后必须清理私有载体")
        try runGit(["config", "--file", bound.appendingPathComponent(".git/config").path, "--unset-all", "core.worktree"])

        let cleanRequest = try launcher.prepare(projectURL: validChild, businessScriptURL: fakeScript)
        let cleanProcess = Process()
        cleanProcess.executableURL = URL(fileURLWithPath: "/bin/zsh")
        cleanProcess.arguments = [cleanRequest.carrierURL.path]
        delayedEnvironment["GIT_DIR"] = folder.appendingPathComponent(".git").path
        delayedEnvironment["GIT_WORK_TREE"] = folder.path
        delayedEnvironment["GIT_CONFIG_COUNT"] = "1"
        delayedEnvironment["GIT_CONFIG_KEY_0"] = "core.worktree"
        delayedEnvironment["GIT_CONFIG_VALUE_0"] = sibling.path
        cleanProcess.environment = delayedEnvironment
        try cleanProcess.run()
        cleanProcess.waitUntilExit()
        try check(cleanProcess.terminationStatus == 0, "继承的 Git 定位与临时配置必须在子进程隔离")
        try check(try String(contentsOf: identityCapture, encoding: .utf8) == validChild.path, "有效子目录仍精确传给业务")

        try runGit(["-C", bound.path, "-c", "user.name=Jobs Test", "-c", "user.email=jobs-test@example.invalid", "commit", "--quiet", "--allow-empty", "-m", "fixture"])
        let realWorktree = root.appendingPathComponent("real-worktree", isDirectory: true)
        try runGit(["-C", bound.path, "worktree", "add", "--quiet", "-b", "fixture-worktree", realWorktree.path])
        let worktreeRequest = try launcher.prepare(projectURL: realWorktree, businessScriptURL: fakeScript)
        launcher.cleanup(worktreeRequest)
        print("✔ Git 提交回退 URL、工作树身份、私有载体、特殊路径与退出清理验证通过。")
    }

    private static func runGit(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        try check(process.terminationStatus == 0, "临时 Git 夹具创建失败")
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
        NSError(domain: "GitRollbackTransportTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
