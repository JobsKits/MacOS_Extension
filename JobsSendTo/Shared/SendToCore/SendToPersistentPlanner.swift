//
//  SendToPersistentPlanner.swift
//  JobsSendToCore
//
//  Created by Jobs on 2026年11月18日，星期三.
//

import Foundation
import Darwin

enum SendToPersistentPlanner {

    static func plan(sources: [SendToSource], proof: (URL) throws -> SendToVolumeProof,
                     cancel: () -> Bool, progress: (SendToProgress) -> Void) throws -> ([SendToPersistentSource], [SendToPersistentNode]) {
        var roots: [SendToPersistentSource] = []
        var nodes: [SendToPersistentNode] = []
        var lastEmission: UInt64 = 0
        for (top, source) in sources.enumerated() {
            if cancel() {
                throw SendToCoreError.cancelled
            }
            try SendToFilesystem.validate(source)
            let volume = try proof(source.url)
            let prefix = volume.rootURL.path == "/" ? "/" : volume.rootURL.path + "/"
            let relative = source.url.path.hasPrefix(prefix) ? String(source.url.path.dropFirst(prefix.count)) : nil
            roots.append(SendToPersistentSource(source: source, volume: volume, relativePath: relative))
            let fd = Darwin.open(source.url.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
            guard fd >= 0 else {
                throw SendToCoreError.system("打开源快照失败", source.url.path, errno)
            }
            defer {
                close(fd)
            }
            try scan(fd: fd, top: top, relative: [], expectedDevice: source.identity.dev,
                     path: source.url.path, nodes: &nodes, cancel: cancel, progress: {
                         let now = DispatchTime.now().uptimeNanoseconds
                         if now - lastEmission >= 100_000_000 {
                             lastEmission = now
                             progress(SendToProgress(completed: 0, total: sources.count, currentPath: $0, phase: "preparing"))
                         }
                     })
            try SendToFilesystem.validate(source)
        }
        return (roots, nodes)
    }

    private static func scan(fd: Int32, top: Int, relative: [String], expectedDevice: UInt64,
                             path: String, nodes: inout [SendToPersistentNode],
                             cancel: () -> Bool, progress: (String) -> Void) throws {
        if cancel() {
            throw SendToCoreError.cancelled
        }
        guard relative.count <= 512, nodes.count < 200000 else {
            throw SendToCoreError.rejected("源快照超出深度或条目安全上限。")
        }
        let before = try SendToFilesystem.attributes(fd: fd)
        guard SendToFilesystem.identity(before).dev == expectedDevice else {
            throw SendToCoreError.rejected("源目录包含其它挂载卷，未开始复制：\(path)")
        }
        progress(path)
        let index = nodes.count
        var hashes: [String] = []
        let kind: SendToPersistentNode.Kind
        if SendToFilesystem.kind(before) == .file {
            kind = .file
            var offset: Int64 = 0
            while offset < before.st_size {
                if cancel() {
                    throw SendToCoreError.cancelled
                }
                let block = try SendToPersistentIO.readBlock(fd: fd, offset: offset,
                                                            count: min(SendToPersistentIO.blockSize, Int(before.st_size - offset)))
                hashes.append(SendToPersistentIO.digest(block))
                progress(path)
                offset += Int64(block.count)
                guard hashes.count <= 1_000_000 else {
                    throw SendToCoreError.rejected("单文件块清单过大，未开始复制。")
                }
            }
        } else if SendToFilesystem.kind(before) == .directory {
            kind = .directory
        } else {
            throw SendToCoreError.rejected("不复制源特殊节点：\(path)")
        }
        nodes.append(node(index: index, top: top, relative: relative, kind: kind, value: before, link: nil, hashes: hashes))
        if kind == .directory {
            for name in try SendToFilesystem.names(fd: fd, cancel: cancel) {
                if cancel() {
                    throw SendToCoreError.cancelled
                }
                let value = try SendToFilesystem.attributes(parent: fd, name: name)
                if value.st_mode & S_IFMT == S_IFLNK {
                    guard nodes.count < 200000, relative.count < 512 else {
                        throw SendToCoreError.rejected("源链接清单超出安全范围。")
                    }
                    var bytes = [CChar](repeating: 0, count: Int(PATH_MAX) + 1)
                    let count = readlinkat(fd, name, &bytes, bytes.count - 1)
                    guard count >= 0, count < bytes.count - 1 else {
                        throw SendToCoreError.system("读取源链接失败", path + "/" + name, errno)
                    }
                    nodes.append(node(index: nodes.count, top: top, relative: relative + [name], kind: .link,
                                      value: value, link: String(cString: bytes), hashes: []))
                    continue
                }
                let child = openat(fd, name, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
                guard child >= 0 else {
                    throw SendToCoreError.system("读取源子项快照失败", path + "/" + name, errno)
                }
                defer {
                    close(child)
                }
                guard try SendToFilesystem.identity(SendToFilesystem.attributes(fd: child)) == SendToFilesystem.identity(value) else {
                    throw SendToCoreError.rejected("源子项快照期间被替换。")
                }
                try scan(fd: child, top: top, relative: relative + [name], expectedDevice: expectedDevice,
                         path: path + "/" + name, nodes: &nodes, cancel: cancel, progress: progress)
            }
        }
        try verify(nodes[index], value: SendToFilesystem.attributes(fd: fd))
    }

    static func node(index: Int, top: Int, relative: [String], kind: SendToPersistentNode.Kind,
                     value: stat, link: String?, hashes: [String]) -> SendToPersistentNode {
        return SendToPersistentNode(index: index, top: top, relative: relative, kind: kind, ino: value.st_ino,
                                     size: value.st_size, modifiedSeconds: Int64(value.st_mtimespec.tv_sec),
                                     modifiedNanoseconds: Int64(value.st_mtimespec.tv_nsec),
                                     changedSeconds: Int64(value.st_ctimespec.tv_sec), changedNanoseconds: Int64(value.st_ctimespec.tv_nsec),
                                     link: link, hashes: hashes)
    }

    static func verify(_ node: SendToPersistentNode, value: stat) throws {
        let kind: SendToPersistentNode.Kind? = value.st_mode & S_IFMT == S_IFLNK ? .link :
            (SendToFilesystem.kind(value) == .file ? .file : (SendToFilesystem.kind(value) == .directory ? .directory : nil))
        guard kind == node.kind, value.st_ino == node.ino, value.st_size == node.size,
              Int64(value.st_mtimespec.tv_sec) == node.modifiedSeconds,
              Int64(value.st_mtimespec.tv_nsec) == node.modifiedNanoseconds,
              Int64(value.st_ctimespec.tv_sec) == node.changedSeconds,
              Int64(value.st_ctimespec.tv_nsec) == node.changedNanoseconds else {
            throw SendToCoreError.rejected("源在中断期间被编辑或替换，不能混合续传：\(node.relative.joined(separator: "/"))")
        }
    }
}
