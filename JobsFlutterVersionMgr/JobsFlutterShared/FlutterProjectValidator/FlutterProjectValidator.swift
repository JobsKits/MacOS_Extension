//
//  FlutterProjectValidator.swift
//  JobsFlutterShared
//
//  Created by Jobs on 2026年10月19日，星期一.
//

import Foundation

/// 只识别当前真实普通目录的 Flutter SDK 依赖，不递归搜索子目录。
struct FlutterProjectValidator {
    func isFlutterProject(at directoryURL: URL) -> Bool {
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
        return declaresFlutterSDK(in: text)
    }

    /// 保守解析 pubspec 常见块映射与单行 flow 映射；复杂 YAML 留给终端复核。
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
                // 非映射正文通常属于 description 的块字符串；它不能成为依赖入口。
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

    /// 引号和 flow 容器内的分隔符属于数据，不能改变 YAML 层级。
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
