//
//  GitFolderValidator.swift
//  JobsGitPullShared
//
//  Created by Jobs on 2026年10月19日，星期一.
//

import Foundation

/// Finder 仅校验普通文件夹；Git 根、worktree 和运行状态由终端脚本重新核实。
struct GitFolderValidator {
    func isFolder(at url: URL) -> Bool {
        guard url.isFileURL,
              let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              values.isDirectory == true,
              values.isSymbolicLink != true else {
            return false
        }
        return true
    }
}
