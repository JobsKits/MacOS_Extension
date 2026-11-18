//
//  EnvironmentUpdateTerminalLauncher.swift
//  JobsEnvironmentUpdater
//
//  Created by Jobs on 2026年11月17日，星期二.
//

import AppKit

enum EnvironmentUpdateTerminalLauncher {

    static func open(bundle: Bundle = .main) throws {
        guard let resources = bundle.resourceURL?.appendingPathComponent("Scripts", isDirectory: true) else {
            throw failure("随包 update 资源缺失，请安装／更新本功能。")
        }
        let carrier = try prepareCarrier(resources: resources)
        let command = "/bin/zsh " + shellQuote(carrier.path)
        let source = terminalScript(command: command)
        guard let script = NSAppleScript.makeEnvironmentUpdateScript(source: source) else {
            removeCarrier(carrier)
            throw failure("无法创建 Terminal 启动请求。")
        }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error {
            removeCarrier(carrier)
            throw failure("Terminal 启动失败：\(error)。请允许本宿主控制 Terminal 后重试。")
        }
    }

    static func terminalScript(command: String) -> String {
        // launch 不发送开窗用的 run／reopen；执行窗口创建后再激活，避免额外空白窗口。
        return "tell application \"Terminal\"\nlaunch\ndo script \(appleScriptQuote(command))\nactivate\nend tell"
    }

    // 私有快照保留原目录关系，安装更新或卸载宿主不会截断已启动的 update。
    static func prepareCarrier(resources: URL,
                               temporaryRoot: URL = FileManager.default.temporaryDirectory) throws -> URL {
        let source = resources.appendingPathComponent("【MacOS】update.command", isDirectory: true)
        let library = resources.appendingPathComponent("_lib", isDirectory: true)
        try validateTree(source)
        try validateTree(library)
        guard FileManager.default.isReadableFile(atPath: source.appendingPathComponent("【MacOS】update.command").path) else {
            throw failure("随包 update 主脚本不可读。")
        }
        let directory = temporaryRoot.appendingPathComponent("JobsEnvironmentUpdate-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let carrier = directory.appendingPathComponent("Launch.command")
        do {
            let scripts = directory.appendingPathComponent("Scripts", isDirectory: true)
            try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            try FileManager.default.copyItem(at: source, to: scripts.appendingPathComponent("【MacOS】update.command", isDirectory: true))
            try FileManager.default.copyItem(at: library, to: scripts.appendingPathComponent("_lib", isDirectory: true))
            let snapshot = scripts.appendingPathComponent("【MacOS】update.command/【MacOS】update.command")
            let cleanup = "/bin/rm -r -- " + shellQuote(directory.path)
            let text = """
            #!/bin/zsh
            setopt NO_NOMATCH
            trap \(shellQuote(cleanup)) EXIT
            trap 'exit 130' INT
            trap 'exit 143' TERM
            trap 'exit 129' HUP
            # Only this child receives UTF-8; the original script uses prompt expansion in Chinese paths.
            /usr/bin/env -u JOBS_MAC_ENV_SOURCE_MODE -u JOBS_MAC_ENV_SKIP_README LC_ALL=en_US.UTF-8 /bin/zsh \(shellQuote(snapshot.path))
            jobs_environment_update_result=$?
            print -r -- "更新进程退出码：$jobs_environment_update_result"
            exit "$jobs_environment_update_result"
            """ + "\n"
            try text.write(to: carrier, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: carrier.path)
            return carrier
        } catch {
            removeCarrier(carrier)
            throw error
        }
    }

    static func shellQuote(_ text: String) -> String {
        return "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func appleScriptQuote(_ text: String) -> String {
        return "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private static func validateTree(_ root: URL) throws {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]
        let values = try root.resourceValues(forKeys: keys)
        guard root.isFileURL,
              values.isDirectory == true,
              values.isSymbolicLink != true,
              let entries = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys), options: []) else {
            throw failure("更新资源目录缺失或含链接：\(root.path)")
        }
        for case let entry as URL in entries {
            let value = try entry.resourceValues(forKeys: keys)
            guard value.isSymbolicLink != true,
                  value.isDirectory == true || value.isRegularFile == true else {
                throw failure("更新资源不是普通文件或目录：\(entry.path)")
            }
        }
    }

    private static func failure(_ text: String) -> NSError {
        return NSError(domain: "JobsEnvironmentUpdate", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
    }

    private static func removeCarrier(_ carrier: URL) {
        try? FileManager.default.removeItem(at: carrier.deletingLastPathComponent())
    }
}
