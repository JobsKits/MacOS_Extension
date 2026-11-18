//
//  DiskCleanupTerminalLauncher.swift
//  JobsDiskSpaceInfo
//
//  Created by Jobs on 2026年11月15日，星期日.
//

import AppKit

enum DiskCleanupTerminalLauncher {

    static func open(bundle: Bundle = .main) throws {
        guard let resource = bundle.resourceURL?.appendingPathComponent("【MacOS】清理磁盘空间.command", isDirectory: true)
            .appendingPathComponent("【MacOS】清理磁盘空间.command") else {
            throw failure("清理脚本缺失，请安装／更新本功能。")
        }
        let carrier = try prepareCarrier(script: resource)
        let command = "/bin/zsh " + shellQuote(carrier.path)
        let source = terminalScript(command: command)
        guard let script = NSAppleScript.makeDiskCleanupScript(source: source) else {
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

    // 将随包业务复制到本次私有载体，App 更新／卸载不会截断已经打开的清理终端。
    static func prepareCarrier(script: URL,
                               temporaryRoot: URL = FileManager.default.temporaryDirectory) throws -> URL {
        let values = try script.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard script.isFileURL,
              values.isRegularFile == true,
              values.isSymbolicLink != true else {
            throw failure("清理资源不是普通文件。")
        }
        let directory = temporaryRoot.appendingPathComponent("JobsDiskSpaceCleanup-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let carrier = directory.appendingPathComponent("Launch.command")
        let snapshot = directory.appendingPathComponent("Cleanup.command")
        do {
            try FileManager.default.copyItem(at: script, to: snapshot)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: snapshot.path)
            let cleanup = "/bin/rm -f -- \(shellQuote(snapshot.path)) \(shellQuote(carrier.path)); /bin/rmdir -- \(shellQuote(directory.path))"
            let text = """
            #!/bin/zsh
            setopt NO_NOMATCH
            trap \(shellQuote(cleanup)) EXIT
            trap 'exit 130' INT
            trap 'exit 143' TERM
            trap 'exit 129' HUP
            /bin/zsh \(shellQuote(snapshot.path))
            jobs_disk_cleanup_result=$?
            print -r -- "清理进程退出码：$jobs_disk_cleanup_result"
            exit "$jobs_disk_cleanup_result"
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

    private static func appleScriptQuote(_ text: String) -> String {
        return "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private static func failure(_ text: String) -> NSError {
        return NSError(domain: "JobsDiskSpaceCleanup", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
    }

    private static func removeCarrier(_ carrier: URL) {
        try? FileManager.default.removeItem(at: carrier.deletingLastPathComponent())
    }
}
