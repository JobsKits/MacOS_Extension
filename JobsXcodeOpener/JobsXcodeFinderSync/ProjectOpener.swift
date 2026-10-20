//
//  ProjectOpener.swift
//  JobsXcodeFinderSync
//
//  Created by Jobs on 2026年10月18日，星期日.
//

import AppKit

/// 安装扩展已以 Xcode 为前提；直接交给系统打开项目，路径仅作为独立参数传递。
final class ProjectOpener {
    typealias OpenDocument = (URL, @escaping (Error?) -> Void) -> Void

    private let openDocument: OpenDocument
    private let chooseCandidate: ([URL]) -> URL?
    private let reportFailure: (String, String) -> Void
    private let fileManager: FileManager

    init(
        openDocument: @escaping OpenDocument = ProjectOpener.openWithXcode,
        chooseCandidate: @escaping ([URL]) -> URL? = ProjectOpener.chooseProject,
        reportFailure: @escaping (String, String) -> Void = ProjectOpener.showFailure,
        fileManager: FileManager = .default
    ) {
        self.openDocument = openDocument
        self.chooseCandidate = chooseCandidate
        self.reportFailure = reportFailure
        self.fileManager = fileManager
    }

    func open(_ selectedURL: URL) {
        let didStartAccessing = selectedURL.startAccessingSecurityScopedResource()
        do {
            let candidates = try projectCandidates(from: selectedURL)
            guard !candidates.isEmpty else {
                if didStartAccessing {
                    selectedURL.stopAccessingSecurityScopedResource()
                }
                reportFailure("没有可用的 Xcode 项目", "当前目录需要包含 Xcode 工程、工作区或 Package.swift。")
                return
            }
            let chosenURL = candidates.count == 1 ? candidates.first : chooseCandidate(candidates)
            guard let targetURL = chosenURL, candidates.contains(targetURL) else {
                if didStartAccessing {
                    selectedURL.stopAccessingSecurityScopedResource()
                }
                return
            }
            openDocument(targetURL) { [reportFailure] error in
                if didStartAccessing {
                    selectedURL.stopAccessingSecurityScopedResource()
                }
                if let error {
                    DispatchQueue.main.async {
                        reportFailure("Xcode 未能打开项目", error.localizedDescription)
                    }
                }
            }
        } catch {
            if didStartAccessing {
                selectedURL.stopAccessingSecurityScopedResource()
            }
            reportFailure("无法读取项目位置", error.localizedDescription)
        }
    }

    func projectCandidates(from selectedURL: URL) throws -> [URL] {
        guard selectedURL.isFileURL else {
            throw NSError(domain: "JobsXcodeFinderSync", code: 1, userInfo: [NSLocalizedDescriptionKey: "请选择本地文件或文件夹。"])
        }
        let selectedURL = selectedURL.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: selectedURL.path, isDirectory: &isDirectory) else {
            throw NSError(domain: "JobsXcodeFinderSync", code: 2, userInfo: [NSLocalizedDescriptionKey: "所选文件或文件夹已不存在。"])
        }
        let directoryURL = isDirectory.boolValue ? selectedURL : selectedURL.deletingLastPathComponent()
        return try XcodeProjectDetector.projectCandidates(in: directoryURL, fileManager: fileManager)
    }

    static func openWithXcode(_ targetURL: URL, completion: @escaping (Error?) -> Void) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Xcode", targetURL.path]
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let message = output.isEmpty ? "系统打开命令失败，退出码：\(process.terminationStatus)。" : output
                completion(NSError(domain: "JobsXcodeFinderSync", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: message]))
                return
            }
            completion(nil)
        } catch {
            completion(error)
        }
    }

    static func chooseProject(_ candidates: [URL]) -> URL? {
        guard !candidates.isEmpty else {
            return nil
        }
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "选择要用 Xcode 打开的项目"
        alert.informativeText = "当前文件夹包含多个候选项目，请明确选择一个。"
        let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 420, height: 28), pullsDown: false)
        picker.addItems(withTitles: candidates.map(\.lastPathComponent))
        alert.accessoryView = picker
        alert.addButton(withTitle: "打开所选项目")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn,
              candidates.indices.contains(picker.indexOfSelectedItem) else {
            return nil
        }
        return candidates[picker.indexOfSelectedItem]
    }

    static func showFailure(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}
