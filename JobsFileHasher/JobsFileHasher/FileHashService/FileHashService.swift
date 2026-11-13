//
//  FileHashService.swift
//  JobsFileHasher
//
//  Created by Jobs on 2026年11月6日，星期五.
//

import Foundation
import CryptoKit
import Darwin

enum FileHashService {

    // 以不跟随链接的只读描述符分块计算，大文件不整体装入内存。
    static func sha256(_ file: URL) throws -> String {
        guard FileHashTarget.regularFile(file) != nil else {
            throw FileHashFailure.message("仅支持一个普通文件；目录、符号链接和特殊设备不支持。")
        }
        let descriptor = Darwin.open(file.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else {
            throw FileHashFailure.message("无法只读打开文件：\(String(cString: strerror(errno)))")
        }
        defer {
            Darwin.close(descriptor)
        }
        var before = stat()
        guard fstat(descriptor, &before) == 0,
              before.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
            throw FileHashFailure.message("所选文件已变为目录、链接或特殊对象，请重新选择。")
        }
        var hasher = SHA256()
        var buffer = [UInt8](repeating: 0, count: 1024 * 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes {
                Darwin.read(descriptor, $0.baseAddress, $0.count)
            }
            if count == 0 {
                break
            }
            if count < 0 {
                if errno == EINTR {
                    continue
                }
                throw FileHashFailure.message("读取文件失败：\(String(cString: strerror(errno)))")
            }
            hasher.update(data: Data(buffer.prefix(count)))
        }
        var after = stat()
        var current = stat()
        guard fstat(descriptor, &after) == 0,
              lstat(file.path, &current) == 0,
              current.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              sameSnapshot(before, after),
              sameSnapshot(after, current) else {
            throw FileHashFailure.message("计算期间文件发生变化或被替换；未复制摘要，请重新计算。")
        }
        return hasher.finalize().map {
            String(format: "%02x", $0)
        }.joined()
    }

    private static func sameSnapshot(_ first: stat,
                                     _ second: stat) -> Bool {
        return first.st_dev == second.st_dev &&
            first.st_ino == second.st_ino &&
            first.st_size == second.st_size &&
            first.st_mtimespec.tv_sec == second.st_mtimespec.tv_sec &&
            first.st_mtimespec.tv_nsec == second.st_mtimespec.tv_nsec &&
            first.st_ctimespec.tv_sec == second.st_ctimespec.tv_sec &&
            first.st_ctimespec.tv_nsec == second.st_ctimespec.tv_nsec
    }
}
