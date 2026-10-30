//
//  FileCreationService.swift
//  JobsFileCreator
//
//  Created by Jobs on 2026年10月29日，星期四.
//

import Foundation
import Darwin

struct FileCreationService {

    enum Failure: LocalizedError {

        case invalidName
        case invalidDirectory
        case occupied
        case fileSystem(Int32)

        var errorDescription: String? {
            switch self {
            case .invalidName:
                return "请输入有效文件名；不能使用空白名称、/、:、换行或 .、..。"
            case .invalidDirectory:
                return "目标文件夹不存在或当前不可访问，请重新打开 Finder 后重试。"
            case .occupied:
                return "同名文件、文件夹或链接已经存在，请换一个文件名。"
            case .fileSystem(let code):
                return "无法新建文件：\(String(cString: strerror(code)))。请检查文件夹的写入权限和剩余空间。"
            }
        }
    }

    static func validate(name: String) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name != ".",
              name != "..",
              !name.contains("/"),
              !name.contains(":"),
              !name.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0) || CharacterSet.newlines.contains($0)
              }) else {
            throw Failure.invalidName
        }
    }

    func create(name: String,
                in directoryURL: URL) throws -> URL {
        try Self.validate(name: name)
        guard let directory = FileCreationContext.directory(isContainer: true,
                                                            targetedURL: directoryURL) else {
            throw Failure.invalidDirectory
        }
        let directoryDescriptor = Darwin.open(directory.path,
                                              O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard directoryDescriptor >= 0 else {
            throw Failure.fileSystem(errno)
        }
        defer {
            Darwin.close(directoryDescriptor)
        }
        // 以目录描述符排他创建；同名对象即使是悬空链接也不覆盖。
        let descriptor = Darwin.openat(directoryDescriptor,
                                        name,
                                        O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                                        mode_t(0o666))
        guard descriptor >= 0 else {
            let code = errno
            if code == EEXIST {
                throw Failure.occupied
            }
            throw Failure.fileSystem(code)
        }
        guard Darwin.close(descriptor) == 0 else {
            throw Failure.fileSystem(errno)
        }
        return directory.appendingPathComponent(name,
                                                isDirectory: false)
    }
}
