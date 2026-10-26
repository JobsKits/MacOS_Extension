//
//  SourcetreeProjectOpener.swift
//  JobsProjectTools
//
//  Created by Jobs on 2026年10月26日，星期一.
//

import AppKit

/// 使用应用的打开文档入口传递仓库 URL，支持中文、空格和特殊字符。
struct SourcetreeProjectOpener {
    func open(at selectedURL: URL, completion: @escaping () -> Void) throws {
        guard let repositoryURL = GitRepositoryValidator().workingDirectory(at: selectedURL),
              let applicationURL = SourcetreeApplication.installedURL() else {
            throw OpenError.unavailable
        }
        let configuration = NSWorkspace.OpenConfiguration.make {
            $0.activates = true
        }
        NSWorkspace.shared.open([repositoryURL], withApplicationAt: applicationURL, configuration: configuration) { _, error in
            DispatchQueue.main.async {
                if let error {
                    AppDelegate.showFailure(error.localizedDescription)
                }
                completion()
            }
        }
    }

    private enum OpenError: LocalizedError {
        case unavailable

        var errorDescription: String? {
            return "Sourcetree 已卸载或不可用，或当前目录已不在有效 Git 工作树内。请重新右键。"
        }
    }
}

private extension NSWorkspace.OpenConfiguration {
    static func make(_ configure: (NSWorkspace.OpenConfiguration) -> Void) -> NSWorkspace.OpenConfiguration {
        let configuration = NSWorkspace.OpenConfiguration()
        configure(configuration)
        return configuration
    }
}
