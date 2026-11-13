//
//  FileHashClipboard.swift
//  JobsFileHasher
//
//  Created by Jobs on 2026年11月6日，星期五.
//

import Foundation

enum FileHashClipboard {

    // 只在全部读取成功后向系统 pbcopy 发送纯摘要，不附加路径和换行。
    static func copy(_ digest: String) throws {
        let input = Pipe.make()
        let process = Process.make(executableURL: URL(fileURLWithPath: "/usr/bin/pbcopy"),
                                   standardInput: input)
        try process.run()
        try input.fileHandleForWriting.write(contentsOf: Data(digest.utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw FileHashFailure.message("系统剪贴板写入失败，退出码 \(process.terminationStatus)；可手动复制终端中的摘要。")
        }
    }
}
