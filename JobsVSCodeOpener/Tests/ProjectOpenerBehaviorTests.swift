//
//  ProjectOpenerBehaviorTests.swift
//  JobsVSCodeOpener
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
        let healthyApp = try makeApp(at: root.appendingPathComponent("Healthy.app"), bundleID: "com.microsoft.VSCode", executable: true)
        let brokenApp = try makeApp(at: root.appendingPathComponent("Broken.app"), bundleID: "com.microsoft.VSCode", executable: false)
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
        requireSingleMainThreadCompletion {
            opener.open(source, completion: $0)
        }
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
        requireSingleMainThreadCompletion {
            missingOpener.open(root.appendingPathComponent("不存在的项目"), completion: $0)
        }
        precondition(downloads.map(\.absoluteString) == ["https://code.visualstudio.com/download"])
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
        requireSingleMainThreadCompletion {
            noAppOpener.open(project, completion: $0)
        }
        precondition(failures.count == 1)
        verifyRequestEncoding()
        try verifyXcodeProjectExclusion(root: root, healthyApp: healthyApp)
        verifyInvalidPathCompletion(root: root, healthyApp: healthyApp)
        verifyAsyncOpenCompletion(project: project, healthyApp: healthyApp, error: nil)
        verifyAsyncOpenCompletion(
            project: project,
            healthyApp: healthyApp,
            error: NSError(domain: "JobsVSCodeOpenerTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "测试启动失败"])
        )
        print("PASS JobsVSCodeOpener: Xcode 项目互斥、Flutter 子工程边界、特殊路径、应用健康检查、请求编解码及主线程 completion")
    }

    static func verifyXcodeProjectExclusion(root: URL, healthyApp: URL) throws {
        let fileManager = FileManager.default
        let xcodeRoot = root.appendingPathComponent("Xcode 工程目录", isDirectory: true)
        let project = xcodeRoot.appendingPathComponent("工程.xcodeproj", isDirectory: true)
        let workspace = xcodeRoot.appendingPathComponent("工作区.xcworkspace", isDirectory: true)
        try fileManager.createDirectory(at: project, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: workspace, withIntermediateDirectories: true)
        try Data("// fixture".utf8).write(to: project.appendingPathComponent("project.pbxproj"))
        try Data("<Workspace/>".utf8).write(to: workspace.appendingPathComponent("contents.xcworkspacedata"))
        let source = xcodeRoot.appendingPathComponent("项目源文件.swift")
        try Data("// fixture".utf8).write(to: source)
        let fakeNestedProject = xcodeRoot.appendingPathComponent("无效包.xcodeproj", isDirectory: true)
        try fileManager.createDirectory(at: fakeNestedProject, withIntermediateDirectories: true)

        let packageRoot = root.appendingPathComponent("Swift Package", isDirectory: true)
        try fileManager.createDirectory(at: packageRoot, withIntermediateDirectories: true)
        let manifest = packageRoot.appendingPathComponent("Package.swift")
        try Data("// swift-tools-version: 5.0".utf8).write(to: manifest)

        let flutterRoot = root.appendingPathComponent("Flutter 项目", isDirectory: true)
        let iosRoot = flutterRoot.appendingPathComponent("ios", isDirectory: true)
        let iosProject = iosRoot.appendingPathComponent("Runner.xcodeproj", isDirectory: true)
        try fileManager.createDirectory(at: iosProject, withIntermediateDirectories: true)
        try Data("// fixture".utf8).write(to: iosProject.appendingPathComponent("project.pbxproj"))
        let flutterManifest = flutterRoot.appendingPathComponent("pubspec.yaml")
        try Data("name: fixture\ndependencies:\n  flutter:\n    sdk: flutter\n".utf8).write(to: flutterManifest)
        let flutterNativeProject = flutterRoot.appendingPathComponent("原生.xcodeproj", isDirectory: true)
        let flutterWorkspace = flutterRoot.appendingPathComponent("原生.xcworkspace", isDirectory: true)
        try fileManager.createDirectory(at: flutterNativeProject, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: flutterWorkspace, withIntermediateDirectories: true)
        try Data("// fixture".utf8).write(to: flutterNativeProject.appendingPathComponent("project.pbxproj"))
        try Data("<Workspace/>".utf8).write(to: flutterWorkspace.appendingPathComponent("contents.xcworkspacedata"))
        precondition(FlutterProjectValidator().isFlutterProject(at: flutterRoot))
        precondition(!ProjectOpener.isXcodeProject(at: flutterRoot))
        precondition(!ProjectOpener.isXcodeProject(at: flutterManifest))
        var openedFlutterTargets: [URL] = []
        let flutterOpener = ProjectOpener(
            applicationURLs: {
                [healthyApp]
            },
            openDocument: { target, app, completion in
                precondition(target == flutterRoot && app == healthyApp)
                openedFlutterTargets.append(target)
                completion(nil)
            },
            openDownload: { _ in
                preconditionFailure("正常 Flutter 项目不应进入下载页")
            },
            reportFailure: { _, _ in
                preconditionFailure("Flutter 根目录即使包含同层原生工程也应允许 VSCode 打开")
            }
        )
        for url in [flutterRoot, flutterManifest] {
            requireSingleMainThreadCompletion {
                flutterOpener.open(url, completion: $0)
            }
        }
        precondition(openedFlutterTargets == [flutterRoot, flutterRoot])

        let invalidRoot = root.appendingPathComponent("无效工程标记", isDirectory: true)
        let fakeProject = invalidRoot.appendingPathComponent("假工程.xcodeproj", isDirectory: true)
        let fakeWorkspace = invalidRoot.appendingPathComponent("假工作区.xcworkspace", isDirectory: true)
        try fileManager.createDirectory(at: fakeProject.appendingPathComponent("project.pbxproj"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: fakeWorkspace.appendingPathComponent("contents.xcworkspacedata"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: invalidRoot.appendingPathComponent("Package.swift"), withIntermediateDirectories: true)
        precondition(!ProjectOpener.isXcodeProject(at: invalidRoot))
        precondition(!ProjectOpener.isXcodeProject(at: fakeProject))
        precondition(!ProjectOpener.isXcodeProject(at: fakeWorkspace))
        precondition(!ProjectOpener.isXcodeProject(at: root.appendingPathComponent("不存在的工程")))
        precondition(!ProjectOpener.isXcodeProject(at: URL(string: "https://example.com/project")!))

        var failureTitles: [String] = []
        let opener = ProjectOpener(
            applicationURLs: {
                preconditionFailure("Xcode 项目必须在查询 VSCode 安装前终止")
            },
            openDocument: { _, _, _ in
                preconditionFailure("Xcode 项目不应交给 VSCode")
            },
            openDownload: { _ in
                preconditionFailure("Xcode 项目不应打开 VSCode 下载页")
            },
            reportFailure: { title, _ in
                precondition(Thread.isMainThread)
                failureTitles.append(title)
            }
        )
        let excluded = [xcodeRoot, project, workspace, source, fakeNestedProject, packageRoot, manifest, iosRoot, iosProject]
        for url in excluded {
            precondition(ProjectOpener.isXcodeProject(at: url), "必须识别 Xcode 项目：\(url.path)")
            requireSingleMainThreadCompletion {
                opener.open(url, completion: $0)
            }
        }
        precondition(failureTitles == Array(repeating: "请使用 Xcode 打开项目", count: excluded.count))
    }

    static func verifyRequestEncoding() {
        let paths = [
            "/Users/jobs/项目 中文 空格/目录@Jobs",
            "/tmp/单引号'和双引号\"",
            "/tmp/第一行\n第二行",
            "/tmp/特殊 !#$%&()+,;=[]{}^`~?-_字符/文件.swift"
        ]
        for path in paths {
            guard let request = ProjectRequest.url(forPath: path) else {
                preconditionFailure("有效路径必须能生成请求：\(path)")
            }
            precondition(ProjectRequest.path(from: request) == path, "路径编解码必须保持原文")
        }
        precondition(ProjectRequest.url(forPath: "") == nil)
        let invalidRequests = [
            "https://open?p=L3RtcA",
            "jobsvscodeopener://open",
            "jobsvscodeopener://open?p=",
            "jobsvscodeopener://open?p=@@@",
            "jobsvscodeopener://open?p=/w"
        ]
        for value in invalidRequests {
            guard let request = URL(string: value) else {
                preconditionFailure("非法请求测试样本本身必须是有效 URL")
            }
            precondition(ProjectRequest.path(from: request) == nil, "必须拒绝非法请求：\(value)")
        }
    }

    static func verifyInvalidPathCompletion(root: URL, healthyApp: URL) {
        var failureTitles: [String] = []
        let opener = ProjectOpener(
            applicationURLs: {
                [healthyApp]
            },
            openDocument: { _, _, _ in
                preconditionFailure("失效路径不应派发给编辑器")
            },
            openDownload: { _ in
                preconditionFailure("已安装编辑器时不应打开下载页面")
            },
            reportFailure: { title, _ in
                precondition(Thread.isMainThread)
                failureTitles.append(title)
            }
        )
        requireSingleMainThreadCompletion {
            opener.open(root.appendingPathComponent("已删除项目"), completion: $0)
        }
        precondition(failureTitles == ["无法读取项目位置"])
    }

    static func verifyAsyncOpenCompletion(project: URL, healthyApp: URL, error: Error?) {
        var failureTitles: [String] = []
        let opener = ProjectOpener(
            applicationURLs: {
                [healthyApp]
            },
            openDocument: { target, app, completion in
                precondition(target == project && app == healthyApp)
                DispatchQueue.global().async {
                    precondition(!Thread.isMainThread)
                    completion(error)
                }
            },
            openDownload: { _ in
                preconditionFailure("已安装编辑器时不应打开下载页面")
            },
            reportFailure: { title, message in
                precondition(Thread.isMainThread)
                precondition(message == error?.localizedDescription)
                failureTitles.append(title)
            }
        )
        requireSingleMainThreadCompletion {
            opener.open(project, completion: $0)
        }
        precondition(failureTitles == (error == nil ? [] : ["VSCode 未能打开项目"]))
    }

    static func requireSingleMainThreadCompletion(_ start: (@escaping () -> Void) -> Void) {
        precondition(Thread.isMainThread)
        var completionCount = 0
        start {
            precondition(Thread.isMainThread, "宿主完成回调必须回到主线程")
            completionCount += 1
        }
        precondition(completionCount == 0, "完成回调应异步派发，避免宿主启动重入")
        let deadline = Date().addingTimeInterval(2)
        // 主线程继续处理 run loop，避免信号量等待堵住待验证的主队列回调。
        while completionCount == 0 && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        precondition(completionCount == 1, "每条打开请求必须恰好完成一次")
        RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        precondition(completionCount == 1, "打开请求不能重复完成")
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
