//
//  DependencyProjectValidator.swift
//  JobsTerminalShared
//
//  Created by Jobs on 2026年9月13日，星期日.
//

import Foundation

/// 新工程类型必须同时补充菜单识别、终端清理白名单及两端一致性测试。
enum BuildArtifactProjectKind: String {
    case flutter = "Flutter"
    case harmony = "OpenHarmony"
    case android = "Android"
    case ios = "iOS/Xcode"

    var menuTitle: String { "清理\(rawValue)构建产物" }

    var supportsAndroidOpenHarmonyCleanup: Bool {
        self == .flutter || self == .android || self == .harmony
    }
}

struct DependencyProjectValidator {
    private let fileManager = FileManager.default

    func isCocoaPodsProject(at directoryURL: URL) -> Bool {
        guard isOrdinaryDirectory(directoryURL),
              isRegularFile(directoryURL.appendingPathComponent("Podfile")),
              let childURLs = try? fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: []
              ) else {
            return false
        }

        return childURLs.contains { childURL in
            guard childURL.pathExtension.lowercased() == "xcodeproj",
                  let values = try? childURL.resourceValues(forKeys: [.isDirectoryKey]),
                  values.isDirectory == true else {
                return false
            }
            return true
        }
    }

    func isFlutterProject(at directoryURL: URL) -> Bool {
        guard isOrdinaryDirectory(directoryURL),
              isOrdinaryDirectory(directoryURL.appendingPathComponent("lib", isDirectory: true)) else { return false }

        return isFlutterToolsProject(at: directoryURL)
    }

    /// 两平台与完整 Flutter 清理共用清单边界，不要求已创建 lib。
    func isFlutterToolsProject(at directoryURL: URL) -> Bool {
        guard directoryURL.isFileURL,
              let directory = try? directoryURL.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey, .isAliasFileKey]),
              directory.isDirectory == true,
              directory.isPackage != true,
              directory.isSymbolicLink != true,
              directory.isAliasFile != true else {
            return false
        }
        let manifestURL = directoryURL.appendingPathComponent("pubspec.yaml")
        guard let manifest = try? manifestURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              manifest.isRegularFile == true,
              manifest.isSymbolicLink != true,
              (manifest.fileSize ?? 0) <= 1_048_576,
              let data = try? Data(contentsOf: manifestURL),
              let text = String(data: data, encoding: .utf8) else {
            return false
        }
        return TerminalFlutterManifestParser().declaresFlutterSDK(in: text)
    }

    func isCodeGraphTargetFolder(at directoryURL: URL) -> Bool {
        isOrdinaryDirectory(directoryURL)
    }

    func isBuildArtifactTargetFolder(at directoryURL: URL) -> Bool {
        buildArtifactProjectKind(at: directoryURL) != nil
    }

    func isAndroidOpenHarmonyBuildArtifactTargetFolder(at directoryURL: URL) -> Bool {
        buildArtifactProjectKind(at: directoryURL)?.supportsAndroidOpenHarmonyCleanup == true
    }

    /// 只识别所选目录；Flutter 根目录优先，平台子目录单独选中时按平台识别。
    /// 与 CleanBuildArtifacts.zsh 保持一致，不执行工程脚本或构建工具。
    func buildArtifactProjectKind(at directoryURL: URL) -> BuildArtifactProjectKind? {
        guard directoryURL.isFileURL, isOrdinaryDirectory(directoryURL),
              buildArtifactDirectory(directoryURL) else { return nil }
        let root = directoryURL.resolvingSymlinksInPath().standardizedFileURL
        guard root.path != "/", root != fileManager.homeDirectoryForCurrentUser.resolvingSymlinksInPath() else { return nil }
        if isFlutterToolsProject(at: root) {
            return .flutter
        }
        if buildArtifactHarmonyProject(root) { return .harmony }
        if buildArtifactAndroidProject(root) { return .android }
        for project in buildArtifactChildren(root) where project.pathExtension == "xcodeproj" {
            if buildArtifactText(project.appendingPathComponent("project.pbxproj"), matches:
                #"(SDKROOT[ \t]*=[ \t]*"?iphone(os|simulator)|IPHONEOS_DEPLOYMENT_TARGET[ \t]*=|SUPPORTED_PLATFORMS[ \t]*=.*iphone)"#) {
                return .ios
            }
        }
        return nil
    }

    func isGitEmptyCommitPushTargetFolder(at directoryURL: URL) -> Bool {
        isOrdinaryDirectory(directoryURL)
    }
}

