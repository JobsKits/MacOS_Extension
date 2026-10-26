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
        let healthyApp = try makeApp(at: root.appendingPathComponent("Healthy.app"), bundleID: "com.microsoft.VSCode", executable: true)
        let brokenApp = try makeApp(at: root.appendingPathComponent("Broken.app"), bundleID: "com.microsoft.VSCode", executable: false)
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
        requireSingleMainThreadCompletion { completion in
            opener.open(project, completion: completion)
        }
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
            requireSingleMainThreadCompletion { completion in
            opener.open(rejected, completion: completion)
        }
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
        requireSingleMainThreadCompletion { completion in
            missing.open(project, completion: completion)
        }
        precondition(downloads.map(\.absoluteString) == ["https://code.visualstudio.com/download"])
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
        requireSingleMainThreadCompletion { completion in
            failing.open(project, completion: completion)
        }
        precondition(failures.count == 1)
        verifyRequestEncoding()
        verifyInvalidPathCompletion(root: root, healthyApp: healthyApp)
        verifyAsyncOpenCompletion(project: project, healthyApp: healthyApp, error: nil)
        verifyAsyncOpenCompletion(project: project, healthyApp: healthyApp, error: NSError(domain: "Test", code: 1))
        try manager.removeItem(at: manifest)
        try manager.removeItem(at: source)
        precondition(!IDEProjectDirectory.isNonempty(project), "文件删完后必须判为空")
        try requireEqual(opener.projectCandidates(from: project), [])
        print("PASS JobsVSCodeOpener: 非空目录、iOS排除、普通文件与链接拒绝、应用健康检查、特殊路径、缺失下载及点击复核")
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
        precondition(failureTitles == ["当前目录不适用于 VSCode 项目入口"])
    }

    static func verifyAsyncOpenCompletion(project: URL, healthyApp: URL, error: Error?) {
        var failureTitles: [String] = []
        let opener = ProjectOpener(
            applicationURLs: {
                [healthyApp]
            },
            openDocument: { target, app, completion in
                precondition(target.path == project.path && app == healthyApp)
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
