//
//  FileHashTerminalLauncher.swift
//  JobsFileHasher
//
//  Created by Jobs on 2026年11月6日，星期五.
//

import AppKit

enum FileHashTerminalLauncher {

    static func open(_ file: URL) throws {
        guard FileHashTarget.regularFile(file) != nil,
              let executable = Bundle.main.executableURL,
              FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw FileHashFailure.message("所选文件或宿主程序不可用，请重新选择或安装本功能。")
        }
        let carrier = try prepareCarrier(executable: executable, file: file)
        let command = "/bin/zsh " + shellQuote(carrier.path)
        let source = "tell application \"Terminal\"\nactivate\ndo script \(appleScriptQuote(command))\nend tell"
        guard let script = NSAppleScript.make(source: source) else {
            removeCarrier(carrier)
            throw FileHashFailure.message("无法创建 Terminal 启动请求。")
        }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error {
            removeCarrier(carrier)
            throw FileHashFailure.message("无法打开新终端：\(error)。请允许本工具控制 Terminal 后重试。")
        }
    }

    // Terminal 只接收一行启动命令；目标路径保存在每次独占的私有脚本中。
    static func prepareCarrier(executable: URL,
                               file: URL,
                               temporaryRoot: URL = FileManager.default.temporaryDirectory) throws -> URL {
        let directory = temporaryRoot.appendingPathComponent("JobsFileHash-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory,
                                                withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        let carrier = directory.appendingPathComponent("Hash.command")
        let cleanup = "/bin/rm -f -- \(shellQuote(carrier.path)); /bin/rmdir -- \(shellQuote(directory.path))"
        let text = """
        #!/bin/zsh
        # 私有终端载体：只读计算单文件指纹，由退出陷阱清理本次载体。
        setopt NO_NOMATCH
        trap \(shellQuote(cleanup)) EXIT
        trap 'exit 130' INT
        trap 'exit 143' TERM
        trap 'exit 129' HUP
        \(shellQuote(executable.path)) --hash-file \(shellQuote(file.path))
        jobs_hash_result=$?
        exit "$jobs_hash_result"
        """ + "\n"
        do {
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
        return "\"" + text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private static func removeCarrier(_ carrier: URL) {
        try? FileManager.default.removeItem(at: carrier)
        try? FileManager.default.removeItem(at: carrier.deletingLastPathComponent())
    }
}
