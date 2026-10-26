//
//  RunRevocationValidator.swift
//  JobsRunRevocationShared
//
//  Created by Jobs on 2026年10月24日，星期六.
//

import Foundation
import Darwin

/// 菜单和宿主共用单文件边界，不将目录、工程包或符号链接当成可授权文件。
struct RunRevocationValidator {
    private let scriptExtensions: Set<String> = [
        "command", "sh", "bash", "zsh", "ksh", "csh", "tcsh", "fish",
        "py", "pyw", "rb", "pl", "swift", "js", "mjs", "lua", "tcl", "awk", "expect",
        "scpt", "applescript"
    ]

    func isRegularFile(at url: URL) -> Bool {
        guard url.isFileURL,
              !url.path.utf8.contains(0),
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.standardizedFileURL.path),
              let type = attributes[.type] as? FileAttributeType else {
            return false
        }
        return type == .typeRegular
    }

    func isExecutableFormat(at url: URL) -> Bool {
        guard isRegularFile(at: url) else {
            return false
        }
        if scriptExtensions.contains(url.pathExtension.lowercased()) {
            return true
        }
        // 只读取短文件头，不启动解释器，也不把误加 +x 的文档当成脚本。
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else {
            return false
        }
        defer {
            close(descriptor)
        }
        var info = stat()
        guard fstat(descriptor, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFREG else {
            return false
        }
        let header = readHeader(descriptor, offset: 0, count: 32)
        if url.pathExtension.isEmpty, header.starts(with: [0x23, 0x21]), header.count > 2 {
            return true
        }
        if isMachOExecutable(header) {
            return true
        }
        let magic = Array(header.prefix(4))
        let isFat64 = magic == [0xca, 0xfe, 0xba, 0xbf]
        guard header.count >= 8,
              magic == [0xca, 0xfe, 0xba, 0xbe] || isFat64 else {
            return false
        }
        let architectureCount = unsignedInteger(header, offset: 4, count: 4)
        guard architectureCount > 0, architectureCount <= 64 else {
            return false
        }
        let entrySize = isFat64 ? 32 : 20
        let table = readHeader(descriptor, offset: 8, count: Int(architectureCount) * entrySize)
        guard table.count == Int(architectureCount) * entrySize else {
            return false
        }
        for index in 0..<Int(architectureCount) {
            let offset = unsignedInteger(table, offset: index * entrySize + 8, count: isFat64 ? 8 : 4)
            guard offset <= UInt64(Int64.max), offset < UInt64(info.st_size) else {
                continue
            }
            if isMachOExecutable(readHeader(descriptor, offset: off_t(offset), count: 32)) {
                return true
            }
        }
        return false
    }

    func hasExecutionPermission(at url: URL) -> Bool {
        guard isRegularFile(at: url),
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let mode = attributes[.posixPermissions] as? NSNumber else {
            return false
        }
        return mode.intValue & 0o111 != 0
    }

    private func readHeader(_ descriptor: Int32, offset: off_t, count: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: count)
        let length = pread(descriptor, &bytes, count, offset)
        return length > 0 ? Array(bytes.prefix(length)) : []
    }

    private func unsignedInteger(_ bytes: [UInt8], offset: Int, count: Int) -> UInt64 {
        return bytes[offset..<(offset + count)].reduce(UInt64(0)) { value, byte in
            (value << 8) | UInt64(byte)
        }
    }

    private func isMachOExecutable(_ header: [UInt8]) -> Bool {
        guard header.count >= 28 else {
            return false
        }
        let magic = Array(header.prefix(4))
        if magic == [0xce, 0xfa, 0xed, 0xfe] || magic == [0xcf, 0xfa, 0xed, 0xfe] {
            return Array(header[12..<16]) == [2, 0, 0, 0]
        }
        if magic == [0xfe, 0xed, 0xfa, 0xce] || magic == [0xfe, 0xed, 0xfa, 0xcf] {
            return Array(header[12..<16]) == [0, 0, 0, 2]
        }
        return false
    }

    func selectedFile(from urls: [URL]?) -> URL? {
        guard let urls, urls.count == 1,
              let url = urls.first,
              isExecutableFormat(at: url) else {
            return nil
        }
        return url.standardizedFileURL
    }
}
