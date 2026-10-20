//
//  PathClipboardWriter.swift
//  JobsPathCopyFinderSync
//
//  Created by Jobs on 2026年6月28日，星期日.
//

import AppKit

struct PathClipboardWriter {
    func copyAbsolutePath(from fileURL: URL) throws -> String {
        let standardizedURL = fileURL.standardizedFileURL
        guard standardizedURL.isFileURL else {
            throw ClipboardError.unsupportedURL(fileURL)
        }

        let path = standardizedURL.path
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(path, forType: .string) else {
            throw ClipboardError.copyFailed(path)
        };return path
    }
}

private extension PathClipboardWriter {
    enum ClipboardError: LocalizedError {
        case unsupportedURL(URL)
        case copyFailed(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedURL(let url):
                return "不是本地文件路径：\(url.absoluteString)"
            case .copyFailed(let path):
                return "写入剪贴板失败：\(path)"
            }
        }
    }
}
