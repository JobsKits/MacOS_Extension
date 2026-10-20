//
//  DependencyProjectValidatorTests.swift
//  JobsTerminalOpenerTests
//
//  Created by Jobs on 2026年10月18日，星期日.
//

import Foundation

/// 与真实共享验证器一起编译运行，只在系统临时目录构造文件夹夹具。
@main
enum DependencyProjectValidatorTests {
    private static let fileManager = FileManager.default
    private static let validator = DependencyProjectValidator()
    private static var assertionCount = 0

    static func main() throws {
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("JobsPodValidator-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: root)
        }

        let project = root.appendingPathComponent("工程 空格 ' \" $(touch SHOULD_NOT_EXIST)\n第二行", isDirectory: true)
        try makeProject(at: project)
        try expect(validator.isCocoaPodsProject(at: project), "同层 Podfile 与 Xcode 工程包完整时应允许 Pod 入口")
        try expect(
            !fileManager.fileExists(atPath: project.appendingPathComponent("Demo.xcworkspace").path),
            "首次安装夹具不应预先生成 workspace"
        )

        for combination in 0..<8 {
            let directory = root.appendingPathComponent("存在组合-\(combination)", isDirectory: true)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            for (bit, name) in ["Podfile", "Demo.xcodeproj", "Demo.xcworkspace"].enumerated() {
                if combination & (1 << bit) != 0 {
                    try makeComponent(name, in: directory)
                }
            }
            try expect(
                validator.isCocoaPodsProject(at: directory) == ((combination & 3) == 3),
                "存在组合 \(combination) 应只取决于 Podfile 与 Xcode 工程包"
            )
        }

        for name in ["Podfile", "Demo.xcodeproj"] {
            let component = project.appendingPathComponent(name)
            try fileManager.removeItem(at: component)
            try expect(!validator.isCocoaPodsProject(at: project), "缺少 \(name) 时必须拒绝")
            try makeComponent(name, in: project)
        }

        let projectPackage = project.appendingPathComponent("Demo.xcodeproj")
        try fileManager.removeItem(at: projectPackage)
        try Data("ordinary file".utf8).write(to: projectPackage)
        try expect(!validator.isCocoaPodsProject(at: project), "普通文件 Demo.xcodeproj 不能充当工程包")
        try fileManager.removeItem(at: projectPackage)
        try makeComponent("Demo.xcodeproj", in: project)

        let podfile = project.appendingPathComponent("Podfile")
        try fileManager.removeItem(at: podfile)
        try fileManager.createDirectory(at: podfile, withIntermediateDirectories: false)
        try expect(!validator.isCocoaPodsProject(at: project), "同名 Podfile 文件夹必须拒绝")
        try fileManager.removeItem(at: podfile)
        try makeComponent("Podfile", in: project)

        let nestedOnly = root.appendingPathComponent("仅子目录完整", isDirectory: true)
        try makeProject(at: nestedOnly.appendingPathComponent("nested", isDirectory: true))
        try expect(!validator.isCocoaPodsProject(at: nestedOnly), "不能递归借用子目录的 Podfile 与工程包")

        let nestedProject = root.appendingPathComponent("仅工程包在子目录", isDirectory: true)
        try fileManager.createDirectory(at: nestedProject, withIntermediateDirectories: true)
        try makeComponent("Podfile", in: nestedProject)
        try makeComponent("Demo.xcodeproj", in: nestedProject.appendingPathComponent("nested"))
        try expect(!validator.isCocoaPodsProject(at: nestedProject), "同层只有 Podfile 时不能借用子目录工程包")

        let nestedPodfile = root.appendingPathComponent("仅Podfile在子目录", isDirectory: true)
        try fileManager.createDirectory(at: nestedPodfile.appendingPathComponent("nested"), withIntermediateDirectories: true)
        try makeComponent("Demo.xcodeproj", in: nestedPodfile)
        try makeComponent("Podfile", in: nestedPodfile.appendingPathComponent("nested"))
        try expect(!validator.isCocoaPodsProject(at: nestedPodfile), "同层只有工程包时不能借用子目录 Podfile")

        let workspace = project.appendingPathComponent("Demo.xcworkspace")
        try Data("unrelated file".utf8).write(to: workspace)
        try expect(validator.isCocoaPodsProject(at: project), "同名 workspace 普通文件不能影响 Pod 资格")
        try fileManager.removeItem(at: workspace)
        try fileManager.createDirectory(
            at: project.appendingPathComponent("nested/Demo.xcworkspace", isDirectory: true),
            withIntermediateDirectories: true
        )
        try expect(validator.isCocoaPodsProject(at: project), "workspace 位于子目录时仍允许同层 Podfile 与工程包")
        try makeComponent("Demo.xcworkspace", in: project)

        let child = project.appendingPathComponent("没有元数据的子目录", isDirectory: true)
        try fileManager.createDirectory(at: child, withIntermediateDirectories: true)
        try expect(!validator.isCocoaPodsProject(at: child), "不能借用父目录的 Podfile 与工程包后弹出终端")

        let hidden = root.appendingPathComponent("隐藏项目", isDirectory: true)
        try makeProject(at: hidden)
        try fileManager.moveItem(
            at: hidden.appendingPathComponent("Demo.xcodeproj"),
            to: hidden.appendingPathComponent(".Demo.xcodeproj")
        )
        try expect(validator.isCocoaPodsProject(at: hidden), "隐藏工程包同样满足同层 Podfile 与工程包两项条件")

        let multipleProjects = root.appendingPathComponent("多个工程包", isDirectory: true)
        try makeProject(at: multipleProjects)
        try Data("ordinary file".utf8).write(to: multipleProjects.appendingPathComponent("Other.xcodeproj"))
        try expect(validator.isCocoaPodsProject(at: multipleProjects), "一个有效工程包即可，同层其它普通文件不影响资格")

        let uppercase = root.appendingPathComponent("扩展名大小写", isDirectory: true)
        try makeProject(at: uppercase)
        try fileManager.moveItem(
            at: uppercase.appendingPathComponent("Demo.xcodeproj"),
            to: uppercase.appendingPathComponent("Demo.XCODEPROJ")
        )
        try expect(validator.isCocoaPodsProject(at: uppercase), "工程包扩展名比较沿用大小写兼容")

        try expect(!validator.isCocoaPodsProject(at: podfile), "选中文件自身不能充当工程目录")
        try expect(!validator.isCocoaPodsProject(at: project.appendingPathComponent("Demo.xcodeproj")), "选中工程包自身必须拒绝")
        try expect(!validator.isCocoaPodsProject(at: project.appendingPathComponent("Demo.xcworkspace")), "选中 workspace 包自身必须拒绝")
        try expect(!validator.isCocoaPodsProject(at: root.appendingPathComponent("不存在")), "目标消失时必须拒绝")
        try expect(!validator.isCocoaPodsProject(at: URL(string: "https://example.com/project")!), "远程 URL 必须拒绝")

        let flutter = root.appendingPathComponent("Flutter", isDirectory: true)
        try fileManager.createDirectory(at: flutter.appendingPathComponent("lib"), withIntermediateDirectories: true)
        try Data("name: fixture\ndependencies:\n  flutter:\n    sdk: flutter\n".utf8)
            .write(to: flutter.appendingPathComponent("pubspec.yaml"))
        try expect(validator.isFlutterProject(at: flutter), "Pod 门禁变更不能影响合法 Flutter 工程")
        try expect(validator.isCodeGraphTargetFolder(at: child), "普通文件夹仍允许代码地图入口")
        try expect(validator.isGitEmptyCommitPushTargetFolder(at: child), "普通文件夹仍允许 Git 入口")
        try expect(!fileManager.fileExists(atPath: project.appendingPathComponent("SHOULD_NOT_EXIST").path), "特殊路径不得被解释成命令")

        print("DependencyProjectValidatorTests: \(assertionCount) assertions passed")
    }

    private static func makeProject(at url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        for name in ["Podfile", "Demo.xcodeproj"] {
            try makeComponent(name, in: url)
        }
    }

    private static func makeComponent(_ name: String, in directory: URL) throws {
        let url = directory.appendingPathComponent(name)
        if name == "Podfile" {
            try Data("platform :ios, '12.0'\n".utf8).write(to: url)
        } else {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        assertionCount += 1
        guard condition() else {
            throw NSError(
                domain: "DependencyProjectValidatorTests",
                code: assertionCount,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
    }
}
