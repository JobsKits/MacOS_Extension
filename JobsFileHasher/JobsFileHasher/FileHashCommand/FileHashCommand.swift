//
//  FileHashCommand.swift
//  JobsFileHasher
//
//  Created by Jobs on 2026年11月6日，星期五.
//

import Foundation

enum FileHashCommand {

    // 终端只读入口：先说明行为，完成摘要后才触碰剪贴板。
    static func run(path: String,
                    copy: (String) throws -> Void = FileHashClipboard.copy) -> Int32 {
        print("━━━━━━━━━━ 文件指纹 Hash（SHA-256）━━━━━━━━━━")
        print("用途：只读计算一个普通文件的 SHA-256，并将纯摘要复制到系统剪贴板。")
        print("影响：不修改文件内容或权限；成功后覆盖系统剪贴板。按 Ctrl+C 可取消。")
        // debugDescription 将文件名中的控制字符转义，避免终端转义序列注入。
        print("文件：\(path.debugDescription)")
        do {
            guard path.hasPrefix("/"),
                  !path.contains("\0") else {
                throw FileHashFailure.message("文件路径必须是无 NUL 字符的绝对路径。")
            }
            let digest = try FileHashService.sha256(URL(fileURLWithPath: path))
            print("\nSHA-256：\n\(digest)")
            try copy(digest)
            print("\n✔ 纯 SHA-256 已复制到系统剪贴板。")
            return 0
        } catch {
            print("\n✖ \(error.localizedDescription)")
            return 1
        }
    }
}
