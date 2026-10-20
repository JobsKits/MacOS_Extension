//
//  XcodeProjectDetector.swift
//  JobsIDEProjectDetection
//
//  Created by Jobs on 2026年10月20日，星期二.
//

import Foundation

/// 三个 IDE 扩展使用相同的目录判定，保持菜单互斥且能独立构建。
enum XcodeProjectDetector {
    static func canOpen(_ directoryURL: URL, fileManager: FileManager = .default) -> Bool {
        guard let candidates = try? projectCandidates(in: directoryURL, fileManager: fileManager) else {
            return false
        }
        return !candidates.isEmpty
    }

    static func projectCandidates(in directoryURL: URL, fileManager: FileManager = .default) throws -> [URL] {
        guard directoryURL.isFileURL, isDirectory(directoryURL, fileManager: fileManager) else {
            return []
        }
        let directoryURL = directoryURL.standardizedFileURL
        // Flutter 根目录优先交给 Android Studio / VSCode，即使本层也有原生工程。
        guard !FlutterProjectValidator().isFlutterProject(at: directoryURL.resolvingSymlinksInPath()) else {
            return []
        }
        let projectExtensions = ["xcworkspace", "xcodeproj"]
        if projectExtensions.contains(directoryURL.pathExtension.lowercased()) {
            return isProjectBundle(directoryURL, fileManager: fileManager) ? [directoryURL] : []
        }

        let children = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        // 只检查当前层；Flutter 根目录不会因 ios 子目录被误判为 Xcode 项目。
        for pathExtension in projectExtensions {
            let projects = children.filter { candidate in
                candidate.pathExtension.lowercased() == pathExtension &&
                isProjectBundle(candidate, fileManager: fileManager)
            }.sorted { left, right in
                left.lastPathComponent.localizedStandardCompare(right.lastPathComponent) == .orderedAscending
            }
            if !projects.isEmpty {
                return projects
            }
        }

        let manifestURL = directoryURL.appendingPathComponent("Package.swift")
        return isRegularFile(manifestURL) ? [directoryURL] : []
    }
}

private extension XcodeProjectDetector {
    static func isDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    static func isRegularFile(_ url: URL) -> Bool {
        return (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }

    static func isProjectBundle(_ url: URL, fileManager: FileManager) -> Bool {
        guard isDirectory(url, fileManager: fileManager) else {
            return false
        }
        let marker = url.pathExtension.lowercased() == "xcworkspace" ? "contents.xcworkspacedata" : "project.pbxproj"
        return isRegularFile(url.appendingPathComponent(marker))
    }
}
