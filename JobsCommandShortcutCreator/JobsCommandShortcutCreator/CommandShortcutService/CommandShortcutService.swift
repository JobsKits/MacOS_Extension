//
//  CommandShortcutService.swift
//  JobsCommandShortcutCreator
//
//  Created by Jobs on 2026年11月13日，星期五.
//

import Foundation
import Darwin

struct CommandShortcutService {

    enum Failure: LocalizedError {
        case invalidName
        case invalidDirectory
        case occupied
        case fileSystem(Int32)

        var errorDescription: String? {
            switch self {
            case .invalidName:
                return CommandShortcutLocalization.text("invalidName")
            case .invalidDirectory:
                return CommandShortcutLocalization.text("invalidTarget")
            case .occupied:
                return CommandShortcutLocalization.text("occupied")
            case .fileSystem(let code):
                return CommandShortcutLocalization.text("writeFailed") + "\n" + String(cString: strerror(code))
            }
        }
    }

    static func validate(name: String) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name != ".command",
              name.hasSuffix(".command"),
              !name.contains("/"),
              !name.contains(":"),
              name.utf8.count <= 255,
              !name.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0) || CharacterSet.newlines.contains($0)
              }) else {
            throw Failure.invalidName
        }
    }

    static func quoted(_ value: String) -> String {
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func content(packageName: String) -> String {
        let package = quoted("./" + packageName)
        let target = quoted("./" + packageName + "/" + packageName)
        return """
        #!/bin/zsh
        # 脚本自述：相对路径转交同级功能包，保留参数与退出码；由原脚本负责业务确认。
        # shell: zsh

        SHORTCUT_SOURCE="${(%):-%x}"
        TARGET_DIRECTORY=\(package)
        TARGET_SCRIPT=\(target)

        launch_companion() {
          setopt NO_NOMATCH
          local shortcut_directory="${SHORTCUT_SOURCE:A:h}"
          cd -- "$shortcut_directory" || return 1
          if [[ ! -d "$TARGET_DIRECTORY" || -L "$TARGET_DIRECTORY" || ! -f "$TARGET_SCRIPT" || -L "$TARGET_SCRIPT" ]]; then
            print -u2 -r -- "✖ 找不到有效的配套脚本 / Companion script unavailable: $TARGET_SCRIPT"
            return 1
          fi
          # 按原 shebang 选择系统 Shell，不修改原文件权限。
          local first_line
          local -a interpreter
          IFS= read -r first_line < "$TARGET_SCRIPT"
          first_line="${first_line%$'\\r'}"
          case "$first_line" in
            '#!/bin/zsh'|'#!/usr/bin/zsh'|'#!/usr/bin/env zsh') interpreter=(/bin/zsh) ;;
            '#!/bin/bash'|'#!/usr/bin/env bash') interpreter=(/bin/bash) ;;
            '#!/bin/sh'|'#!/usr/bin/env sh') interpreter=(/bin/sh) ;;
            *)
              if [[ -x "$TARGET_SCRIPT" ]]; then
                exec "$TARGET_SCRIPT" "$@"
              fi
              print -u2 -r -- "✖ 无法解析脚本解释器，请先授予原脚本执行权限 / Grant execute permission to the source script: $TARGET_SCRIPT"
              return 1
              ;;
          esac
          exec "${interpreter[@]}" "$TARGET_SCRIPT" "$@"
        }

        main() {
          launch_companion "$@"
        }

        main "$@"

        """
    }

    func create(name: String,
                in directoryURL: URL) throws -> URL {
        try Self.validate(name: name)
        guard let directory = CommandShortcutContext.directory(isContainer: true,
                                                                 targetedURL: directoryURL) else {
            throw Failure.invalidDirectory
        }
        let parent = directory.deletingLastPathComponent()
        var parentSnapshot = stat()
        var packageSnapshot = stat()
        var scriptSnapshot = stat()
        guard fstatat(AT_FDCWD, parent.path, &parentSnapshot, 0) == 0,
              Darwin.lstat(directory.path, &packageSnapshot) == 0,
              Darwin.lstat(directory.appendingPathComponent(directory.lastPathComponent).path, &scriptSnapshot) == 0,
              packageSnapshot.st_mode & S_IFMT == S_IFDIR,
              scriptSnapshot.st_mode & S_IFMT == S_IFREG else {
            throw Failure.invalidDirectory
        }
        let parentFD = Darwin.open(parent.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard parentFD >= 0 else {
            throw Failure.fileSystem(errno)
        }
        defer {
            Darwin.close(parentFD)
        }
        var openedParent = stat()
        guard fstat(parentFD, &openedParent) == 0,
              openedParent.st_dev == parentSnapshot.st_dev,
              openedParent.st_ino == parentSnapshot.st_ino else {
            throw Failure.invalidDirectory
        }
        // 固定所选包身份，再通过同一父目录描述符独占创建，避免覆盖任何同名对象。
        let packageFD = Darwin.openat(parentFD, directory.lastPathComponent,
                                      O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard packageFD >= 0 else {
            throw Failure.invalidDirectory
        }
        defer {
            Darwin.close(packageFD)
        }
        var sourceInfo = stat()
        var openedPackage = stat()
        guard fstatat(packageFD, directory.lastPathComponent, &sourceInfo, AT_SYMLINK_NOFOLLOW) == 0,
              fstat(packageFD, &openedPackage) == 0,
              openedPackage.st_dev == packageSnapshot.st_dev,
              openedPackage.st_ino == packageSnapshot.st_ino,
              sourceInfo.st_mode & S_IFMT == S_IFREG,
              sourceInfo.st_dev == scriptSnapshot.st_dev,
              sourceInfo.st_ino == scriptSnapshot.st_ino else {
            throw Failure.invalidDirectory
        }
        let descriptor = Darwin.openat(parentFD, name,
                                        O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                                        mode_t(0o600))
        guard descriptor >= 0 else {
            throw errno == EEXIST ? Failure.occupied : Failure.fileSystem(errno)
        }
        var completed = false
        defer {
            if !completed {
                // 只清理本次创建且仍是同一 inode 的未完成文件。
                var owned = stat()
                var current = stat()
                if fstat(descriptor, &owned) == 0,
                   fstatat(parentFD, name, &current, AT_SYMLINK_NOFOLLOW) == 0,
                   owned.st_dev == current.st_dev,
                   owned.st_ino == current.st_ino {
                    unlinkat(parentFD, name, 0)
                }
            }
            Darwin.close(descriptor)
        }
        let data = Data(Self.content(packageName: directory.lastPathComponent).utf8)
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(descriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR {
                    continue
                }
                guard count > 0 else {
                    throw Failure.fileSystem(count == 0 ? EIO : errno)
                }
                offset += count
            }
        }
        guard fsync(descriptor) == 0,
              fchmod(descriptor, mode_t(0o755)) == 0,
              fsync(descriptor) == 0 else {
            throw Failure.fileSystem(errno)
        }
        var currentParent = stat()
        var currentPackage = stat()
        var currentSource = stat()
        guard fstatat(AT_FDCWD, parent.path, &currentParent, 0) == 0,
              Darwin.lstat(directory.path, &currentPackage) == 0,
              fstatat(packageFD, directory.lastPathComponent, &currentSource, AT_SYMLINK_NOFOLLOW) == 0,
              currentParent.st_dev == parentSnapshot.st_dev,
              currentParent.st_ino == parentSnapshot.st_ino,
              currentPackage.st_dev == packageSnapshot.st_dev,
              currentPackage.st_ino == packageSnapshot.st_ino,
              currentSource.st_dev == scriptSnapshot.st_dev,
              currentSource.st_ino == scriptSnapshot.st_ino else {
            throw Failure.invalidDirectory
        }
        completed = true
        return parent.appendingPathComponent(name, isDirectory: false)
    }
}
