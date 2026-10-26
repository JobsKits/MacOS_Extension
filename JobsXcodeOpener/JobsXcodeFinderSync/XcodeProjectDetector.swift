//
//  XcodeProjectDetector.swift
//  JobsIDEProjectDetection
//
//  Created by Jobs on 2026年10月20日，星期二.
//

import Foundation

/// 三个独立 IDE 及聚合菜单共用同一目录资格；只扫描本层，不把文件归一为父目录。
enum IDEProjectDirectory {
    static func isNonempty(_ url: URL, allowProjectBundle: Bool = false, fileManager: FileManager = .default) -> Bool {
        guard url.isFileURL,
              let attributes = try? fileManager.attributesOfItem(atPath: url.standardizedFileURL.path),
              attributes[.type] as? FileAttributeType == .typeDirectory else {
            return false
        }
        let suffix = url.pathExtension.lowercased()
        if (try? url.resourceValues(forKeys: [.isPackageKey]).isPackage) == true,
           !(allowProjectBundle && ["xcodeproj", "xcworkspace"].contains(suffix)) {
            return false
        }
        if ["app", "bundle", "framework", "xcodeproj", "xcworkspace"].contains(suffix),
           !(allowProjectBundle && ["xcodeproj", "xcworkspace"].contains(suffix)) {
            return false
        }
        guard let names = try? fileManager.contentsOfDirectory(atPath: url.path) else {
            return false
        }
        // Finder / Explorer 自建的目录元数据不构成可编辑的项目内容。
        let metadata = Set([".ds_store", "thumbs.db", "desktop.ini"])
        return names.contains { name in
            return !metadata.contains(name.lowercased())
        }
    }

    static func canOpenInVSCode(_ url: URL, fileManager: FileManager = .default) -> Bool {
        return isNonempty(url, fileManager: fileManager) && XcodeProjectDetector.isConfirmedNonIOS(url, fileManager: fileManager)
    }

