//
//  SendToPersistentIO.swift
//  JobsSendToCore
//
//  Created by Jobs on 2026年11月18日，星期三.
//

import Foundation
import Darwin
import CryptoKit

enum SendToPersistentIO {
    static let blockSize = 4 * 1024 * 1024

    static func digest(_ data: Data) -> String {
        return SHA256.hash(data: data).map {
            String(format: "%02x", $0)
        }.joined()
    }

    static func proof(_ url: URL) throws -> SendToVolumeProof {
        var value = statfs()
        guard statfs(url.path, &value) == 0 else {
            throw SendToCoreError.system("读取持久卷身份失败", url.path, errno)
        }
        let rootPath = withUnsafePointer(to: &value.f_mntonname) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MNAMELEN)) {
                String(cString: $0)
            }
        }
        let mountSource = withUnsafePointer(to: &value.f_mntfromname) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MNAMELEN)) {
                String(cString: $0)
            }
        }
        let fsType = withUnsafePointer(to: &value.f_fstypename) {
            $0.withMemoryRebound(to: CChar.self, capacity: 16) {
                String(cString: $0)
            }
        }
        let root = try SendToFilesystem.realURL(URL(fileURLWithPath: rootPath))
        let uuid = try? url.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString
        let fsid = "\(value.f_fsid.val.0):\(value.f_fsid.val.1)"
        var endpoint: String?
        var reconnectURL: URL?
        if UInt64(value.f_flags) & UInt64(MNT_LOCAL) == 0 {
            // Store only a digest of the mounted share endpoint, with any user-info removed.
            let raw = mountSource.hasPrefix("//") ? String(mountSource.dropFirst(2)) : mountSource
            let separator = raw.firstIndex(of: "/") ?? raw.endIndex
            let authority = String(raw[..<separator])
            let host = authority.split(separator: "@", omittingEmptySubsequences: false).last.map(String.init) ?? authority
            let source = host.lowercased() + raw[separator...]
            guard source.contains("/"), !source.isEmpty else {
                throw SendToCoreError.rejected("网络挂载缺少可核对的端点身份。")
            }
            endpoint = digest(Data((fsType + ":" + source).utf8))
            let scheme = fsType == "smbfs" ? "smb" : (fsType == "afpfs" ? "afp" : nil)
            if let scheme, let candidate = URL(string: scheme + "://" + source),
               let value = URLComponents(url: candidate, resolvingAgainstBaseURL: false),
               value.user == nil, value.password == nil, value.query == nil, value.fragment == nil,
               value.host?.isEmpty == false {
                reconnectURL = candidate
            }
        }
        let result = SendToVolumeProof(rootURL: root, uuid: uuid?.lowercased(), fsid: fsid,
                                       networkEndpoint: endpoint, fsType: fsType,
                                       rootIno: try SendToFilesystem.attributes(root.path).st_ino,
                                       reconnectURL: reconnectURL)
        guard result.uuid != nil || result.networkEndpoint != nil else {
            throw SendToCoreError.rejected("此卷没有可核对的持久 UUID 或可信挂载端点，不能安全建立断点任务。")
        }
        return result
    }

    @discardableResult
    static func flush(_ fd: Int32, path: String, directory: Bool = false) throws -> Bool {
        guard fsync(fd) == 0 else {
            throw SendToCoreError.system("持久化同步失败", path, errno)
        }
        if directory {
            return false
        }
        if fcntl(fd, F_FULLFSYNC) == 0 {
            return true
        }
        let code = errno
        guard code == ENOTSUP || code == EINVAL || code == ENOTTY else {
            throw SendToCoreError.system("设备完整同步失败", path, code)
        }
        return false
    }

    static func readBlock(fd: Int32, offset: Int64, count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        var copied = 0
        while copied < count {
            let amount = bytes.withUnsafeMutableBytes {
                pread(fd, $0.baseAddress!.advanced(by: copied), count - copied, off_t(offset + Int64(copied)))
            }
            if amount < 0, errno == EINTR {
                continue
            }
            guard amount > 0 else {
                throw SendToCoreError.system("读取块不完整", "offset \(offset)", amount == 0 ? EIO : errno)
            }
            copied += amount
        }
        return Data(bytes)
    }

    static func writeBlock(fd: Int32, data: Data, offset: Int64, midpoint: (Int64) throws -> Void) throws {
        var copied = 0
        // Smaller writes expose cancellation/crash boundaries inside a durable 4 MiB block.
        while copied < data.count {
            let count = min(256 * 1024, data.count - copied)
            let amount = data.withUnsafeBytes {
                pwrite(fd, $0.baseAddress!.advanced(by: copied), count, off_t(offset + Int64(copied)))
            }
            if amount < 0, errno == EINTR {
                continue
            }
            guard amount > 0 else {
                throw SendToCoreError.system("写入块失败", "offset \(offset)", errno)
            }
            copied += amount
            try midpoint(offset + Int64(copied))
        }
    }

    static func readData(_ url: URL, limit: Int = 128 * 1024 * 1024) throws -> Data {
        let fd = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else {
            throw SendToCoreError.system("读取任务清单失败", url.path, errno)
        }
        defer {
            close(fd)
        }
        let value = try SendToFilesystem.attributes(fd: fd)
        guard SendToFilesystem.kind(value) == .file, value.st_size >= 0, value.st_size <= limit else {
            throw SendToCoreError.rejected("任务清单类型或长度不合法：\(url.path)")
        }
        return try readBlock(fd: fd, offset: 0, count: Int(value.st_size))
    }

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let payload = try JSONEncoder().encode(value)
        return try JSONEncoder().encode(SendToJournalEnvelope(version: 1, payload: payload, digest: digest(payload)))
    }

    static func decode<T: Decodable>(_ type: T.Type, data: Data) throws -> T {
        let envelope = try JSONDecoder().decode(SendToJournalEnvelope.self, from: data)
        guard envelope.version == 1, digest(envelope.payload) == envelope.digest else {
            throw SendToCoreError.rejected("任务清单校验失败；原数据已保留。")
        }
        return try JSONDecoder().decode(type, from: envelope.payload)
    }

    static func save<T: Encodable>(_ value: T, at url: URL) throws {
        let parent = try SendToFilesystem.openDirectory(url.deletingLastPathComponent().path)
        defer {
            close(parent)
        }
        try save(value, parent: parent, name: url.lastPathComponent)
    }

    static func save<T: Encodable>(_ value: T, parent: Int32, name: String) throws {
        let bytes = try encode(value)
        let temporary = ".pending-" + UUID().uuidString
        let fd = openat(parent, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else {
            throw SendToCoreError.system("创建任务检查点失败", name, errno)
        }
        defer {
            close(fd)
            unlinkat(parent, temporary, 0)
        }
        try writeBlock(fd: fd, data: bytes, offset: 0, midpoint: {
            _ in
        })
        try flush(fd, path: name)
        guard renameat(parent, temporary, parent, name) == 0 else {
            throw SendToCoreError.system("提交任务检查点失败", name, errno)
        }
        try flush(parent, path: name, directory: true)
    }

    static func load<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        return try decode(type, data: readData(url))
    }

    static func defaultStore() throws -> URL {
        guard let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw SendToCoreError.rejected("无法定位本机 Application Support。")
        }
        return root.appendingPathComponent("Jobs/JobsSendTo/Transfers", isDirectory: true)
    }
}
