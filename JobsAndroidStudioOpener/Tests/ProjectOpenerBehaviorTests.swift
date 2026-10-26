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
        let manager = FileManager.default
        let root = manager.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("Jobs IDE 中文 空格'\";$-\(UUID().uuidString)")
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            try? manager.removeItem(at: root)
        }
        let project = root.appendingPathComponent("项目 空格'名称")
        try manager.createDirectory(at: project, withIntermediateDirectories: true)
        let source = project.appendingPathComponent("测试文件.swift")
        try Data("// fixture".utf8).write(to: source)
        let manifest = project.appendingPathComponent("pubspec.yaml")
        try Data("dependencies:\n  flutter:\n    sdk: flutter\n".utf8).write(to: manifest)
        let healthyApp = try makeApp(at: root.appendingPathComponent("Healthy.app"), bundleID: "com.google.android.studio", executable: true)
        let brokenApp = try makeApp(at: root.appendingPathComponent("Broken.app"), bundleID: "com.google.android.studio", executable: false)
        let wrongApp = try makeApp(at: root.appendingPathComponent("Other.app"), bundleID: "com.example.other", executable: true)
        var openedTargets: [URL] = []
        var downloads: [URL] = []
        var failures: [String] = []
        var lookups = 0
        let opener = ProjectOpener(
            applicationURLs: {
                lookups += 1
                return [brokenApp, wrongApp, healthyApp]
            },
            openDocument: { target, app, completion in
                precondition(app == healthyApp)
                openedTargets.append(target)
                completion(nil)
            },
            openDownload: { url in
                downloads.append(url)
                return true
            },
            chooseCandidate: { _ in
                preconditionFailure("单个目录不需要候选选择")
            },
            reportFailure: { title, _ in
                failures.append(title)
            }
        )
        precondition(opener.usableApplicationURL(in: [brokenApp]) == nil)
        precondition(opener.usableApplicationURL(in: [wrongApp]) == nil)
        precondition(opener.usableApplicationURL(in: [brokenApp, healthyApp]) == healthyApp)
        try requireEqual(opener.projectCandidates(from: source), [])
        try requireEqual(opener.projectCandidates(from: project), [project])
        opener.open(project)
        precondition(openedTargets.map(\.path) == [project.path] && downloads.isEmpty && failures.isEmpty)
        let before = lookups
        let empty = root.appendingPathComponent("empty")
        try manager.createDirectory(at: empty, withIntermediateDirectories: true)
        let link = root.appendingPathComponent("linked")
        try manager.createSymbolicLink(at: link, withDestinationURL: project)
        let ios = root.appendingPathComponent("ios")
        let bundle = ios.appendingPathComponent("App.xcodeproj")
        try manager.createDirectory(at: bundle, withIntermediateDirectories: true)
        try Data("SDKROOT = iphoneos;".utf8).write(to: bundle.appendingPathComponent("project.pbxproj"))
        for rejected in [empty, source, link, ios, bundle, root.appendingPathComponent("missing")] {
            try requireEqual(opener.projectCandidates(from: rejected), [])
            opener.open(rejected)
        }
        precondition(lookups == before && downloads.isEmpty && openedTargets.map(\.path) == [project.path], "不适用目标应在查找应用前拒绝")
        failures.removeAll()
        let missing = ProjectOpener(
            applicationURLs: {
                return [brokenApp]
            },
            openDocument: { _, _, _ in
                preconditionFailure("缺失 IDE 不应打开项目")
            },
            openDownload: { url in
                downloads.append(url)
                return true
            },
            reportFailure: { title, _ in
                failures.append(title)
            }
        )
        missing.open(project)
        precondition(downloads.map(\.absoluteString) == ["https://developer.android.com/studio"])
        precondition(failures.isEmpty)
        let failing = ProjectOpener(
            applicationURLs: {
                return []
            },
            openDocument: { _, _, _ in
                preconditionFailure("没有 IDE 不应打开项目")
            },
            openDownload: { _ in
                return false
            },
            reportFailure: { title, _ in
                failures.append(title)
            }
        )
        failing.open(project)
        precondition(failures.count == 1)

        try manager.removeItem(at: manifest)
        try manager.removeItem(at: source)
        precondition(!IDEProjectDirectory.isNonempty(project), "文件删完后必须判为空")
        try requireEqual(opener.projectCandidates(from: project), [])
        print("PASS JobsAndroidStudioOpener: 非空目录、iOS排除、普通文件与链接拒绝、应用健康检查、特殊路径、缺失下载及点击复核")
    }

    static func requireEqual(_ actual: [URL], _ expected: [URL]) throws {
        precondition(actual.map(\.path) == expected.map(\.path), "actual=\(actual) expected=\(expected)")
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
