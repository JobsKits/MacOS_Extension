//
//  SendToFilesystem.swift
//  JobsSendToCore
//
//  Created by Jobs on 2026年11月18日，星期三.
//

import Foundation
import Darwin

enum SendToFilesystem {

    static func identity(_ value: stat) -> SendToIdentity {
        return SendToIdentity(dev: UInt64(UInt32(bitPattern: value.st_dev)), ino: value.st_ino)
    }

    static func attributes(_ path: String) throws -> stat {
        guard !path.utf8.contains(0) else {
            throw SendToCoreError.rejected("路径包含空字符。")
        }
        var value = stat()
        guard lstat(path, &value) == 0 else {
            throw SendToCoreError.system("读取对象失败", path, errno)
        }
        return value
    }

    static func attributes(fd: Int32) throws -> stat {
        var value = stat()
        guard fstat(fd, &value) == 0 else {
            throw SendToCoreError.system("读取已打开对象失败", "fd \(fd)", errno)
        }
        return value
    }

    static func attributes(parent: Int32, name: String) throws -> stat {
        var value = stat()
        guard fstatat(parent, name, &value, AT_SYMLINK_NOFOLLOW) == 0 else {
            throw SendToCoreError.system("读取子项失败", name, errno)
        }
        return value
    }

    static func kind(_ value: stat) -> SendToSource.Kind? {
        if value.st_mode & S_IFMT == S_IFREG {
            return .file
        }
        if value.st_mode & S_IFMT == S_IFDIR {
            return .directory
        }
        return nil
    }

    static func realURL(_ url: URL) throws -> URL {
        guard url.isFileURL, url.host == nil || url.host == "" || url.host == "localhost",
              !url.path.utf8.contains(0), let value = realpath(url.path, nil) else {
            throw SendToCoreError.rejected("无法解析本地文件路径：\(url.path)")
        }
        defer {
            free(value)
        }
        return URL(fileURLWithPath: String(cString: value)).standardizedFileURL
    }

    static func openDirectory(_ path: String) throws -> Int32 {
        let fd = Darwin.open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else {
            throw SendToCoreError.system("打开真实目录失败", path, errno)
        }
        return fd
    }

    static func validate(_ source: SendToSource) throws {
        let value = try attributes(source.url.path)
        guard identity(value) == source.identity, kind(value) == source.kind else {
            throw SendToCoreError.rejected("源对象已替换或变成链接：\(source.url.path)")
        }
        let resolved = try realURL(source.url)
        guard resolved.path == source.url.path else {
            throw SendToCoreError.rejected("源目录祖先已变化：\(source.url.path)")
        }
    }

    static func validateDestination(_ destination: SendToVolume, fd: Int32) throws {
        guard (destination.rootURL == nil) == (destination.rootIdentity == nil) else {
            throw SendToCoreError.rejected("目标目录缺少匹配的卷根身份。")
        }
        if let rootURL = destination.rootURL, let rootIdentity = destination.rootIdentity {
            let root = SendToVolume(url: rootURL, name: destination.name, identity: rootIdentity,
                                    isNetwork: destination.isNetwork)
            let selected = try selectedDirectory(root: root, folder: destination.url,
                                                 expectedInode: destination.identity.ino)
            guard selected.identity == destination.identity else {
                throw SendToCoreError.rejected("目标目录身份已变化：\(destination.url.path)")
            }
        }
        let pathValue = try attributes(destination.url.path)
        let openedValue = try attributes(fd: fd)
        guard kind(pathValue) == .directory, identity(pathValue) == destination.identity,
              identity(openedValue) == destination.identity,
              try realURL(destination.url).path == destination.url.path else {
            throw SendToCoreError.rejected("目标卷已卸载、替换或目录祖先已变化：\(destination.url.path)")
        }
        var info = statfs()
        guard fstatfs(fd, &info) == 0 else {
            throw SendToCoreError.system("读取目标卷状态失败", destination.url.path, errno)
        }
        guard UInt64(info.f_flags) & UInt64(MNT_RDONLY) == 0 else {
            throw SendToCoreError.rejected("目标卷为只读：\(destination.url.path)")
        }
    }

