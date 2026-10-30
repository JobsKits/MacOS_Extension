//
//  FinderMenuFeatureConfiguration.swift
//  JobsTerminalShared
//
//  Created by Jobs on 2026年9月13日，星期日.
//

import Darwin
import Foundation

enum FinderMenuFeature: String, CaseIterable {
    case open
    case fileContent = "file-content"
    case fileMerge = "file-merge"
    case fileSplit = "file-split"
    case podInstall = "pod-install"
    case flutterPubGet = "flutter-pub-get"
    case cleanBuildArtifacts = "clean-build-artifacts"
    case codeGraphBootstrap = "codegraph-bootstrap"
    case gitEmptyCommitPush = "git-empty-commit-push"

    var configurationTitle: String {
        switch self {
        /// 对任意单个本地文件或文件夹提供终端入口
        case .open:
            return "用终端打开 —— 任意单个本地文件或文件夹"
        case .fileContent:
            return "用终端查看文件内容 —— 单个普通文件，大文件确认后读取"
        /// 仅完整选中同一组分卷时提供合并。
        case .fileMerge:
            return "合并分卷 —— 多选同一完整分卷组"
        /// 仅普通单文件可拆分，原文件始终保留。
        case .fileSplit:
            return "拆分文件 —— 单个普通文件"
        /// 同层存在工程包和 Podfile 时提供原生安装命令
        case .podInstall:
            return "Pod Install 兼容入口 —— 菜单已归入 iOS / CocoaPods 辅助工具"
        /// 仅对合法 Flutter 工程提供依赖拉取入口
        case .flutterPubGet:
            return "在终端执行 flutter pub get —— 合法 Flutter 工程"
        /// 当前 Flutter、Android 或 OpenHarmony 工程的两平台产物清理。
        case .cleanBuildArtifacts:
            return "清理 Android / OpenHarmony 构建产物 —— Flutter、Android 或 OpenHarmony 工程文件夹"
        /// 仅对普通文件夹更新代码地图，缺失工具时在终端确认安装
        case .codeGraphBootstrap:
            return "更新代码地图（.codegraph） —— 普通文件夹，缺失组件时确认安装"
        /// 仅对普通文件夹提供 Git 空白提交并推送入口
        case .gitEmptyCommitPush:
            return "空白 Commit 并 Push 兼容入口 —— 菜单已归入 Git操作"
        }
    }
}

struct FinderMenuFeatureConfiguration {
    static let infoDictionaryKey = "JobsTerminalEnabledFeatures"
    private static let directoryName = "JobsTerminalOpener"
    private static let fileName = "EnabledFinderMenuFeatures.txt"

    static func enabledFeatures(fallbackBundle: Bundle) -> Set<FinderMenuFeature> {
        if let configurationFileURL,
           let configuredValue = try? String(contentsOf: configurationFileURL, encoding: .utf8) {
            return features(from: configuredValue)
        }

        guard let configuredValue = fallbackBundle.object(forInfoDictionaryKey: infoDictionaryKey) as? String else {
            return Set(FinderMenuFeature.allCases).subtracting([.fileMerge, .fileSplit])
        }
        return features(from: configuredValue)
    }

    static func save(_ features: Set<FinderMenuFeature>) throws {
        guard let configurationFileURL else {
            throw NSError(
                domain: "com.jobs.JobsTerminalOpener.FeatureConfiguration",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "无法确定当前用户目录。"]
            )
        }

        let directoryURL = configurationFileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let configuredValue = FinderMenuFeature.allCases
            .filter { features.contains($0) }
            .map(\.rawValue)
            .joined(separator: ",")
        try configuredValue.write(to: configurationFileURL, atomically: true, encoding: .utf8)
    }
}

private extension FinderMenuFeatureConfiguration {
    static var configurationFileURL: URL? {
        guard let passwordEntry = getpwuid(getuid()),
              let homeDirectoryPointer = passwordEntry.pointee.pw_dir else { return nil };return URL(fileURLWithPath: String(cString: homeDirectoryPointer), isDirectory: true)
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    static func features(from configuredValue: String) -> Set<FinderMenuFeature> {
        let configuredIdentifiers = Set(
            configuredValue
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        );return Set(FinderMenuFeature.allCases.filter { configuredIdentifiers.contains($0.rawValue) })
    }
}
