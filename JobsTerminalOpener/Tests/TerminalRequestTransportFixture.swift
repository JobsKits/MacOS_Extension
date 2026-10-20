//
//  TerminalRequestTransportFixture.swift
//  JobsTerminalOpenerTests
//
//  Created by Jobs on 2026年10月18日，星期日.
//

import Foundation

/// 配合 Ruby PTY 回归编译真实 TerminalOpener；从不启动真实 Terminal 或 osascript。
@main
enum TerminalRequestTransportFixture {
    private static let fileManager = FileManager.default

    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count >= 3 else {
            throw failure("需要 mode 和 target 参数")
        }
        let mode = arguments[1]
        let target = URL(fileURLWithPath: arguments[2], isDirectory: true)
        let action = arguments.count > 3 ? TerminalOpener.Action(rawValue: arguments[3]) ?? .podInstall : .podInstall

        switch mode {
        /// 创建真实请求，后续由 Ruby 的隔离交互 Shell 执行。
        case "prepare":
            let request = try TerminalOpener().prepareTerminalRequest(directoryURL: target, action: action)
            try emit(requestDictionary(request))
        /// 模拟 AppleScript 发送成功或失败，检查载体生命周期。
        case "dispatch-success", "dispatch-failure":
            var capturedScript = ""
            var capturedCommand = ""
            var scriptsDuringDispatch: [String] = []
            var didThrow = false
            let opener = TerminalOpener(executeAppleScript: { script, command in
                capturedScript = script
                capturedCommand = command
                scriptsDuringDispatch = preparedScripts().filter {
                    commandTargetsScript(command, path: $0)
                }
                if mode == "dispatch-failure" {
                    throw failure("模拟 AppleScript 请求失败")
                }
            })
            do {
                try opener.openDirectoryInTerminal(target, action: action)
            } catch {
                didThrow = true
            }
            try emit([
                "appleScript": capturedScript,
                "commandLine": capturedCommand,
                "scriptsDuringDispatch": scriptsDuringDispatch,
                "scriptsAfterDispatch": scriptsDuringDispatch.filter { fileManager.fileExists(atPath: $0) },
                "didThrow": didThrow
            ])
        /// 两个实例必须有独立目录，多次清理一个实例不能影响另一个。
        case "concurrency":
            let opener = TerminalOpener()
            let first = try opener.prepareTerminalRequest(directoryURL: target, action: action)
            let second = try opener.prepareTerminalRequest(directoryURL: target, action: action)
            opener.cleanupPreparedTerminalRequest(first)
            opener.cleanupPreparedTerminalRequest(first)
            let secondSurvives = second.scriptURL.map { fileManager.fileExists(atPath: $0.path) } ?? false
            let firstRemoved = first.runtimeDirectoryURL.map { !fileManager.fileExists(atPath: $0.path) } ?? false
            opener.cleanupPreparedTerminalRequest(second)
            let secondRemoved = second.runtimeDirectoryURL.map { !fileManager.fileExists(atPath: $0.path) } ?? false
            try emit([
                "differentDirectories": first.runtimeDirectoryURL != second.runtimeDirectoryURL,
                "firstRemoved": firstRemoved,
                "secondSurvivesFirstCleanup": secondSurvives,
                "secondRemoved": secondRemoved
            ])
        /// 无资格工程必须在创建文件和请求 Terminal 之前被验证器拒绝。
        case "invalid-pod":
            let existingScripts = Set(preparedScripts())
            var dispatchCount = 0
            let opener = TerminalOpener(executeAppleScript: { _, _ in
                dispatchCount += 1
            })
            var didThrow = false
            do {
                _ = try opener.openTerminal(from: target, action: .podInstall)
            } catch {
                didThrow = true
            }
            try emit([
                "didThrow": didThrow,
                "dispatchCount": dispatchCount,
                "preparedScripts": preparedScripts().filter { !existingScripts.contains($0) }
            ])
        /// 未知模式只返回错误，不执行任何系统请求。
        default:
            throw failure("未知 mode：\(mode)")
        }
    }

    private static func requestDictionary(_ request: TerminalOpener.PreparedTerminalRequest) -> [String: Any] {
        [
            "commandLine": request.commandLine,
            "scriptPath": request.scriptURL?.path as Any? ?? NSNull(),
            "runtimeDirectory": request.runtimeDirectoryURL?.path as Any? ?? NSNull()
        ]
    }

    private static func preparedScripts() -> [String] {
        guard let directories = try? fileManager.contentsOfDirectory(
            at: fileManager.temporaryDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return directories.compactMap { directory in
            guard directory.lastPathComponent.hasPrefix("JobsTerminalOpener-"),
                  (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                return nil
            }
            let script = directory.appendingPathComponent("action.zsh")
            return fileManager.fileExists(atPath: script.path) ? script.path : nil
        }.sorted()
    }

    private static func emit(_ value: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    private static func commandTargetsScript(_ command: String, path: String) -> Bool {
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        let candidates = [path, resolved].flatMap { candidate in
            candidate.hasPrefix("/private/var/") ? [candidate, String(candidate.dropFirst("/private".count))] : [candidate]
        }
        return candidates.contains { candidate in
            command == "/bin/zsh \(TerminalOpener().terminalShellWord(candidate))"
        }
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "TerminalRequestTransportFixture", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