/// 与 FlutterProjectValidator 使用同一清单解析，避免 Flutter 根目录回退为原生清理。
private struct TerminalFlutterManifestParser {
    func declaresFlutterSDK(in text: String) -> Bool {
        guard !text.utf8.contains(0) else {
            return false
        }
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var entries: [(indent: Int, key: String, value: String)] = []
        for rawLine in lines {
            let line = rawLine.hasPrefix("\u{FEFF}") ? String(rawLine.dropFirst()) : rawLine
            let indent = line.prefix(while: { $0 == " " }).count
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }
            if trimmed == "---" || trimmed == "..." || line.prefix(while: { $0.isWhitespace }).contains("\t") {
                return false
            }
            guard let pair = mappingPair(String(line.dropFirst(indent))) else {
                entries.append((indent, "", ""))
                continue
            }
            entries.append((indent, pair.key, pair.value))
        }
        let roots = entries.indices.filter { entries[$0].indent == 0 && entries[$0].key == "dependencies" }
        guard roots.count == 1, let root = roots.first else {
            return false
        }
        let rootEntry = entries[root]
        if !rootEntry.value.isEmpty {
            guard let dependencies = flowMapping(rootEntry.value),
                  let flutter = dependencies["flutter"],
                  let flutterMap = flowMapping(flutter),
                  let sdk = flutterMap["sdk"] else {
                return false
            }
            return scalar(sdk) == "flutter"
        }
        let end = entries.indices.first { $0 > root && entries[$0].indent == 0 } ?? entries.endIndex
        let children = Array(entries[(root + 1)..<end])
        guard let dependencyIndent = children.map(\.indent).min(), dependencyIndent > 0 else {
            return false
        }
        let flutterPositions = children.indices.filter { children[$0].indent == dependencyIndent && children[$0].key == "flutter" }
        guard flutterPositions.count == 1, let flutterIndex = flutterPositions.first else {
            return false
        }
        let flutterEntry = children[flutterIndex]
        if !flutterEntry.value.isEmpty {
            guard let map = flowMapping(flutterEntry.value), let sdk = map["sdk"] else {
                return false
            }
            return scalar(sdk) == "flutter"
        }
        let flutterEnd = children.indices.first { $0 > flutterIndex && children[$0].indent <= dependencyIndent } ?? children.endIndex
        let fields = Array(children[(flutterIndex + 1)..<flutterEnd])
        guard let sdkIndent = fields.map(\.indent).min(), sdkIndent > dependencyIndent else {
            return false
        }
        let sdkFields = fields.filter { $0.indent == sdkIndent && $0.key == "sdk" }
        return sdkFields.count == 1 && scalar(sdkFields[0].value) == "flutter"
    }

    private func mappingPair(_ source: String) -> (key: String, value: String)? {
        guard let clean = uncomment(source), let colon = delimiter(in: clean, character: ":") else {
            return nil
        }
        let keyText = String(clean[..<colon]).trimmingCharacters(in: .whitespaces)
        guard let key = scalar(keyText), !key.isEmpty else {
            return nil
        }
        let value = String(clean[clean.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        return (key, value)
    }

    private func flowMapping(_ source: String) -> [String: String]? {
        let source = source.trimmingCharacters(in: .whitespaces)
        guard source.first == "{", source.last == "}" else {
            return nil
        }
        var remaining = String(source.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        var result: [String: String] = [:]
        while !remaining.isEmpty {
            let comma = delimiter(in: remaining, character: ",")
            let part = comma.map { String(remaining[..<$0]) } ?? remaining
            guard let pair = mappingPair(part), result[pair.key] == nil, !pair.value.isEmpty else {
                return nil
            }
            result[pair.key] = pair.value
            guard let comma else {
                break
            }
            remaining = String(remaining[remaining.index(after: comma)...]).trimmingCharacters(in: .whitespaces)
        }
        return result
    }

    private func scalar(_ source: String) -> String? {
        let source = source.trimmingCharacters(in: .whitespaces)
        guard !source.isEmpty else {
            return nil
        }
        if source.first == "\"" {
            guard let data = source.data(using: .utf8),
                  let value = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? String else {
                return nil
            }
            return value
        }
        if source.first == "'" {
            guard source.count >= 2, source.last == "'" else {
                return nil
            }
            let body = String(source.dropFirst().dropLast())
            guard !body.replacingOccurrences(of: "''", with: "").contains("'") else {
                return nil
            }
            return body.replacingOccurrences(of: "''", with: "'")
        }
        guard source.rangeOfCharacter(from: CharacterSet(charactersIn: "{}[],:#&*!|>\"'")) == nil else {
            return nil
        }
        return source
    }

    private func uncomment(_ source: String) -> String? {
        guard let hash = delimiter(in: source, character: "#", comments: true) else {
            return source
        }
        return String(source[..<hash]).trimmingCharacters(in: .whitespaces)
    }

    private func delimiter(in source: String, character: Character, comments: Bool = false) -> String.Index? {
        var quote: Character?
        var depth = 0
        var escaped = false
        var index = source.startIndex
        while index < source.endIndex {
            let current = source[index]
            if let activeQuote = quote {
                if activeQuote == "\"" && current == "\\" && !escaped {
                    escaped = true
                    index = source.index(after: index)
                    continue
                }
                if current == activeQuote && !escaped {
                    let next = source.index(after: index)
                    if activeQuote == "'" && next < source.endIndex && source[next] == "'" {
                        index = source.index(after: next)
                        continue
                    }
                    quote = nil
                }
                escaped = false
            } else if current == "\"" || current == "'" {
                quote = current
            } else if current == character && depth == 0 {
                if !comments || index == source.startIndex || source[source.index(before: index)].isWhitespace {
                    return index
                }
            } else if current == "{" || current == "[" {
                depth += 1
            } else if current == "}" || current == "]" {
                depth -= 1
            }
            index = source.index(after: index)
        }
        return nil
    }
}

private extension DependencyProjectValidator {
    func buildArtifactDirectory(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return false }
        return values.isDirectory == true && values.isSymbolicLink != true
    }

    func buildArtifactFile(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { return false }
        return values.isRegularFile == true && values.isSymbolicLink != true
    }

    func buildArtifactText(_ url: URL, matches pattern: String, stripComments: Bool = false) -> Bool {
        guard buildArtifactFile(url), var text = try? String(contentsOf: url, encoding: .utf8) else { return false }
        if stripComments {
            text = text.replacingOccurrences(of: #"(?s)/\*.*?\*/"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"//[^\n]*"#, with: "", options: .regularExpression)
        }
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    func buildArtifactChildren(_ url: URL) -> [URL] {
        let children = (try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [])) ?? []
        return children.filter { !$0.lastPathComponent.hasPrefix(".") && buildArtifactDirectory($0) }
    }

    func buildArtifactHasAnyFile(_ directory: URL, _ names: [String]) -> Bool {
        names.contains { buildArtifactFile(directory.appendingPathComponent($0)) }
    }

    func buildArtifactHarmonyProject(_ root: URL) -> Bool {
        buildArtifactHasAnyFile(root, ["hvigorfile.ts", "hvigorfile.js"]) &&
            buildArtifactFile(root.appendingPathComponent("build-profile.json5")) &&
            buildArtifactFile(root.appendingPathComponent("oh-package.json5")) &&
            (buildArtifactFile(root.appendingPathComponent("AppScope/app.json5")) ||
             buildArtifactFile(root.appendingPathComponent("src/main/module.json5")))
    }

    func buildArtifactAndroidProject(_ root: URL) -> Bool {
        let gradleFiles = ["build.gradle", "build.gradle.kts"]
        let settingsFiles = ["settings.gradle", "settings.gradle.kts"]
        guard buildArtifactHasAnyFile(root, gradleFiles + settingsFiles) else { return false }
        let excluded: Set<String> = ["build", "node_modules", "oh_modules", "Pods", "vendor", "third_party", "DerivedData"]
        var pending = [root]
        while let directory = pending.popLast() {
            if buildArtifactHasAnyFile(directory, gradleFiles) {
                if buildArtifactFile(directory.appendingPathComponent("src/main/AndroidManifest.xml")) { return true }
                if gradleFiles.contains(where: { buildArtifactText(directory.appendingPathComponent($0), matches:
                    #"com\.android\.(application|library|test|dynamic-feature|asset-pack)"#, stripComments: true) }) { return true }
            }
            pending += buildArtifactChildren(directory).filter { child in
                !excluded.contains(child.lastPathComponent) && !["xcodeproj", "xcworkspace"].contains(child.pathExtension) &&
                    !fileManager.fileExists(atPath: child.appendingPathComponent(".git").path) &&
                    !fileManager.fileExists(atPath: child.appendingPathComponent("pubspec.yaml").path) &&
                    !buildArtifactHasAnyFile(child, settingsFiles) && !buildArtifactHarmonyProject(child)
            }
        }
        return false
    }

    func isOrdinaryDirectory(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey]) else { return false };return values.isDirectory == true && values.isPackage != true
    }

    func isRegularFile(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]) else { return false };return values.isRegularFile == true
    }
}
