//
//  SendToPersistentEngine.swift
//  JobsSendToCore
//
//  Created by Jobs on 2026年11月18日，星期三.
//

import Foundation
import Darwin

struct SendToPersistentOptions {
    let storeRoot: URL
    var volumeProvider: () throws -> [SendToVolume] = SendToCore.volumes
    var proofProvider: (URL) throws -> SendToVolumeProof = SendToPersistentIO.proof
    var mountedVolumeProvider: () throws -> [URL] = {
        guard let values = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: []) else {
            throw SendToCoreError.rejected("无法核对原设备的实际挂载状态。")
        }
        return values
    }
    var hook: (SendToResumeEvent) -> Void = {
        _ in
    }
}

final class SendToPersistentEngine {
    let options: SendToPersistentOptions

    init(options: SendToPersistentOptions) {
        self.options = options
    }

    func directory(_ id: UUID) -> URL {
        return options.storeRoot.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private func file(_ id: UUID, _ name: String) -> URL {
        return directory(id).appendingPathComponent(name)
    }

    private func nodeName(_ index: Int) -> String {
        return "node-\(index).json"
    }

    private func progressName(_ index: Int) -> String {
        return "progress-\(index).json"
    }

    private func topName(_ index: Int) -> String {
        return "top-\(index).json"
    }

    private func ensureStore() throws {
        let existed = FileManager.default.fileExists(atPath: options.storeRoot.path)
        try FileManager.default.createDirectory(at: options.storeRoot, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let value = try SendToFilesystem.attributes(options.storeRoot.path)
        guard SendToFilesystem.kind(value) == .directory, value.st_uid == geteuid() else {
            throw SendToCoreError.rejected("本机任务目录不是当前用户的真实目录。")
        }
        if !existed {
            // Persist every newly-created ancestor entry before transfer data can exist on the target.
            guard let canonical = realpath(options.storeRoot.path, nil) else {
                throw SendToCoreError.rejected("无法解析本机任务目录真实位置。")
            }
            var path = String(cString: canonical)
            free(canonical)
            while true {
                let fd = try SendToFilesystem.openDirectory(path)
                do {
                    try SendToPersistentIO.flush(fd, path: path, directory: true)
                    close(fd)
                } catch {
                    close(fd)
                    throw error
                }
                let parent = (path as NSString).deletingLastPathComponent
                if parent == path {
                    break
                }
                path = parent
            }
        }
    }

    private func lock(_ id: UUID) throws -> Int32 {
        try validateTaskDirectory(id)
        let fd = Darwin.open(file(id, "lock").path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else {
            throw SendToCoreError.system("打开任务互斥锁失败", id.uuidString, errno)
        }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            throw SendToCoreError.rejected("此任务正由另一进程处理；未按 PID 抢占锁。")
        }
        return fd
    }

    private func load(_ id: UUID) throws -> SendToTaskRecord {
        try validateTaskDirectory(id)
        let task = try SendToPersistentIO.load(SendToTaskRecord.self, from: file(id, "task.json"))
        let target = task.summary.destination
        guard task.version == 1, task.summary.id == id, task.summary.total == task.sources.count,
              target.url.isFileURL, (target.rootURL == nil) == (target.rootIdentity == nil),
              target.rootURL.map({ $0.isFileURL && target.url.path.hasPrefix($0.path + "/") }) ?? true,
              !task.sources.isEmpty, task.sources.count <= 128,
              task.summary.completed >= 0, task.summary.completed <= task.summary.total,
              task.nodeCount >= task.sources.count, task.nodeCount <= 200000, task.nonce.utf8.count == 72 else {
            throw SendToCoreError.rejected("未知或不完整任务清单，原数据保留。")
        }
        return task
    }

    private func validateTaskDirectory(_ id: UUID) throws {
        for path in [options.storeRoot.path, directory(id).path] {
            let value = try SendToFilesystem.attributes(path)
            guard SendToFilesystem.kind(value) == .directory, value.st_uid == geteuid() else {
                throw SendToCoreError.rejected("任务路径含链接或未知归属目录，已阻止访问：\(path)")
            }
        }
    }

    private func save(_ task: SendToTaskRecord) throws {
        try SendToPersistentIO.save(task, at: file(task.summary.id, "task.json"))
    }

    func create(sources: [SendToSource], destination: SendToVolume,
                cancel: () -> Bool = {
                    false
                }, progress: (SendToProgress) -> Void = {
                    _ in
                }) throws -> UUID {
        guard !sources.isEmpty, sources.count <= 128,
              try options.volumeProvider().contains(where: {
                  $0.url == destination.volumeURL && $0.identity == destination.volumeIdentity
              }),
              SendToCore.canCopy(sources: sources, destination: destination) else {
            throw SendToCoreError.rejected("所选源或目标不是当前可用的安全复制对象。")
        }
        let destinationProof = try options.proofProvider(destination.volumeURL)
        guard destinationProof.uuid != nil || destinationProof.networkEndpoint != nil else {
            throw SendToCoreError.rejected("目标缺少可核对的持久卷身份。")
        }
        // Baselines are complete before any transfer data is written. A crash during this read-only preparation starts no partial copy.
        let (roots, nodes) = try SendToPersistentPlanner.plan(sources: sources, proof: options.proofProvider,
                                                            cancel: cancel, progress: progress)
        if cancel() {
            throw SendToCoreError.cancelled
        }
        try ensureStore()
        let id = UUID()
        try FileManager.default.createDirectory(at: directory(id), withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        let fd = try lock(id)
        defer {
            close(fd)
        }
        for node in nodes {
            try SendToPersistentIO.save(node, at: file(id, nodeName(node.index)))
        }
        for index in roots.indices {
            try SendToPersistentIO.save(SendToTopProgress(), at: file(id, topName(index)))
        }
        let summary = SendToTaskSummary(id: id, destination: destination, sourcePaths: sources.map {
            $0.url.path
        },
                                         state: "queued", completed: 0, total: sources.count, updatedAt: Date(), detail: nil, isBusy: false)
        let task = SendToTaskRecord(version: 1, summary: summary,
                                    nonce: UUID().uuidString + UUID().uuidString,
                                    destinationProof: destinationProof, sources: roots, nodeCount: nodes.count,
                                    stageIno: nil, durability: "块数据先 fsync，再尝试 F_FULLFSYNC；本机清单原子替换并同步父目录。网络服务器确认不等于物理介质断电保证。")
        try save(task)
        let storeFD = try SendToFilesystem.openDirectory(options.storeRoot.path)
        defer {
            close(storeFD)
        }
        try SendToPersistentIO.flush(storeFD, path: options.storeRoot.path, directory: true)
        return id
    }

    func pendingTasks() throws -> [SendToTaskSummary] {
        guard FileManager.default.fileExists(atPath: options.storeRoot.path) else {
            return []
        }
        try ensureStore()
        var result: [SendToTaskSummary] = []
        for name in try FileManager.default.contentsOfDirectory(atPath: options.storeRoot.path) {
            guard let id = UUID(uuidString: name) else {
                continue
            }
            var summary: SendToTaskSummary
            do {
                summary = try load(id).summary
                if summary.state == "completed" || summary.state == "discarded" {
                    continue
                }
            } catch {
                summary = SendToTaskSummary(id: id, destination: SendToVolume(url: URL(fileURLWithPath: "/"), name: "未知目标",
                                                                                 identity: SendToIdentity(dev: 0, ino: 0), isNetwork: false),
                                             sourcePaths: [], state: "blocked", completed: 0, total: 0,
                                             updatedAt: Date(), detail: "任务清单损坏或未知，已保留并阻止恢复：\(error.localizedDescription)", isBusy: false)
            }
            do {
                let fd = try lock(id)
                close(fd)
            } catch {
                summary.isBusy = true
            }
            if summary.state == "running", !summary.isBusy {
                summary.state = "paused"
                summary.detail = "上次进程已中断；可校验后继续，本机账本与目标暂存均保留。"
            }
            result.append(summary)
        }
        return result.sorted {
            $0.updatedAt > $1.updatedAt
        }
    }

    func destinationProof(taskID: UUID) throws -> SendToVolumeProof {
        return try load(taskID).destinationProof
    }

    func resolvedDestination(taskID: UUID) throws -> SendToVolume {
        return try destination(load(taskID))
    }

    // Match logical source sets and an anchored target, then separately decide whether the old baseline can resume.
    func matchingTasks(sources: [SendToSource], destination: SendToVolume? = nil,
                        cancel: () -> Bool = { false }) throws -> [SendToTaskMatch] {
        let currentProof = try destination.map { try options.proofProvider($0.volumeURL) }
        func sourceKey(_ source: SendToSource, _ proof: SendToVolumeProof) -> String {
            let prefix = proof.rootURL.path == "/" ? "/" : proof.rootURL.path + "/"
            let path = source.url.path.hasPrefix(prefix) ? String(source.url.path.dropFirst(prefix.count)) : source.url.path
            return (proof.uuid ?? proof.networkEndpoint ?? "") + "|" + proof.fsType + "|" + path
        }
        func folderKey(_ value: SendToVolume) -> String {
            guard let root = value.rootURL else {
                return ""
            }
            let prefix = root.path == "/" ? "/" : root.path + "/"
            return value.url.path.hasPrefix(prefix) ? String(value.url.path.dropFirst(prefix.count)) : "<invalid>"
        }
        var currentSources: [String: SendToSource] = [:]
        var currentSourceProofs: [String: SendToVolumeProof] = [:]
        for source in sources {
            let proof = try options.proofProvider(source.url)
            currentSources[sourceKey(source, proof)] = source
            currentSourceProofs[sourceKey(source, proof)] = proof
        }
        var result: [SendToTaskMatch] = []
        for summary in try pendingTasks() {
            if cancel() { throw SendToCoreError.cancelled }
            guard let task = try? load(summary.id),
                  Set(task.sources.map({ sourceKey($0.source, $0.volume) })) == Set(currentSources.keys) else {
                continue
            }
            if let destination, let currentProof,
               (!task.destinationProof.matches(currentProof) || folderKey(task.summary.destination) != folderKey(destination)) {
                continue
            }
            var reason: String?
            var baselineReadable = false
            do {
                guard !summary.isBusy else {
                    throw SendToCoreError.rejected("上次传输正由另一窗口或进程处理。")
                }
                guard destination == nil || task.summary.destination.identity.ino == destination?.identity.ino else {
                    throw SendToCoreError.rejected("原目标文件夹已替换，不能沿用旧断点。")
                }
                let baseline = try nodes(task)
                baselineReadable = true
                for (top, saved) in task.sources.enumerated() {
                    guard let current = currentSources[sourceKey(saved.source, saved.volume)],
                          let currentProof = currentSourceProofs[sourceKey(saved.source, saved.volume)],
                          saved.volume.matches(currentProof),
                          current.identity.ino == saved.source.identity.ino, current.kind == saved.source.kind else {
                        throw SendToCoreError.rejected("源对象已替换，不能继续旧传输。")
                    }
                    try SendToFilesystem.validate(current)
                    let fd = Darwin.open(current.url.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
                    guard fd >= 0 else {
                        throw SendToCoreError.system("无法读取原源对象", current.url.path, errno)
                    }
                    defer {
                        close(fd)
                    }
                    for node in baseline where node.top == top {
                        if cancel() { throw SendToCoreError.cancelled }
                        try verifySource(node, root: fd)
                    }
                }
            } catch {
                reason = error.localizedDescription
            }
            if cancel() { throw SendToCoreError.cancelled }
            var resolved: SendToVolume?
            var temporaryNetworkFailure = false
            do {
                resolved = try self.destination(task)
            } catch {
                if case SendToCoreError.system(_, _, let code) = error {
                    temporaryNetworkFailure = [ENETDOWN, ENETUNREACH, ENETRESET, ECONNABORTED, ECONNRESET,
                                               ENOTCONN, ETIMEDOUT, EHOSTDOWN, EHOSTUNREACH, ECONNREFUSED, EPIPE, ESTALE].contains(code)
                } else {
                    temporaryNetworkFailure = false
                }
                if !temporaryNetworkFailure && reason == nil {
                    reason = error.localizedDescription
                }
            }
            var currentSummary = summary
            if let resolved {
                currentSummary.destination = resolved
            }
            result.append(SendToTaskMatch(summary: currentSummary, canResume: reason == nil, reason: reason,
                                           canRestart: !summary.isBusy && baselineReadable && (resolved != nil || temporaryNetworkFailure)))
        }
        return result
    }

    private func nodes(_ task: SendToTaskRecord) throws -> [SendToPersistentNode] {
        let id = task.summary.id
        var result: [SendToPersistentNode] = []
        var seen = Set<String>()
        for index in 0..<task.nodeCount {
            let node = try SendToPersistentIO.load(SendToPersistentNode.self, from: file(id, nodeName(index)))
            guard node.index == index, task.sources.indices.contains(node.top), node.relative.count <= 512,
                  node.relative.allSatisfy({
                      !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("/") && !$0.utf8.contains(0)
                  }),
                  seen.insert("\(node.top)/" + node.relative.joined(separator: "/")).inserted,
                  node.size >= 0, node.size <= Int64(SendToPersistentIO.blockSize) * 1_000_000,
                  node.hashes.count == (node.kind == .file ? Int((node.size + Int64(SendToPersistentIO.blockSize) - 1) / Int64(SendToPersistentIO.blockSize)) : 0) else {
                throw SendToCoreError.rejected("源块清单结构不合法，保留任务。")
            }
            result.append(node)
        }
        return result
    }

    private func destination(_ task: SendToTaskRecord) throws -> SendToVolume {
        for candidate in try options.volumeProvider() {
            if task.destinationProof.matches(try options.proofProvider(candidate.url)) {
                let saved = task.summary.destination
                if let root = saved.rootURL {
                    let prefix = root.path == "/" ? "/" : root.path + "/"
                    guard saved.rootIdentity != nil, saved.url.path.hasPrefix(prefix) else {
                        throw SendToCoreError.rejected("原任务的卷内目标目录记录不完整，已保留。")
                    }
                    let relative = String(saved.url.path.dropFirst(prefix.count))
                    return try SendToFilesystem.selectedDirectory(root: candidate,
                                                                  folder: candidate.url.appendingPathComponent(relative),
                                                                  expectedInode: saved.identity.ino)
                }
                guard saved.rootIdentity == nil else {
                    throw SendToCoreError.rejected("原任务缺少目标卷根路径，已保留。")
                }
                return candidate
            }
        }
        if task.summary.destination.isNetwork {
            let original = task.summary.destination.volumeURL
            let present = try options.mountedVolumeProvider().contains {
                $0.standardizedFileURL.path == original.path
            }
            guard present else {
                throw SendToCoreError.system("原网络卷尚未重新挂载", original.path, ENOTCONN)
            }
            let proof = try options.proofProvider(original)
            guard task.destinationProof.matches(proof) else {
                throw SendToCoreError.rejected("原挂载路径已被其它卷占用，不能重新连接或续传。")
            }
            let fd = try SendToFilesystem.openDirectory(original.path)
            defer {
                close(fd)
            }
            let root = SendToVolume(url: original, name: task.summary.destination.name,
                                    identity: try SendToFilesystem.identity(SendToFilesystem.attributes(fd: fd)), isNetwork: true)
            try SendToFilesystem.validateDestination(root, fd: fd)
            throw SendToCoreError.rejected("原网络卷仍已挂载，但当前不可写或访问受限；请检查权限后重试。")
        }
        throw SendToCoreError.rejected("原目标卷未挂载或稳定卷身份不匹配；不会按同名路径接管其它卷。")
    }

    private func sourceURL(_ saved: SendToPersistentSource) throws -> URL {
        if let current = try? options.proofProvider(saved.source.url), saved.volume.matches(current) {
            return saved.source.url
        }
        if let relative = saved.relativePath {
            let mounts = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: []) ?? []
            for mount in mounts {
                if let current = try? options.proofProvider(mount), saved.volume.matches(current) {
                    return mount.appendingPathComponent(relative)
                }
            }
        }
        throw SendToCoreError.rejected("原源卷身份不匹配，不能续接：\(saved.source.url.path)")
    }

    private func openPath(root: Int32, components: [String], flags: Int32) throws -> Int32 {
        if components.isEmpty {
            let fd = dup(root)
            guard fd >= 0 else {
                throw SendToCoreError.system("复制对象句柄失败", "root", errno)
            }
            return fd
        }
        var parent = dup(root)
        guard parent >= 0 else {
            throw SendToCoreError.system("复制目录句柄失败", "root", errno)
        }
        defer {
            close(parent)
        }
        for component in components.dropLast() {
            let next = openat(parent, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard next >= 0 else {
                throw SendToCoreError.system("打开任务真实祖先失败", component, errno)
            }
            close(parent)
            parent = next
        }
        let fd = openat(parent, components.last!, flags | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else {
            throw SendToCoreError.system("打开任务对象失败", components.joined(separator: "/"), errno)
        }
        return fd
    }

    private func parentPath(root: Int32, components: [String]) throws -> Int32 {
        return try openPath(root: root, components: Array(components.dropLast()), flags: O_RDONLY | O_DIRECTORY)
    }

    private func verifySource(_ node: SendToPersistentNode, root: Int32) throws {
        if node.kind == .link {
            let parent = try parentPath(root: root, components: node.relative)
            defer {
                close(parent)
            }
            let name = node.relative.last!
            try SendToPersistentPlanner.verify(node, value: SendToFilesystem.attributes(parent: parent, name: name))
            var bytes = [CChar](repeating: 0, count: Int(PATH_MAX) + 1)
            let count = readlinkat(parent, name, &bytes, bytes.count - 1)
            guard count >= 0, count < bytes.count - 1, String(cString: bytes) == node.link else {
                throw SendToCoreError.rejected("源符号链接内容已变化。")
            }
        } else {
            let fd = try openPath(root: root, components: node.relative, flags: O_RDONLY)
            defer {
                close(fd)
            }
            try SendToPersistentPlanner.verify(node, value: SendToFilesystem.attributes(fd: fd))
        }
    }

    private func stageName(_ id: UUID) -> String {
        return ".JobsSendTo-" + id.uuidString
    }

    private func stage(task: inout SendToTaskRecord, destinationFD: Int32) throws -> Int32 {
        let name = stageName(task.summary.id)
        var existing = stat()
        if task.stageIno != nil, fstatat(destinationFD, name, &existing, AT_SYMLINK_NOFOLLOW) != 0 {
            throw SendToCoreError.rejected("已有断点的暂存目录消失，保留账本且不新建替代目录。")
        }
        let created = mkdirat(destinationFD, name, 0o700) == 0
        if !created, errno != EEXIST {
            throw SendToCoreError.system("打开持久暂存失败", name, errno)
        }
        let fd = openat(destinationFD, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else {
            throw SendToCoreError.system("打开持久暂存失败", name, errno)
        }
        do {
            let value = try SendToFilesystem.attributes(fd: fd)
            guard value.st_uid == geteuid(), value.st_mode & 0o777 == 0o700 else {
                throw SendToCoreError.rejected("暂存目录归属或权限不匹配，已保留。")
            }
            let owner = SendToStageOwner(version: 1, taskID: task.summary.id, nonce: task.nonce)
            if created {
                guard task.stageIno == nil else {
                    throw SendToCoreError.rejected("已有断点的暂存目录消失，不能用空目录冒充原任务。")
                }
                try SendToPersistentIO.save(owner, parent: fd, name: "owner.json")
                try SendToPersistentIO.flush(destinationFD, path: name, directory: true)
            } else {
                let ownerFD = openat(fd, "owner.json", O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
                guard ownerFD >= 0 else {
                    throw SendToCoreError.rejected("未知旧暂存缺少任务所有权清单，已保留。")
                }
                defer {
                    close(ownerFD)
                }
                let size = try SendToFilesystem.attributes(fd: ownerFD).st_size
                guard size > 0, size < 16384 else {
                    throw SendToCoreError.rejected("暂存所有权清单不合法。")
                }
                let existing = try SendToPersistentIO.decode(SendToStageOwner.self,
                                                              data: SendToPersistentIO.readBlock(fd: ownerFD, offset: 0, count: Int(size)))
                guard existing == owner else {
                    throw SendToCoreError.rejected("暂存 nonce 或任务归属不匹配，已保留。")
                }
            }
            guard task.stageIno == nil || task.stageIno == value.st_ino else {
                throw SendToCoreError.rejected("持久暂存对象身份变化，已阻止恢复。")
            }
            task.stageIno = value.st_ino
            try save(task)
            return fd
        } catch {
            close(fd)
            throw error
        }
    }

    private func stageComponents(_ node: SendToPersistentNode) -> [String] {
        return ["payload-\(node.top)"] + node.relative
    }

    private func loadProgress(_ id: UUID, _ node: SendToPersistentNode) throws -> SendToNodeProgress {
        let url = file(id, progressName(node.index))
        if !FileManager.default.fileExists(atPath: url.path) {
            return SendToNodeProgress()
        }
        let value = try SendToPersistentIO.load(SendToNodeProgress.self, from: url)
        guard value.blocks >= 0, value.blocks <= node.hashes.count else {
            throw SendToCoreError.rejected("块检查点越界，任务保留。")
        }
        guard !value.metadataComplete || (value.dataComplete && (node.kind != .file || value.blocks == node.hashes.count)) else {
            throw SendToCoreError.rejected("元数据检查点与块进度矛盾，保留任务。")
        }
        return value
    }

    private func saveProgress(_ id: UUID, _ node: SendToPersistentNode, _ value: SendToNodeProgress) throws {
        try SendToPersistentIO.save(value, at: file(id, progressName(node.index)))
    }

    private func createNode(_ node: SendToPersistentNode, id: UUID, stageFD: Int32) throws -> SendToNodeProgress {
        var progress = try loadProgress(id, node)
        let components = stageComponents(node)
        let parent = try parentPath(root: stageFD, components: components)
        defer {
            close(parent)
        }
        let name = components.last!
        var value = stat()
        if fstatat(parent, name, &value, AT_SYMLINK_NOFOLLOW) != 0 {
            guard errno == ENOENT else {
                throw SendToCoreError.system("读取断点对象失败", name, errno)
            }
            if progress.stageIno != nil {
                throw SendToCoreError.rejected("断点对象缺失，不能静默另建并误报已续接。")
            }
            if node.kind == .directory {
                guard mkdirat(parent, name, 0o700) == 0 else {
                    throw SendToCoreError.system("建立复制目录失败", name, errno)
                }
            } else if node.kind == .link {
                guard let link = node.link, symlinkat(link, parent, name) == 0 else {
                    throw SendToCoreError.system("建立复制链接失败", name, errno)
                }
            } else {
                let fd = openat(parent, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
                guard fd >= 0 else {
                    throw SendToCoreError.system("建立断点文件失败", name, errno)
                }
                try SendToPersistentIO.flush(fd, path: name)
                close(fd)
            }
            try SendToPersistentIO.flush(parent, path: name, directory: true)
            value = try SendToFilesystem.attributes(parent: parent, name: name)
        }
        let actualKind: SendToPersistentNode.Kind? = value.st_mode & S_IFMT == S_IFLNK ? .link :
            (SendToFilesystem.kind(value) == .directory ? .directory : (SendToFilesystem.kind(value) == .file ? .file : nil))
        guard actualKind == node.kind, value.st_uid == geteuid() else {
            throw SendToCoreError.rejected("暂存对象类型或所有者变化，保留未知数据。")
        }
        if let known = progress.stageIno {
            guard known == value.st_ino else {
                throw SendToCoreError.rejected("暂存对象 inode 变化，保留未知数据。")
            }
        } else {
            if node.kind == .file {
                guard value.st_size == 0, value.st_mode & 0o777 == 0o600 else {
                    throw SendToCoreError.rejected("未记账的非空暂存文件不能自动领养。")
                }
            } else if node.kind == .directory {
                let fd = try openPath(root: stageFD, components: components, flags: O_RDONLY | O_DIRECTORY)
                defer {
                    close(fd)
                }
                guard try SendToFilesystem.names(fd: fd).isEmpty else {
                    throw SendToCoreError.rejected("未记账的非空暂存目录不能自动领养。")
                }
            }
            progress.stageIno = value.st_ino
            try saveProgress(id, node, progress)
        }
        return progress
    }

    private func verifyBlocks(_ node: SendToPersistentNode, fd: Int32, limit: Int) throws -> Int {
        let size = try SendToFilesystem.attributes(fd: fd).st_size
        var valid = 0
        for index in 0..<limit {
            let offset = Int64(index * SendToPersistentIO.blockSize)
            let count = min(SendToPersistentIO.blockSize, Int(node.size - offset))
            guard offset + Int64(count) <= size else {
                break
            }
            let data = try SendToPersistentIO.readBlock(fd: fd, offset: offset, count: count)
            guard SendToPersistentIO.digest(data) == node.hashes[index] else {
                break
            }
            valid += 1
        }
        return valid
    }

    private func metadata(_ node: SendToPersistentNode, source: Int32, output: Int32, cancel: @escaping () -> Bool) throws {
        guard let state = copyfile_state_alloc() else {
            throw SendToCoreError.rejected("无法创建元数据复制状态。")
        }
        defer {
            copyfile_state_free(state)
        }
        let context = SendToCopyContext(cancelled: cancel, progress: {}, dataCheckpoint: {
            _ in
        })
        copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CB), unsafeBitCast(SendToCopyContext.callback, to: UnsafeRawPointer.self))
        copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CTX), Unmanaged.passUnretained(context).toOpaque())
        let code = withExtendedLifetime(context) {
            fcopyfile(source, output, state, copyfile_flags_t(COPYFILE_METADATA))
        }
        if let error = context.firstFailure {
            throw SendToCoreError.system("元数据复制失败", node.relative.joined(separator: "/"), error)
        }
        if context.userCancelled || cancel() {
            throw SendToCoreError.cancelled
        }
        guard code == 0 else {
            throw SendToCoreError.system("元数据复制失败", node.relative.joined(separator: "/"), errno)
        }
        try SendToPersistentIO.flush(output, path: "metadata", directory: node.kind == .directory)
    }

    private func copyNode(_ node: SendToPersistentNode, task: SendToTaskRecord, sourceFD: Int32, stageFD: Int32,
                          cancel: @escaping () -> Bool, progress: (SendToProgress) -> Void) throws {
        let id = task.summary.id
        var checkpoint = try createNode(node, id: id, stageFD: stageFD)
        if node.kind == .link {
            checkpoint.dataComplete = true
            checkpoint.metadataComplete = true
            try saveProgress(id, node, checkpoint)
            options.hook(SendToResumeEvent(phase: .directoryChildCommitted, nodeIndex: node.index, bytes: 0))
            return
        }
        if node.kind == .directory {
            return
        }
        let input = try openPath(root: sourceFD, components: node.relative, flags: O_RDONLY)
        defer {
            close(input)
        }
        try SendToPersistentPlanner.verify(node, value: SendToFilesystem.attributes(fd: input))
        var output = try openPath(root: stageFD, components: stageComponents(node), flags: O_RDONLY)
        defer { if output >= 0 {
            close(output)
        } }
        let valid = try verifyBlocks(node, fd: output, limit: checkpoint.blocks)
        if valid != checkpoint.blocks {
            checkpoint.blocks = valid
            checkpoint.dataComplete = false
            checkpoint.metadataComplete = false
            try saveProgress(id, node, checkpoint)
        }
        if checkpoint.blocks < node.hashes.count {
            // A formerly completed 0400 copy may need a bad-block rollback. Only this verified private inode is adjusted;
            // metadataComplete is already durably false, so the unchanged source metadata will be reapplied after data repair.
            let mode = try SendToFilesystem.attributes(fd: output).st_mode & 0o7777
            if mode & 0o200 == 0 {
                checkpoint.dataComplete = false
                checkpoint.metadataComplete = false
                try saveProgress(id, node, checkpoint)
                guard fchmod(output, mode_t(mode | 0o200)) == 0 else {
                    throw SendToCoreError.system("准备已验证暂存文件的块恢复权限失败", "node \(node.index)", errno)
                }
                try SendToPersistentIO.flush(output, path: "node \(node.index)")
            }
            let previous = output
            output = -1
            close(previous)
            output = try openPath(root: stageFD, components: stageComponents(node), flags: O_RDWR)
            guard ftruncate(output, off_t(min(node.size, Int64(checkpoint.blocks * SendToPersistentIO.blockSize)))) == 0 else {
                throw SendToCoreError.system("回退未验证尾块失败", "node \(node.index)", errno)
            }
            var lastEmission: UInt64 = 0
            for index in checkpoint.blocks..<node.hashes.count {
                if cancel() {
                    throw SendToCoreError.cancelled
                }
                let offset = Int64(index * SendToPersistentIO.blockSize)
                let block = try SendToPersistentIO.readBlock(fd: input, offset: offset, count: min(SendToPersistentIO.blockSize, Int(node.size - offset)))
                guard SendToPersistentIO.digest(block) == node.hashes[index] else {
                    throw SendToCoreError.rejected("源块与初始快照不一致，不能混合续传。")
                }
                try SendToPersistentIO.writeBlock(fd: output, data: block, offset: offset) { bytes in
                    self.options.hook(SendToResumeEvent(phase: .midchunk, nodeIndex: node.index, bytes: bytes))
                    if cancel() {
                        throw SendToCoreError.cancelled
                    }
                    let now = DispatchTime.now().uptimeNanoseconds
                    if now - lastEmission >= 100_000_000 {
                        lastEmission = now
                        progress(SendToProgress(completed: task.summary.completed, total: task.summary.total,
                                                currentPath: task.sources[node.top].source.url.appendingPathComponent(node.relative.joined(separator: "/")).path,
                                                phase: "copying"))
                    }
                }
                try SendToPersistentIO.flush(output, path: "node \(node.index)")
                checkpoint.blocks = index + 1
                try saveProgress(id, node, checkpoint)
                options.hook(SendToResumeEvent(phase: .checkpointDurable, nodeIndex: node.index, bytes: offset + Int64(block.count)))
                if cancel() {
                    throw SendToCoreError.cancelled
                }
            }
        }
        checkpoint.dataComplete = true
        try saveProgress(id, node, checkpoint)
        try SendToPersistentPlanner.verify(node, value: SendToFilesystem.attributes(fd: input))
        if !checkpoint.metadataComplete {
            try metadata(node, source: input, output: output, cancel: cancel)
            options.hook(SendToResumeEvent(phase: .metadataAppliedBeforeCommit, nodeIndex: node.index, bytes: node.size))
            checkpoint.metadataComplete = true
            try saveProgress(id, node, checkpoint)
            options.hook(SendToResumeEvent(phase: .directoryChildCommitted, nodeIndex: node.index, bytes: node.size))
        }
    }

    private func verifyTree(_ nodes: [SendToPersistentNode], root: Int32, prefix: [String]) throws {
        var children: [String: Set<String>] = [:]
        for node in nodes where !node.relative.isEmpty {
            children[node.relative.dropLast().joined(separator: "/"), default: []].insert(node.relative.last!)
        }
        for node in nodes {
            let parts = prefix + node.relative
            if node.kind == .link {
                let parent = try parentPath(root: root, components: parts)
                defer {
                    close(parent)
                }
                let value = try SendToFilesystem.attributes(parent: parent, name: parts.last!)
                var bytes = [CChar](repeating: 0, count: Int(PATH_MAX) + 1)
                let count = readlinkat(parent, parts.last!, &bytes, bytes.count - 1)
                guard value.st_mode & S_IFMT == S_IFLNK, count >= 0, count < bytes.count - 1, String(cString: bytes) == node.link else {
                    throw SendToCoreError.rejected("已复制链接内容不匹配。")
                }
            } else {
                let fd = try openPath(root: root, components: parts, flags: O_RDONLY)
                defer {
                    close(fd)
                }
                let value = try SendToFilesystem.attributes(fd: fd)
                if node.kind == .file {
                    guard SendToFilesystem.kind(value) == .file, value.st_size == node.size,
                          try verifyBlocks(node, fd: fd, limit: node.hashes.count) == node.hashes.count else {
                        throw SendToCoreError.rejected("已发表文件内容校验失败，保留并阻止重复发表。")
                    }
                } else {
                    let expected = children[node.relative.joined(separator: "/")] ?? []
                    guard SendToFilesystem.kind(value) == .directory, Set(try SendToFilesystem.names(fd: fd)) == expected else {
                        throw SendToCoreError.rejected("已复制目录含未知内容或缺少计划项，已保留。")
                    }
                }
            }
        }
    }

    private func tag(fd: Int32, value: String) -> Bool {
        return value.utf8CString.withUnsafeBytes {
            fsetxattr(fd, "com.jobs.sendto.task", $0.baseAddress, $0.count - 1, 0, 0) == 0
        }
    }

    private func verifyTag(fd: Int32, value: String) -> Bool {
        var bytes = [UInt8](repeating: 0, count: 256)
        let count = fgetxattr(fd, "com.jobs.sendto.task", &bytes, bytes.count, 0, 0)
        return count >= 0 && Data(bytes.prefix(count)) == Data(value.utf8)
    }

    private func publish(top: Int, task: SendToTaskRecord, nodes: [SendToPersistentNode], destinationFD: Int32,
                         stageFD: Int32, destination: SendToVolume, cancel: () -> Bool) throws -> URL {
        let id = task.summary.id
        var state = try SendToPersistentIO.load(SendToTopProgress.self, from: file(id, topName(top)))
        guard ["copying", "pending", "published"].contains(state.phase),
              state.candidate.map({
                  !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("/") && !$0.utf8.contains(0)
              }) ?? true else {
            throw SendToCoreError.rejected("发表账本包含未知阶段或非法文件名，已阻止访问。")
        }
        let payload = "payload-\(top)"
        let nonce = task.nonce + ":\(top)"
        if state.phase == "published" || state.phase == "pending" {
            guard let candidate = state.candidate, let knownIno = state.payloadIno else {
                throw SendToCoreError.rejected("发表意图缺少身份，已保留。")
            }
            var actual = stat()
            if fstatat(destinationFD, candidate, &actual, AT_SYMLINK_NOFOLLOW) == 0, actual.st_ino == knownIno {
                let final = try openPath(root: destinationFD, components: [candidate], flags: O_RDONLY)
                defer {
                    close(final)
                }
                guard !state.tagged || verifyTag(fd: final, value: nonce) else {
                    throw SendToCoreError.rejected("同名最终对象缺少本任务 nonce；不会领养或另造副本。")
                }
                if let mode = state.originalMode {
                    guard fchmod(final, mode_t(mode)) == 0 else {
                        throw SendToCoreError.system("恢复已发表目录权限失败", candidate, errno)
                    }
                    try SendToPersistentIO.flush(final, path: candidate, directory: true)
                }
                try verifyTree(nodes, root: destinationFD, prefix: [candidate])
                state.phase = "published"
                try SendToPersistentIO.save(state, at: file(id, topName(top)))
                return destination.url.appendingPathComponent(candidate)
            }
            if state.phase == "published" {
                throw SendToCoreError.rejected("已发表对象已消失或替换；不会重新拷贝覆盖。")
            }
            var staged = stat()
            guard fstatat(stageFD, payload, &staged, AT_SYMLINK_NOFOLLOW) == 0, staged.st_ino == knownIno else {
                throw SendToCoreError.rejected("发表期间发生中断，但最终／暂存身份无法证明；已阻塞，未重复发表。")
            }
        }
        let root = try openPath(root: stageFD, components: [payload], flags: O_RDONLY)
        defer {
            close(root)
        }
        try verifyTree(nodes, root: stageFD, prefix: [payload])
        let ino = try SendToFilesystem.attributes(fd: root).st_ino
        if nodes.first?.kind == .directory {
            if state.originalMode == nil {
                state.originalMode = try SendToFilesystem.attributes(fd: root).st_mode & 0o7777
                try SendToPersistentIO.save(state, at: file(id, topName(top)))
            }
            guard fchmod(root, mode_t(state.originalMode! | 0o200)) == 0 else {
                throw SendToCoreError.system("暂时准备已验证目录的发表权限失败", payload, errno)
            }
            try SendToPersistentIO.flush(root, path: payload, directory: true)
        }
        state.tagged = tag(fd: root, value: nonce)
        try SendToPersistentIO.flush(root, path: payload, directory: nodes.first?.kind == .directory)
        for number in 1...10000 {
            if cancel() {
                throw SendToCoreError.cancelled
            }
            try SendToFilesystem.validateDestination(destination, fd: destinationFD)
            let candidate = SendToCopySession.availableName(task.sources[top].source.url.lastPathComponent, number: number)
            state.phase = "pending"
            state.candidate = candidate
            state.payloadIno = ino
            try SendToPersistentIO.save(state, at: file(id, topName(top)))
            options.hook(SendToResumeEvent(phase: .publishingIntent, nodeIndex: nodes.first?.index, bytes: nil))
            if renameatx_np(stageFD, payload, destinationFD, candidate, UInt32(RENAME_EXCL)) == 0 {
                try SendToPersistentIO.flush(destinationFD, path: candidate, directory: true)
                options.hook(SendToResumeEvent(phase: .afterRename, nodeIndex: nodes.first?.index, bytes: nil))
                if let mode = state.originalMode {
                    guard fchmod(root, mode_t(mode)) == 0 else {
                        throw SendToCoreError.system("恢复已发表目录原权限失败", candidate, errno)
                    }
                    try SendToPersistentIO.flush(root, path: candidate, directory: true)
                }
                state.phase = "published"
                try SendToPersistentIO.save(state, at: file(id, topName(top)))
                return destination.url.appendingPathComponent(candidate)
            }
            guard errno == EEXIST else {
                throw SendToCoreError.system("排他发表失败，意图与暂存已保留", candidate, errno)
            }
        }
        throw SendToCoreError.rejected("同名项过多，未覆盖任何目标。")
    }

    func resume(taskID id: UUID, cancel: @escaping () -> Bool,
                progress: @escaping (SendToProgress) -> Void) -> SendToResult {
        var result = SendToResult()
        result.taskID = id
        result.resumeAvailable = true
        var task: SendToTaskRecord?
        var lockFD: Int32 = -1
        var destinationFD: Int32 = -1
        var stageFD: Int32 = -1
        var sourceFDs: [Int32] = []
        defer {
            sourceFDs.filter {
                $0 >= 0
            }.forEach {
                close($0)
            }
            if stageFD >= 0 {
                close(stageFD)
            }
            if destinationFD >= 0 {
                close(destinationFD)
            }
            if lockFD >= 0 {
                close(lockFD)
            }
        }
        do {
            lockFD = try lock(id)
            var current = try load(id)
            task = current
            if current.summary.state == "discarded" {
                result.resumeAvailable = false
                throw SendToCoreError.rejected("此任务已明确放弃，不再恢复传输。")
            }
            if current.summary.state == "completed" {
                result.resumeAvailable = false
                let receipt = try SendToPersistentIO.load(SendToCompletionReceipt.self, from: file(id, "receipt.json"))
                guard receipt.id == id else {
                    throw SendToCoreError.rejected("完成收据身份不匹配。")
                }
                result.successes = receipt.published
                result.resumeAvailable = false
                return result
            }
            let allNodes = try nodes(current)
            let volume = try destination(current)
            destinationFD = try SendToFilesystem.openDirectory(volume.url.path)
            try SendToFilesystem.validateDestination(volume, fd: destinationFD)
            sourceFDs = [Int32](repeating: -1, count: current.sources.count)
            stageFD = try stage(task: &current, destinationFD: destinationFD)
            current.summary.destination = volume
            current.summary.state = "running"
            current.summary.updatedAt = Date()
            current.summary.detail = nil
            try save(current)
            task = current
            for top in current.sources.indices {
                if cancel() {
                    throw SendToCoreError.cancelled
                }
                let group = allNodes.filter {
                    $0.top == top
                }
                let topState = try SendToPersistentIO.load(SendToTopProgress.self, from: file(id, topName(top)))
                var finalStat = stat()
                let reconcile = topState.phase == "published" ||
                    (topState.phase == "pending" && topState.candidate != nil &&
                     fstatat(destinationFD, topState.candidate!, &finalStat, AT_SYMLINK_NOFOLLOW) == 0 && finalStat.st_ino == topState.payloadIno)
                if !reconcile {
                    let saved = current.sources[top]
                    let url = try sourceURL(saved)
                    let fresh = try SendToCore.snapshotSources([url])[0]
                    guard fresh.identity.ino == saved.source.identity.ino else {
                        throw SendToCoreError.rejected("源对象稳定 fileID 已变化，任务保留。")
                    }
                    let parent = try SendToFilesystem.openDirectory(url.deletingLastPathComponent().path)
                    do {
                        sourceFDs[top] = try openPath(root: parent, components: [url.lastPathComponent], flags: O_RDONLY)
                        close(parent)
                    } catch {
                        close(parent)
                        throw error
                    }
                    try SendToFilesystem.assertOutsideSources([fresh], destination: volume, fd: destinationFD)
                    for node in group {
                        try verifySource(node, root: sourceFDs[top])
                    }
                }
                if topState.phase == "copying" {
                    for node in group {
                        try verifySource(node, root: sourceFDs[top])
                        try copyNode(node, task: current, sourceFD: sourceFDs[top], stageFD: stageFD, cancel: cancel, progress: progress)
                    }
                    for node in group.reversed() where node.kind == .directory {
                        var checkpoint = try loadProgress(id, node)
                        if !checkpoint.metadataComplete {
                            let input = try openPath(root: sourceFDs[top], components: node.relative, flags: O_RDONLY | O_DIRECTORY)
                            let output = try openPath(root: stageFD, components: stageComponents(node), flags: O_RDONLY | O_DIRECTORY)
                            defer {
                                close(input)
                                close(output)
                            }
                            try metadata(node, source: input, output: output, cancel: cancel)
                            options.hook(SendToResumeEvent(phase: .metadataAppliedBeforeCommit, nodeIndex: node.index, bytes: nil))
                            checkpoint.dataComplete = true
                            checkpoint.metadataComplete = true
                            try saveProgress(id, node, checkpoint)
                        }
                    }
                }
                if !reconcile {
                    for node in group {
                        try verifySource(node, root: sourceFDs[top])
                    }
                }
                let final = try publish(top: top, task: current, nodes: group, destinationFD: destinationFD,
                                        stageFD: stageFD, destination: volume, cancel: cancel)
                result.successes.append(final)
                current.summary.completed = top + 1
                current.summary.updatedAt = Date()
                try save(current)
                task = current
                progress(SendToProgress(completed: top + 1, total: current.sources.count, currentPath: final.path, phase: "copying"))
            }
            current.summary.state = "completed"
            current.summary.detail = "全部发表事实已持久化；本机仅保留小完成收据，已发表文件不删除。"
            current.summary.updatedAt = Date()
            try SendToPersistentIO.save(SendToCompletionReceipt(id: id, published: result.successes, completedAt: Date()), at: file(id, "receipt.json"))
            try save(current)
            do {
                try compactCompleted(current, allNodes: allNodes, destinationFD: destinationFD, stageFD: stageFD)
            } catch {
                result.failures.append(SendToFailure(source: nil, code: "cleanup",
                                                     message: "任务已完成，但账本／空暂存精简未完成，原记录保留：\(error.localizedDescription)"))
            }
            result.resumeAvailable = false
            return result
        } catch {
            let cancelled: Bool
            if case SendToCoreError.cancelled = error {
                cancelled = true
            } else {
                cancelled = false
            }
            result.cancelled = cancelled
            if !cancelled {
                let systemCode: Int32?
                if case SendToCoreError.system(_, _, let code) = error {
                    systemCode = code
                } else {
                    systemCode = nil
                }
                result.failures.append(SendToFailure(source: nil, code: "resume-blocked", message: error.localizedDescription,
                                                     systemCode: systemCode))
            }
            if var current = task, current.summary.state != "discarded", current.summary.state != "completed" {
                current.summary.state = cancelled ? "paused" : "blocked"
                current.summary.updatedAt = Date()
                current.summary.detail = error.localizedDescription
                do {
                    try save(current)
                } catch {
                    result.failures.append(SendToFailure(source: nil, code: "journal", message: "状态未能落盘，原账本已保留：\(error.localizedDescription)"))
                }
            }
            return result
        }
    }
}

extension SendToPersistentEngine {

    private func compactCompleted(_ task: SendToTaskRecord, allNodes: [SendToPersistentNode], destinationFD: Int32, stageFD: Int32) throws {
        let id = task.summary.id
        guard Set(try SendToFilesystem.names(fd: stageFD)) == ["owner.json"],
              try SendToFilesystem.attributes(parent: destinationFD, name: stageName(id)).st_ino == task.stageIno else {
            throw SendToCoreError.rejected("完成后的暂存含未知内容，未自动删除。")
        }
        guard unlinkat(stageFD, "owner.json", 0) == 0,
              unlinkat(destinationFD, stageName(id), AT_REMOVEDIR) == 0 else {
            throw SendToCoreError.system("移除完成后的空暂存失败", stageName(id), errno)
        }
        try SendToPersistentIO.flush(destinationFD, path: stageName(id), directory: true)
        var updated = task
        updated.stageIno = nil
        try save(updated)
        let fd = try SendToFilesystem.openDirectory(directory(id).path)
        defer {
            close(fd)
        }
        let names = allNodes.flatMap {
            [nodeName($0.index), progressName($0.index)]
        } + task.sources.indices.map {
            topName($0)
        }
        for name in names {
            if unlinkat(fd, name, 0) != 0, errno != ENOENT {
                throw SendToCoreError.system("精简已完成块账本失败", name, errno)
            }
        }
        try SendToPersistentIO.flush(fd, path: directory(id).path, directory: true)
    }

    // Explicit abandonment validates the complete private inventory before unlinking any entry.
    func discard(taskID id: UUID) throws {
        let lockFD = try lock(id)
        defer {
            close(lockFD)
        }
        var task = try load(id)
        if task.summary.state == "discarded" {
            try pruneDiscarded(id)
            return
        }
        let allNodes = try nodes(task)
        let volume = try destination(task)
        let destinationFD = try SendToFilesystem.openDirectory(volume.url.path)
        defer {
            close(destinationFD)
        }
        try SendToFilesystem.validateDestination(volume, fd: destinationFD)
        var rootValue = stat()
        let exists = fstatat(destinationFD, stageName(id), &rootValue, AT_SYMLINK_NOFOLLOW) == 0
        if exists {
            let stageFD = try stage(task: &task, destinationFD: destinationFD)
            defer {
                close(stageFD)
            }
            var known: [String: (SendToPersistentNode, UInt64)] = [:]
            for node in allNodes {
                let checkpoint = try loadProgress(id, node)
                if let ino = checkpoint.stageIno {
                    known[stageComponents(node).joined(separator: "/")] = (node, ino)
                }
            }
            var actual: [([String], stat)] = []
            func inspect(_ fd: Int32, _ prefix: [String]) throws {
                for name in try SendToFilesystem.names(fd: fd) {
                    if prefix.isEmpty, name == "owner.json" {
                        continue
                    }
                    let parts = prefix + [name]
                    let key = parts.joined(separator: "/")
                    let value = try SendToFilesystem.attributes(parent: fd, name: name)
                    guard let (node, ino) = known[key], value.st_ino == ino,
                          (node.kind == .link ? value.st_mode & S_IFMT == S_IFLNK :
                            (node.kind == .directory ? SendToFilesystem.kind(value) == .directory : SendToFilesystem.kind(value) == .file)) else {
                        throw SendToCoreError.rejected("暂存包含未记账或身份变化的数据，已全部保留：\(key)")
                    }
                    actual.append((parts, value))
                    if node.kind == .directory {
                        let child = openat(fd, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                        guard child >= 0 else {
                            throw SendToCoreError.system("无法核对暂存目录", key, errno)
                        }
                        defer {
                            close(child)
                        }
                        try inspect(child, parts)
                    }
                }
            }
            try inspect(stageFD, [])
            // Only verified private copies receive temporary owner-write permission for removal.
            for (parts, expected) in actual where SendToFilesystem.kind(expected) == .directory {
                let fd = try openPath(root: stageFD, components: parts, flags: O_RDONLY | O_DIRECTORY)
                defer {
                    close(fd)
                }
                guard try SendToFilesystem.attributes(fd: fd).st_ino == expected.st_ino,
                      fchmod(fd, 0o700) == 0 else {
                    throw SendToCoreError.rejected("本次暂存目录无法安全取得清理权限，已保留。")
                }
            }
            for (parts, expected) in actual.sorted(by: {
                $0.0.count > $1.0.count
            }) {
                let parent = try parentPath(root: stageFD, components: parts)
                defer {
                    close(parent)
                }
                guard try SendToFilesystem.attributes(parent: parent, name: parts.last!).st_ino == expected.st_ino else {
                    throw SendToCoreError.rejected("删除前暂存身份变化，已保留。")
                }
                guard unlinkat(parent, parts.last!, SendToFilesystem.kind(expected) == .directory ? AT_REMOVEDIR : 0) == 0 else {
                    throw SendToCoreError.system("删除本次暂存失败", parts.joined(separator: "/"), errno)
                }
            }
            guard Set(try SendToFilesystem.names(fd: stageFD)) == ["owner.json"] else {
                throw SendToCoreError.rejected("暂存出现新内容，停止清理并保留。")
            }
            guard unlinkat(stageFD, "owner.json", 0) == 0,
                  try SendToFilesystem.attributes(parent: destinationFD, name: stageName(id)).st_ino == task.stageIno,
                  unlinkat(destinationFD, stageName(id), AT_REMOVEDIR) == 0 else {
                throw SendToCoreError.rejected("暂存根目录未能安全清除，保留本机账本。")
            }
            try SendToPersistentIO.flush(destinationFD, path: stageName(id), directory: true)
        } else if task.stageIno != nil {
            throw SendToCoreError.rejected("原暂存目录缺失，保留本机账本供核对。")
        }
        task.summary.state = "discarded"
        task.summary.detail = "已明确放弃；只保留小型禁用收据和原互斥锁，不删除已发表文件。"
        task.summary.updatedAt = Date()
        try save(task)
        try pruneDiscarded(id)
    }

    private func pruneDiscarded(_ id: UUID) throws {
        let localFD = try SendToFilesystem.openDirectory(directory(id).path)
        defer {
            close(localFD)
        }
        let names = try SendToFilesystem.names(fd: localFD)
        guard names.allSatisfy({ $0 == "task.json" || $0 == "lock" || $0 == "receipt.json" ||
            $0.range(of: "^(node|progress|top)-[0-9]+\\.json$", options: .regularExpression) != nil ||
            ($0.hasPrefix(".pending-") && UUID(uuidString: String($0.dropFirst(9))) != nil) }) else {
            throw SendToCoreError.rejected("本机任务目录包含未知文件，已保留。")
        }
        for name in names where name != "task.json" && name != "lock" {
            let value = try SendToFilesystem.attributes(parent: localFD, name: name)
            guard SendToFilesystem.kind(value) == .file, value.st_uid == geteuid(), unlinkat(localFD, name, 0) == 0 else {
                throw SendToCoreError.rejected("本机任务文件归属变化，停止清理。")
            }
        }
        // Keep the original lock inode permanently; unlinking it while held would create a split-lock race.
        try SendToPersistentIO.flush(localFD, path: directory(id).path, directory: true)
    }
}