    // A folder remains anchored to an enumerated volume; neither symlinks nor nested mounts become devices.
    static func selectedDirectory(root: SendToVolume, folder: URL, expectedInode: UInt64? = nil) throws -> SendToVolume {
        guard root.rootURL == nil, root.rootIdentity == nil, folder.isFileURL,
              folder.standardizedFileURL.path == folder.path else {
            throw SendToCoreError.rejected("请选择当前设备卷内的真实文件夹。")
        }
        let rootPath = root.url.path
        let prefix = rootPath == "/" ? "/" : rootPath + "/"
        guard folder.path == rootPath || folder.path.hasPrefix(prefix) else {
            throw SendToCoreError.rejected("所选文件夹不在当前设备卷内：\(folder.path)")
        }
        let relative = folder.path == rootPath ? "" : String(folder.path.dropFirst(prefix.count))
        let components = relative.isEmpty ? [] : relative.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard components.count <= 512, components.allSatisfy({
            !$0.isEmpty && $0 != "." && $0 != ".." && !$0.utf8.contains(0)
        }) else {
            throw SendToCoreError.rejected("目标目录路径不合法。")
        }
        var current = try openDirectory(rootPath)
        defer {
            close(current)
        }
        try validateDestination(root, fd: current)
        for component in components {
            let child = openat(current, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard child >= 0 else {
                throw SendToCoreError.system("目标文件夹不存在、不可读取或包含链接", folder.path, errno)
            }
            close(current)
            current = child
            guard try identity(attributes(fd: current)).dev == root.identity.dev else {
                throw SendToCoreError.rejected("目标路径进入其它挂载卷，未执行：\(folder.path)")
            }
        }
        let value = try attributes(fd: current)
        let targetIdentity = identity(value)
        guard expectedInode == nil || expectedInode == targetIdentity.ino,
              try realURL(folder).path == folder.path,
              try identity(attributes(folder.path)) == targetIdentity else {
            throw SendToCoreError.rejected("原目标文件夹已替换或路径祖先发生变化：\(folder.path)")
        }
        if components.isEmpty {
            return root
        }
        return SendToVolume(url: folder, name: root.name, identity: targetIdentity, isNetwork: root.isNetwork,
                            rootURL: root.url, rootIdentity: root.identity)
    }

    // Walk actual destination ancestors, so a different path spelling cannot bypass containment.
    static func assertOutsideSources(_ sources: [SendToSource], destination: SendToVolume, fd: Int32) throws {
        let forbidden = Set(sources.filter { $0.kind == .directory }.map(\.identity))
        var current = dup(fd)
        guard current >= 0 else {
            throw SendToCoreError.system("核对目标祖先失败", destination.url.path, errno)
        }
        defer {
            close(current)
        }
        for _ in 0..<1024 {
            let id = try identity(attributes(fd: current))
            guard !forbidden.contains(id) else {
                throw SendToCoreError.rejected("不能将文件夹复制到自身或其内部：\(destination.url.path)")
            }
            let parent = openat(current, "..", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard parent >= 0 else {
                throw SendToCoreError.system("核对目标祖先失败", destination.url.path, errno)
            }
            let parentID: SendToIdentity
            do {
                parentID = try identity(attributes(fd: parent))
            } catch {
                close(parent)
                throw error
            }
            if parentID == id {
                close(parent)
                return
            }
            close(current)
            current = parent
        }
        throw SendToCoreError.rejected("目标目录祖先超出安全核对范围。")
    }

    // Directory streams originate from an existing no-follow descriptor, never reconstructed paths.
    static func names(fd: Int32, cancel: () -> Bool = { false }) throws -> [String] {
        let copy = openat(fd, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard copy >= 0 else {
            throw SendToCoreError.system("复制目录句柄失败", "fd \(fd)", errno)
        }
        guard let directory = fdopendir(copy) else {
            close(copy)
            throw SendToCoreError.system("枚举目录失败", "fd \(fd)", errno)
        }
        defer {
            closedir(directory)
        }
        var result: [String] = []
        errno = 0
        while let entry = readdir(directory) {
            if cancel() {
                throw SendToCoreError.cancelled
            }
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) {
                    String(cString: $0)
                }
            }
            if name != ".", name != ".." {
                result.append(name)
                guard result.count <= 1_000_000 else {
                    throw SendToCoreError.rejected("单个目录条目超过安全范围。")
                }
            }
            errno = 0
        }
        guard errno == 0 else {
            throw SendToCoreError.system("目录枚举不完整", "fd \(fd)", errno)
        }
        return result.sorted()
    }

    // Destructive cleanup is limited to the private staging tree and never follows links.
    static func removePrivateEntry(parent: Int32, name: String, expected: SendToIdentity) throws {
        let before = try attributes(parent: parent, name: name)
        guard identity(before) == expected else {
            throw SendToCoreError.rejected("临时对象身份变化，已保留：\(name)")
        }
        if kind(before) == .directory {
            let fd = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard fd >= 0 else {
                throw SendToCoreError.system("临时目录无法清理，已保留", name, errno)
            }
            defer {
                close(fd)
            }
            guard try identity(attributes(fd: fd)) == expected else {
                throw SendToCoreError.rejected("临时目录已替换，已保留：\(name)")
            }
            for child in try names(fd: fd) {
                let childID = try identity(attributes(parent: fd, name: child))
                try removePrivateEntry(parent: fd, name: child, expected: childID)
            }
        }
        guard try identity(attributes(parent: parent, name: name)) == expected else {
            throw SendToCoreError.rejected("临时对象在清理前已变化，已保留：\(name)")
        }
        guard unlinkat(parent, name, kind(before) == .directory ? AT_REMOVEDIR : 0) == 0 else {
            throw SendToCoreError.system("清理本次临时对象失败，已保留", name, errno)
        }
    }
}
