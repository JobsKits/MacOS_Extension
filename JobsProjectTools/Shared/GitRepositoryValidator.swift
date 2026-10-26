//
//  GitRepositoryValidator.swift
//  JobsProjectTools
//
//  Created by Jobs on 2026年10月24日，星期六.
//

import Foundation

/// Finder 同步回调只读检查元数据，兼容子目录、子模块和 linked worktree。
struct GitRepositoryValidator {
    private let fileManager = FileManager.default

    func isWorkingDirectory(at url: URL) -> Bool {
        return workingDirectory(at: url) != nil
    }

    /// 返回最近的有效工作树，避免从子目录打开时选中外层仓库。
    func workingDirectory(at url: URL) -> URL? {
        guard url.isFileURL,
              let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isAliasFileKey, .isPackageKey]),
              values.isDirectory == true,
              values.isSymbolicLink != true,
              values.isAliasFile != true,
              values.isPackage != true else {
            return nil
        }
        var current = url.standardizedFileURL.resolvingSymlinksInPath()
        while true {
            // Git 元数据目录本身不属于工作树；损坏的内层仓库也不能借外层仓库通过。
            guard current.lastPathComponent != ".git" else {
                return nil
            }
            let marker = current.appendingPathComponent(".git")
            if (try? fileManager.attributesOfItem(atPath: marker.path)) != nil {
                return validGitDirectory(marker, relativeTo: current) ? current : nil
            }
            guard !isBareRepositoryMetadata(current) else {
                return nil
            }
            guard current.path != "/" else {
                return nil
            }
            current.deleteLastPathComponent()
        }
    }

    private func isBareRepositoryMetadata(_ directory: URL) -> Bool {
        guard ordinaryDirectory(directory.appendingPathComponent("objects")),
              ordinaryDirectory(directory.appendingPathComponent("refs")),
              let head = smallText(directory.appendingPathComponent("HEAD")), validHead(head),
              let config = smallText(directory.appendingPathComponent("config")) else {
            return false
        }
        var isCoreSection = false
        for line in config.components(separatedBy: .newlines) {
            let value = line.trimmingCharacters(in: .whitespaces).lowercased()
            if value.hasPrefix("[") {
                isCoreSection = value == "[core]"
            } else if isCoreSection {
                let pair = value.split(separator: "=", maxSplits: 1).map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
                if pair.count == 2, pair[0] == "bare", pair[1] == "true" {
                    return true
                }
            }
        }
        return false
    }

    private func validGitDirectory(_ marker: URL, relativeTo root: URL) -> Bool {
        guard let values = try? marker.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]),
              values.isSymbolicLink != true else {
            return false
        }
        let gitDirectory: URL
        if values.isDirectory == true {
            gitDirectory = marker
        } else {
            guard values.isRegularFile == true,
                  let text = smallText(marker),
                  text.hasPrefix("gitdir:"),
                  let resolved = pathURL(String(text.dropFirst(7)), relativeTo: root) else {
                return false
            }
            gitDirectory = resolved
        }
        guard ordinaryDirectory(gitDirectory),
              let head = smallText(gitDirectory.appendingPathComponent("HEAD")),
              validHead(head) else {
            return false
        }
        let commonMarker = gitDirectory.appendingPathComponent("commondir")
        let commonDirectory: URL
        if fileManager.fileExists(atPath: commonMarker.path) {
            guard let text = smallText(commonMarker),
                  let resolved = pathURL(text, relativeTo: gitDirectory) else {
                return false
            }
            commonDirectory = resolved
        } else {
            commonDirectory = gitDirectory
        }
        return ordinaryDirectory(commonDirectory)
            && ordinaryDirectory(commonDirectory.appendingPathComponent("objects"))
            && ordinaryDirectory(commonDirectory.appendingPathComponent("refs"))
            && smallText(commonDirectory.appendingPathComponent("config")) != nil
    }

    private func ordinaryDirectory(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else {
            return false
        }
        return values.isDirectory == true && values.isSymbolicLink != true
    }

    private func smallText(_ url: URL) -> String? {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true,
              values.isSymbolicLink != true,
              (values.fileSize ?? 65_537) <= 65_536,
              let text = try? String(contentsOf: url, encoding: .utf8),
              !text.contains("\0") else {
            return nil
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func pathURL(_ text: String, relativeTo directory: URL) -> URL? {
        let path = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty, !path.contains("\n"), !path.contains("\r"), !path.contains("\0") else {
            return nil
        }
        return (path.hasPrefix("/") ? URL(fileURLWithPath: path, isDirectory: true)
                : directory.appendingPathComponent(path, isDirectory: true)).standardizedFileURL
    }

    private func validHead(_ text: String) -> Bool {
        if text.hasPrefix("ref: refs/") {
            return text.count > 10 && !text.contains("\n") && !text.contains("\r")
        }
        return [40, 64].contains(text.count) && text.utf8.allSatisfy {
            (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
        }
    }
}
