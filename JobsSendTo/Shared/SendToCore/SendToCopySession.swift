//
//  SendToCopySession.swift
//  JobsSendToCore
//
//  Created by Jobs on 2026年11月18日，星期三.
//

import Foundation
import Darwin

final class SendToCopySession {
    private let sources: [SendToSource]
    private let destination: SendToVolume
    private let validateMount: () throws -> Void
    private let cancel: () -> Bool
    private let progress: (SendToProgress) -> Void
    private let dataCheckpoint: (Int64) -> Void
    private let publicationCheckpoint: (URL) -> Void
    private var completed = 0
    private var lastProgress: UInt64 = 0
    private var copiedEntries = 0

    init(sources: [SendToSource], destination: SendToVolume,
         validateMount: @escaping () throws -> Void,
         cancel: @escaping () -> Bool,
         progress: @escaping (SendToProgress) -> Void,
         dataCheckpoint: @escaping (Int64) -> Void = { _ in },
         publicationCheckpoint: @escaping (URL) -> Void = { _ in }) {
        self.sources = sources
        self.destination = destination
        self.validateMount = validateMount
        self.cancel = cancel
        self.progress = progress
        self.dataCheckpoint = dataCheckpoint
        self.publicationCheckpoint = publicationCheckpoint
    }

    func run() -> SendToResult {
        var result = SendToResult()
        var destinationFD: Int32 = -1
        defer {
            if destinationFD >= 0 {
                close(destinationFD)
            }
        }
        do {
            guard !sources.isEmpty, sources.count <= 128 else {
                throw SendToCoreError.rejected("请选择 1 至 128 个普通文件或文件夹。")
            }
            try checkCancellation()
            try validateMount()
            destinationFD = try SendToFilesystem.openDirectory(destination.url.path)
            try SendToFilesystem.validateDestination(destination, fd: destinationFD)
            try SendToFilesystem.assertOutsideSources(sources, destination: destination, fd: destinationFD)
        } catch SendToCoreError.cancelled {
            result.cancelled = true
            return result
        } catch {
            result.failures.append(SendToFailure(source: nil, code: "preflight", message: error.localizedDescription))
            return result
        }
        for source in sources {
            if cancel() {
                result.cancelled = true
                break
            }
            let stageName = ".JobsSendTo-" + UUID().uuidString
            var stageIdentity: SendToIdentity?
            var stageFD: Int32 = -1
            do {
                try SendToFilesystem.validate(source)
                try SendToFilesystem.validateDestination(destination, fd: destinationFD)
                guard mkdirat(destinationFD, stageName, 0o700) == 0 else {
                    throw SendToCoreError.system("创建本次私有暂存目录失败", destination.url.path, errno)
                }
                let created = try SendToFilesystem.attributes(parent: destinationFD, name: stageName)
                stageIdentity = SendToFilesystem.identity(created)
                stageFD = openat(destinationFD, stageName, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                guard stageFD >= 0,
                      try SendToFilesystem.identity(SendToFilesystem.attributes(fd: stageFD)) == stageIdentity else {
                    throw SendToCoreError.rejected("本次暂存目录无法打开或身份变化。")
                }
                let input = Darwin.open(source.url.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC | (source.kind == .directory ? O_DIRECTORY : 0))
                guard input >= 0 else {
                    throw SendToCoreError.system("打开源对象失败", source.url.path, errno)
                }
                do {
                    let opened = try SendToFilesystem.attributes(fd: input)
                    guard SendToFilesystem.identity(opened) == source.identity,
                          SendToFilesystem.kind(opened) == source.kind else {
                        throw SendToCoreError.rejected("源对象在复制前已变化：\(source.url.path)")
                    }
                    try copyNode(sourceFD: input, attributes: opened, parent: stageFD,
                                 name: "payload", path: source.url.path, rootDevice: source.identity.dev, depth: 0)
                    close(input)
                } catch {
                    close(input)
                    throw error
                }
                try checkCancellation()
                try SendToFilesystem.validate(source)
                try SendToFilesystem.validateDestination(destination, fd: destinationFD)
                guard let stageIdentity,
                      try SendToFilesystem.identity(SendToFilesystem.attributes(parent: destinationFD, name: stageName)) == stageIdentity else {
                    throw SendToCoreError.rejected("本次暂存目录在发表前已替换。")
                }
                let published = try publish(stageFD: stageFD, destinationFD: destinationFD, name: source.url.lastPathComponent)
                let publishedURL = destination.url.appendingPathComponent(published)
                result.successes.append(publishedURL)
                publicationCheckpoint(publishedURL)
                do {
                    try SendToFilesystem.validateDestination(destination, fd: destinationFD)
                } catch {
                    result.failures.append(SendToFailure(source: source.url, code: "post-publication",
                                                         message: "复制结果已发表并保留，但发表后目标路径不可确认：\(publishedURL.path)；\(error.localizedDescription)"))
                }
            } catch SendToCoreError.cancelled {
                result.cancelled = true
            } catch {
                result.failures.append(SendToFailure(source: source.url, code: "copy", message: error.localizedDescription))
            }
            if stageFD >= 0 {
                close(stageFD)
            }
            if let stageIdentity {
                do {
                    try SendToFilesystem.removePrivateEntry(parent: destinationFD, name: stageName, expected: stageIdentity)
                } catch {
                    result.failures.append(SendToFailure(source: source.url, code: "cleanup",
                                                         message: "\(error.localizedDescription)；暂存位置：\(destination.url.appendingPathComponent(stageName).path)"))
                }
            }
            if result.cancelled {
                break
            }
            completed += 1
            emit(source.url.path, force: true)
        }
        return result
    }

    private func checkCancellation() throws {
        if cancel() {
            throw SendToCoreError.cancelled
        }
    }

    private func emit(_ path: String, force: Bool = false) {
        let now = DispatchTime.now().uptimeNanoseconds
        if force || now - lastProgress >= 100_000_000 {
            lastProgress = now
            progress(SendToProgress(completed: completed, total: sources.count, currentPath: path))
        }
    }

    private func copyNode(sourceFD: Int32, attributes: stat, parent: Int32, name: String,
                          path: String, rootDevice: UInt64, depth: Int) throws {
        try checkCancellation()
        copiedEntries += 1
        guard depth <= 512, copiedEntries <= 1_000_000,
              SendToFilesystem.identity(attributes).dev == rootDevice else {
            throw SendToCoreError.rejected("目录过深、条目过多或包含其它挂载卷，已停止本项：\(path)")
        }
        emit(path, force: depth == 0)
        if SendToFilesystem.kind(attributes) == .directory {
            guard mkdirat(parent, name, 0o700) == 0 else {
                throw SendToCoreError.system("创建复制目录失败", path, errno)
            }
            let output = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard output >= 0 else {
                throw SendToCoreError.system("打开复制目录失败", path, errno)
            }
            defer {
                close(output)
            }
            for child in try SendToFilesystem.names(fd: sourceFD, cancel: cancel) {
                try checkCancellation()
                let value = try SendToFilesystem.attributes(parent: sourceFD, name: child)
                let childPath = path + "/" + child
                if value.st_mode & S_IFMT == S_IFLNK {
                    copiedEntries += 1
                    guard copiedEntries <= 1_000_000 else {
                        throw SendToCoreError.rejected("条目超过安全范围。")
                    }
                    try copyLink(parent: sourceFD, name: child, expected: value, output: output, path: childPath)
                    continue
                }
                guard let kind = SendToFilesystem.kind(value) else {
                    throw SendToCoreError.rejected("不复制特殊设备、套接字或管道：\(childPath)")
                }
                let input = openat(sourceFD, child, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC | (kind == .directory ? O_DIRECTORY : 0))
                guard input >= 0 else {
                    throw SendToCoreError.system("打开源子项失败", childPath, errno)
                }
                defer {
                    close(input)
                }
                let opened = try SendToFilesystem.attributes(fd: input)
                guard SendToFilesystem.identity(opened) == SendToFilesystem.identity(value),
                      SendToFilesystem.kind(opened) == kind else {
                    throw SendToCoreError.rejected("源子项身份变化：\(childPath)")
                }
                try copyNode(sourceFD: input, attributes: opened, parent: output,
                             name: child, path: childPath, rootDevice: rootDevice, depth: depth + 1)
                let after = try SendToFilesystem.attributes(parent: sourceFD, name: child)
                guard SendToFilesystem.identity(after) == SendToFilesystem.identity(value) else {
                    throw SendToCoreError.rejected("源子项在复制期间被替换：\(childPath)")
                }
            }
            try copyFile(sourceFD: sourceFD, outputFD: output, path: path, flags: copyfile_flags_t(COPYFILE_METADATA))
        } else {
            let output = openat(parent, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
            guard output >= 0 else {
                throw SendToCoreError.system("创建复制文件失败", path, errno)
            }
            defer {
                close(output)
            }
            try copyFile(sourceFD: sourceFD, outputFD: output, path: path, flags: copyfile_flags_t(COPYFILE_ALL))
        }
        let after = try SendToFilesystem.attributes(fd: sourceFD)
        guard attributes.st_size == after.st_size,
              attributes.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              attributes.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              attributes.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec,
              attributes.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec else {
            throw SendToCoreError.rejected("源对象在复制期间被编辑，本项未发表：\(path)")
        }
    }

    private func copyFile(sourceFD: Int32, outputFD: Int32, path: String, flags: copyfile_flags_t) throws {
        guard let state = copyfile_state_alloc() else {
            throw SendToCoreError.system("无法分配复制状态", path, ENOMEM)
        }
        defer {
            copyfile_state_free(state)
        }
        let context = SendToCopyContext(cancelled: cancel, progress: { self.emit(path) }, dataCheckpoint: dataCheckpoint)
        let pointer = Unmanaged.passUnretained(context).toOpaque()
        let callback = unsafeBitCast(SendToCopyContext.callback, to: UnsafeRawPointer.self)
        guard copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CB), callback) == 0,
              copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CTX), pointer) == 0 else {
            throw SendToCoreError.system("设置可取消复制失败", path, errno)
        }
        let status = withExtendedLifetime(context) {
            fcopyfile(sourceFD, outputFD, state, flags)
        }
        let code = errno
        if let failure = context.firstFailure {
            throw SendToCoreError.system("复制数据或元数据失败", path, failure)
        }
        if context.userCancelled {
            throw SendToCoreError.cancelled
        }
        try checkCancellation()
        guard status == 0 else {
            throw SendToCoreError.system("复制数据或元数据失败", path, code)
        }
    }

    // Interior symlinks retain their link text; their targets are never opened or traversed.
    private func copyLink(parent: Int32, name: String, expected: stat, output: Int32, path: String) throws {
        var bytes = [CChar](repeating: 0, count: Int(PATH_MAX) + 1)
        let length = readlinkat(parent, name, &bytes, bytes.count - 1)
        guard length >= 0, length < bytes.count - 1 else {
            throw SendToCoreError.system("读取符号链接失败", path, errno)
        }
        guard try SendToFilesystem.identity(SendToFilesystem.attributes(parent: parent, name: name)) == SendToFilesystem.identity(expected) else {
            throw SendToCoreError.rejected("符号链接在复制期间变化：\(path)")
        }
        bytes[Int(length)] = 0
        guard symlinkat(bytes, output, name) == 0 else {
            throw SendToCoreError.system("复制符号链接失败", path, errno)
        }
    }

    private func publish(stageFD: Int32, destinationFD: Int32, name: String) throws -> String {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/") else {
            throw SendToCoreError.rejected("所选对象没有可用的文件名。")
        }
        for number in 1...10000 {
            try checkCancellation()
            try SendToFilesystem.validateDestination(destination, fd: destinationFD)
            let candidate = Self.availableName(name, number: number)
            if renameatx_np(stageFD, "payload", destinationFD, candidate, UInt32(RENAME_EXCL)) == 0 {
                return candidate
            }
            let code = errno
            guard code == EEXIST else {
                throw SendToCoreError.system("发表复制结果失败", destination.url.appendingPathComponent(candidate).path, code)
            }
        }
        throw SendToCoreError.rejected("同名副本数量过多，本项未覆盖任何现有对象。")
    }

    static func availableName(_ original: String, number: Int) -> String {
        if number == 1 {
            return original
        }
        let extensionName = (original as NSString).pathExtension
        var stem = extensionName.isEmpty ? original : (original as NSString).deletingPathExtension
        let suffix = " (\(number))" + (extensionName.isEmpty ? "" : "." + extensionName)
        while (stem + suffix).utf8.count > Int(NAME_MAX), !stem.isEmpty {
            stem.removeLast()
        }
        return stem + suffix
    }
}