    static func canOpenInAndroidStudio(_ url: URL, fileManager: FileManager = .default) -> Bool {
        guard isNonempty(url, fileManager: fileManager) else {
            return false
        }
        if FlutterProjectValidator().isFlutterProject(at: url) {
            return true
        }
        guard XcodeProjectDetector.isConfirmedNonIOS(url, fileManager: fileManager),
              ["settings.gradle", "settings.gradle.kts"].contains(where: { path in
                  return isRegularFile(url.appendingPathComponent(path), fileManager: fileManager)
              }) else {
            return false
        }
        let manifests = ["AndroidManifest.xml", "src/main/AndroidManifest.xml", "app/src/main/AndroidManifest.xml"]
        if manifests.contains(where: { path in
            return isRegularFile(url.appendingPathComponent(path), fileManager: fileManager)
        }) {
            return true
        }
        return ["build.gradle", "build.gradle.kts", "app/build.gradle", "app/build.gradle.kts"].contains { path in
            guard let text = textFile(url.appendingPathComponent(path), fileManager: fileManager) else {
                return false
            }
            let plugins = text.replacingOccurrences(of: #"/\*[\s\S]*?\*/|(?m)^\s*//.*$"#, with: "", options: .regularExpression)
            return plugins.range(of: #"["']com\.android\.(application|library|dynamic-feature|test)["']"#, options: .regularExpression) != nil
        }
    }

    static func isRegularFile(_ url: URL, fileManager: FileManager) -> Bool {
        return (try? fileManager.attributesOfItem(atPath: url.path)[.type]) as? FileAttributeType == .typeRegular
    }

    static func textFile(_ url: URL, fileManager: FileManager) -> String? {
        guard isRegularFile(url, fileManager: fileManager) else {
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}

/// 只将带 iPhone 平台配置的本层工程或明确引用该工程的工作区交给 Xcode。
enum XcodeProjectDetector {
    private static let maximumMetadataBytes = 1_048_576

    static func canOpen(_ directoryURL: URL, fileManager: FileManager = .default) -> Bool {
        guard let candidates = try? projectCandidates(in: directoryURL, fileManager: fileManager) else {
            return false
        }
        return !candidates.isEmpty
    }

    /// 读取或解析失败不等于已确认非 iOS，避免因此把未知项目交给另一个 IDE。
    static func isConfirmedNonIOS(_ directoryURL: URL, fileManager: FileManager = .default) -> Bool {
        if FlutterProjectValidator().isFlutterProject(at: directoryURL) {
            return true
        }
        guard !canOpen(directoryURL, fileManager: fileManager) else {
            return false
        }
        return metadataIsReliable(in: directoryURL, fileManager: fileManager, visited: [])
    }

    static func projectCandidates(in directoryURL: URL, fileManager: FileManager = .default) throws -> [URL] {
        guard IDEProjectDirectory.isNonempty(directoryURL, allowProjectBundle: true, fileManager: fileManager) else {
            return []
        }
        let directoryURL = directoryURL.standardizedFileURL
        // Flutter 官方与鸿蒙根目录都先按有效 Flutter 清单处理；进入其 ios/ 才按原生 iOS 处理。
        guard !FlutterProjectValidator().isFlutterProject(at: directoryURL) else {
            return []
        }
        let suffix = directoryURL.pathExtension.lowercased()
        if ["xcworkspace", "xcodeproj"].contains(suffix) {
            return isIOSBundle(directoryURL, fileManager: fileManager, visited: []) ? [directoryURL] : []
        }
        let children = try fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil, options: [])
        for projectExtension in ["xcworkspace", "xcodeproj"] {
            let projects = children.filter { candidate in
                candidate.pathExtension.lowercased() == projectExtension &&
                isIOSBundle(candidate, fileManager: fileManager, visited: [])
            }.sorted { left, right in
                left.lastPathComponent.localizedStandardCompare(right.lastPathComponent) == .orderedAscending
            }
            if !projects.isEmpty {
                return projects
            }
        }
        // 独立 Swift Package 没有明确的 iOS Xcode target，不在这里猜测为 iOS 工程。
        return []
    }

    private static func metadataIsReliable(in url: URL, fileManager: FileManager, visited: Set<String>) -> Bool {
        guard !visited.contains(url.path),
              let names = try? fileManager.contentsOfDirectory(atPath: url.path) else {
            return false
        }
        var visited = visited
        visited.insert(url.path)
        let suffix = url.pathExtension.lowercased()
        if suffix == "xcodeproj" {
            return !names.contains("project.pbxproj") || metadataText(url.appendingPathComponent("project.pbxproj"), fileManager: fileManager) != nil
        }
        if suffix == "xcworkspace" {
            guard names.contains("contents.xcworkspacedata") else {
                return true
            }
            guard let text = metadataText(url.appendingPathComponent("contents.xcworkspacedata"), fileManager: fileManager),
                  let data = text.data(using: .utf8) else {
                return false
            }
            let references = WorkspaceProjectReferences(directoryURL: url.deletingLastPathComponent())
            let parser = XMLParser.make(data: data)
            parser.delegate = references
            guard parser.parse(), !references.hasUnresolvedReference else {
                return false
            }
            return references.urls.filter { candidate in
                return ["xcodeproj", "xcworkspace"].contains(candidate.pathExtension.lowercased())
            }.allSatisfy { candidate in
                let marker = candidate.pathExtension.lowercased() == "xcodeproj" ? "project.pbxproj" : "contents.xcworkspacedata"
                guard fileManager.fileExists(atPath: candidate.appendingPathComponent(marker).path) else {
                    return false
                }
                return metadataIsReliable(in: candidate, fileManager: fileManager, visited: visited)
            }
        }
        return names.filter { name in
            return ["xcodeproj", "xcworkspace"].contains(URL(fileURLWithPath: name).pathExtension.lowercased())
        }.allSatisfy { name in
            let candidate = url.appendingPathComponent(name)
            guard let attributes = try? fileManager.attributesOfItem(atPath: candidate.path),
                  let type = attributes[.type] as? FileAttributeType else {
                return false
            }
            // 同后缀的普通文件不构成工程元数据；链接或不可读的工程目录不作非 iOS 推断。
            if type == .typeRegular {
                return true
            }
            guard type == .typeDirectory else {
                return false
            }
            return metadataIsReliable(in: candidate, fileManager: fileManager, visited: visited)
        }
    }

    private static func metadataText(_ url: URL, fileManager: FileManager) -> String? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber,
              size.intValue <= maximumMetadataBytes,
              let text = IDEProjectDirectory.textFile(url, fileManager: fileManager),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return text
    }

    private static func isIOSBundle(_ url: URL, fileManager: FileManager, visited: Set<String>) -> Bool {
        guard IDEProjectDirectory.isNonempty(url, allowProjectBundle: true, fileManager: fileManager),
              !visited.contains(url.path) else {
            return false
        }
        var visited = visited
        visited.insert(url.path)
        if url.pathExtension.lowercased() == "xcodeproj" {
            guard let source = metadataText(url.appendingPathComponent("project.pbxproj"), fileManager: fileManager) else {
                return false
            }
            let settings = source.replacingOccurrences(of: #"/\*[\s\S]*?\*/|(?m)^\s*//.*$"#, with: "", options: .regularExpression)
            return settings.range(of: #"\bSDKROOT\s*=\s*"?iphone(?:os|simulator)"?\s*;"#, options: .regularExpression) != nil ||
                settings.range(of: #"\bSUPPORTED_PLATFORMS\s*=\s*(?:"[^";]*\biphone(?:os|simulator)\b[^";]*"|\([^;]*\biphone(?:os|simulator)\b[^;]*\)|iphone(?:os|simulator))\s*;"#, options: .regularExpression) != nil
        }
        guard url.pathExtension.lowercased() == "xcworkspace",
              let text = metadataText(url.appendingPathComponent("contents.xcworkspacedata"), fileManager: fileManager),
              let data = text.data(using: .utf8) else {
            return false
        }
        let references = WorkspaceProjectReferences(directoryURL: url.deletingLastPathComponent())
        let parser = XMLParser.make(data: data)
        parser.delegate = references
        guard parser.parse(), !references.hasUnresolvedReference else {
            return false
        }
        return references.urls.contains { candidate in
            isIOSBundle(candidate, fileManager: fileManager, visited: visited)
        }
    }
}

private final class WorkspaceProjectReferences: NSObject, XMLParserDelegate {
    var urls: [URL] = []
    var hasUnresolvedReference = false
    private let containerURL: URL
    private var groups: [URL?]

    init(directoryURL: URL) {
        containerURL = directoryURL
        groups = [directoryURL]
        super.init()
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        if elementName == "Group" {
            if let location = attributeDict["location"] {
                groups.append(resolve(location))
            } else {
                groups.append(groups.last!)
            }
        } else if elementName == "FileRef" {
            if let location = attributeDict["location"], let url = resolve(location) {
                urls.append(url)
            } else {
                hasUnresolvedReference = true
            }
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "Group", groups.count > 1 {
            groups.removeLast()
        }
    }

    private func resolve(_ location: String) -> URL? {
        let parts = location.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else {
            return nil
        }
        let path = String(parts[1])
        switch parts[0] {
        /// 组内引用相对于其显式父 Group 位置。
        case "group":
            return groups.last?.flatMap { parent in
                return parent.appendingPathComponent(path).standardizedFileURL
            }
        /// container 始终相对于工作区目录。
        case "container":
            return containerURL.appendingPathComponent(path).standardizedFileURL
        /// 绝对引用仍须由上层验证是真实 iOS 工程。
        case "absolute":
            return path.hasPrefix("/") ? URL(fileURLWithPath: path).standardizedFileURL : nil
        /// 不猜测未知动态引用。
        default:
            return nil
        }
    }
}

private extension XMLParser {
    static func make(data: Data) -> XMLParser {
        return XMLParser(data: data)
    }
}
