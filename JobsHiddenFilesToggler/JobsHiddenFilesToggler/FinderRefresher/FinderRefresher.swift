//
//  FinderRefresher.swift
//  JobsHiddenFilesToggler
//
//  Created by Jobs on 2026年10月23日，星期五.
//

import Foundation
import Darwin

/// 固定系统命令按真实 UID 对应的账户过滤，不模拟快捷键，也不请求辅助功能权限。
struct FinderRefresher {
    func refresh() throws {
        guard getuid() != 0, let account = getpwuid(getuid()), let name = account.pointee.pw_name else {
            throw NSError(domain: "JobsHiddenFilesToggler", code: 20, userInfo: [NSLocalizedDescriptionKey: "无法核实当前登录用户，已停止 Finder 刷新。"])
        }
        let username = String(cString: name)
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["-u", username, "Finder"]
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            let output = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw NSError(
                domain: "JobsHiddenFilesToggler",
                code: 21,
                userInfo: [NSLocalizedDescriptionKey: "当前用户 Finder 刷新命令失败（\(process.terminationStatus)）：\(output)"]
            )
        }
    }
}
