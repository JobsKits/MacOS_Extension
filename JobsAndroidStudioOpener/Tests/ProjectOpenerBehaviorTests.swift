//
//  ProjectOpenerBehaviorTests.swift
//  JobsAndroidStudioOpener
//
//  Created by Jobs on 2026年10月18日，星期日.
//

import AppKit

@main
struct ProjectOpenerBehaviorTests {
    static func main() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("Jobs IDE 中文 空格'\";$-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: root)
        }
        let project = root.appendingPathComponent("项目 空格'名称", isDirectory: true)
        try fileManager.createDirectory(at: project, withIntermediateDirectories: true)
        let source = project.appendingPathComponent("测试文件.swift")
        try Data("// fixture".utf8).write(to: source)
        let healthyApp = try makeApp(at: root.appendingPathComponent("Healthy.app"), bundleID: "com.google.android.studio", executable: true)
        let brokenApp = try makeApp(at: root.appendingPathComponent("Broken.app"), bundleID: "com.google.android.studio", executable: false)
        let wrongApp = try makeApp(at: root.appendingPathComponent("Other.app"), bundleID: "com.example.other", executable: true)
        var openedTargets: [URL] = []
        var downloads: [URL] = []
        var chosenCandidates: [[URL]] = []
        var failures: [String] = []
        let opener = ProjectOpener(
            applicationURLs: {
                [brokenApp, wrongApp, healthyApp]
            },
            openDocument: { target, app, completion in
                openedTargets.append(target)
                precondition(app == healthyApp)
                completion(nil)
            },
            openDownload: { url in
                downloads.append(url)
                return true
            },
            chooseCandidate: { candidates in
                chosenCandidates.append(candidates)
                return candidates.last
            },
            reportFailure: { title, _ in
                failures.append(title)
            }
        )
        precondition(opener.usableApplicationURL(in: [brokenApp]) == nil)
        precondition(opener.usableApplicationURL(in: [wrongApp]) == nil)
        precondition(opener.usableApplicationURL(in: [brokenApp, healthyApp]) == healthyApp)
        try requireEqual(opener.projectCandidates(from: source), [project])
        try requireEqual(opener.projectCandidates(from: project), [project])
        opener.open(source)
        precondition(openedTargets == [project])
        precondition(downloads.isEmpty && failures.isEmpty)
        let xcodeProject = project.appendingPathComponent("工程.xcodeproj", isDirectory: true)
        let workspace = project.appendingPathComponent("主工程.xcworkspace", isDirectory: true)
        try fileManager.createDirectory(at: xcodeProject, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: workspace, withIntermediateDirectories: true)
        try requireEqual(opener.projectCandidates(from: xcodeProject), [project])
        try requireEqual(opener.projectCandidates(from: workspace), [project])
        opener.open(project)
        precondition(openedTargets.last == project && chosenCandidates.isEmpty)
        let missingOpener = ProjectOpener(
            applicationURLs: {
                [brokenApp]
            },
            openDocument: { _, _, _ in
                preconditionFailure("缺失或残缺 IDE 不应继续打开项目")
            },
            openDownload: { url in
                downloads.append(url)
                return true
            },
            chooseCandidate: { _ in
                preconditionFailure("缺失 IDE 不应继续解析或选择项目")
            },
            reportFailure: { title, _ in
                failures.append(title)
            }
        )
        missingOpener.open(root.appendingPathComponent("不存在的项目"))
        precondition(downloads.map(\.absoluteString) == ["https://developer.android.com/studio"])
        precondition(failures.isEmpty)
        let noAppOpener = ProjectOpener(
            applicationURLs: {
                []
            },
            openDocument: { _, _, _ in
                preconditionFailure("未安装 IDE 不应打开项目")
            },
            openDownload: { _ in
                false
            },
            reportFailure: { title, _ in
                failures.append(title)
            }
        )
        noAppOpener.open(project)
        precondition(failures.count == 1)
        try verifyXcodeExclusion(at: root, healthyApp: healthyApp)
        print("PASS JobsAndroidStudioOpener: 特殊路径、目录归一、Xcode 互斥、Flutter 层级、点击复核、应用健康检查、缺失终止及下载失败分支")
    }

    static func verifyXcodeExclusion(at root: URL, healthyApp: URL) throws {
        let fileManager = FileManager.default
        func makeDirectory(_ path: String) throws -> URL {
            let url = root.appendingPathComponent(path, isDirectory: true)
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
        func makeFile(in directory: URL, named name: String) throws -> URL {
            let url = directory.appendingPathComponent(name)
            try Data("fixture".utf8).write(to: url)
            return url
        }

        var applicationLookups = 0
        var downloads = 0
        var openedTargets: [URL] = []
        let opener = ProjectOpener(
            applicationURLs: {
                applicationLookups += 1
                return [healthyApp]
            },
            openDocument: { target, app, completion in
                precondition(app == healthyApp)
                openedTargets.append(target)
                completion(nil)
            },
            openDownload: { _ in
                downloads += 1
                return true
            },
            reportFailure: { _, _ in
                preconditionFailure("Xcode 项目应在健康检查前结束")
            }
        )

        let xcodeRoot = try makeDirectory("原生项目")
        let xcodeProject = try makeDirectory("原生项目/工程.xcodeproj")
        let emptyXcodeProject = try makeDirectory("原生项目/空包.xcodeproj")
        let projectFile = try makeFile(in: xcodeProject, named: "project.pbxproj")
        let sourceFile = try makeFile(in: xcodeRoot, named: "Source.swift")
        let workspaceRoot = try makeDirectory("Workspace项目")
        let workspace = try makeDirectory("Workspace项目/工程.xcworkspace")
        _ = try makeFile(in: workspace, named: "contents.xcworkspacedata")
        let packageRoot = try makeDirectory("SwiftPackage")
        let packageFile = try makeFile(in: packageRoot, named: "Package.swift")
        let flutterRoot = try makeDirectory("Flutter")
        let flutterIOS = try makeDirectory("Flutter/ios")
        let runner = try makeDirectory("Flutter/ios/Runner.xcodeproj")
        _ = try makeFile(in: runner, named: "project.pbxproj")
        let flutterManifest = flutterRoot.appendingPathComponent("pubspec.yaml")
        try Data("name: sample\ndependencies:\n  flutter:\n    sdk: flutter\n".utf8).write(to: flutterManifest)

        for selectedURL in [xcodeRoot, xcodeProject, emptyXcodeProject, projectFile, sourceFile, workspaceRoot, workspace, packageRoot, packageFile, flutterIOS] {
            precondition(!opener.canOpen(selectedURL), "Xcode 项目应隐藏入口：\(selectedURL.path)")
            opener.open(selectedURL)
        }
        precondition(applicationLookups == 0 && downloads == 0 && openedTargets.isEmpty)
        precondition(opener.canOpen(flutterRoot), "不得递归把 Flutter 根目录视为 Xcode 项目")
        precondition(opener.canOpen(flutterManifest))
        let mixedProject = try makeDirectory("Flutter/本层工程.xcodeproj")
        let mixedWorkspace = try makeDirectory("Flutter/本层工作区.xcworkspace")
        let mixedProjectFile = try makeFile(in: mixedProject, named: "project.pbxproj")
        _ = try makeFile(in: mixedWorkspace, named: "contents.xcworkspacedata")
        precondition(opener.canOpen(flutterRoot), "Flutter 根目录优先于同层原生工程")
        for selectedURL in [mixedProject, mixedWorkspace, mixedProjectFile] {
            precondition(!opener.canOpen(selectedURL), "直接选中原生工程包时仅显示 Xcode")
            opener.open(selectedURL)
        }
        precondition(applicationLookups == 0 && downloads == 0 && openedTargets.isEmpty)
        precondition(!XcodeProjectDetector.canOpen(packageFile), "检测器只接受目录")

        let invalidRoot = try makeDirectory("无效标记")
        _ = try makeDirectory("无效标记/空工程.xcodeproj")
        _ = try makeDirectory("无效标记/空工作区.xcworkspace")
        _ = try makeDirectory("无效标记/Package.swift")
        _ = try makeFile(in: invalidRoot, named: "伪工程.xcodeproj")
        precondition(opener.canOpen(invalidRoot), "目录名或伪工程文件不能代替有效标记")

        let changingRoot = try makeDirectory("菜单之后创建项目")
        precondition(opener.canOpen(changingRoot))
        let changingProject = try makeDirectory("菜单之后创建项目/新工程.xcodeproj")
        _ = try makeFile(in: changingProject, named: "project.pbxproj")
        precondition(!opener.canOpen(changingRoot))
        opener.open(changingRoot)
        precondition(applicationLookups == 0 && downloads == 0 && openedTargets.isEmpty, "点击时必须复核当前目录")

        opener.open(flutterRoot)
        precondition(applicationLookups == 1 && downloads == 0 && openedTargets == [flutterRoot], "Flutter 根目录保留应用健康检查并正常打开")
    }

    static func requireEqual(_ actual: [URL], _ expected: [URL]) throws {
        precondition(actual == expected)
    }

    static func makeApp(at appURL: URL, bundleID: String, executable: Bool) throws -> URL {
        let fileManager = FileManager.default
        let macOS = appURL.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try fileManager.createDirectory(at: macOS, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": bundleID,
            "CFBundleExecutable": "Fixture",
            "CFBundlePackageType": "APPL"
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: appURL.appendingPathComponent("Contents/Info.plist"))
        if executable {
            let executableURL = macOS.appendingPathComponent("Fixture")
            try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executableURL)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)
        }
        return appURL
    }
}
