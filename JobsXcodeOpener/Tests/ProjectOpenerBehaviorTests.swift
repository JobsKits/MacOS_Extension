//
//  ProjectOpenerBehaviorTests.swift
//  JobsXcodeOpener
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
        try verifyProjectDetection(in: root, fileManager: fileManager)
        let project = root.appendingPathComponent("项目 空格'名称", isDirectory: true)
        try fileManager.createDirectory(at: project, withIntermediateDirectories: true)
        let source = project.appendingPathComponent("测试文件.swift")
        try Data("SDKROOT = iphoneos;".utf8).write(to: source)
        var openedTargets: [URL] = []
        var chosenCandidates: [[URL]] = []
        var failures: [String] = []
        let opener = ProjectOpener(
            openDocument: { target, completion in
                openedTargets.append(target)
                completion(nil)
            },
            chooseCandidate: { candidates in
                chosenCandidates.append(candidates)
                return candidates.last
            },
            reportFailure: { title, _ in
                failures.append(title)
            }
        )
        try requireEqual(opener.projectCandidates(from: source), [])
        try requireEqual(opener.projectCandidates(from: project), [])
        opener.open(source)
        precondition(openedTargets.isEmpty && chosenCandidates.isEmpty)
        precondition(failures == ["没有可用的 iOS 项目"])
        failures.removeAll()
        let xcodeProject = project.appendingPathComponent("工程.xcodeproj", isDirectory: true)
        let workspace = project.appendingPathComponent("主工程.xcworkspace", isDirectory: true)
        try fileManager.createDirectory(at: xcodeProject, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: workspace, withIntermediateDirectories: true)
        try Data("SDKROOT = iphoneos;".utf8).write(to: xcodeProject.appendingPathComponent("project.pbxproj"))
        try Data("<Workspace><FileRef location=\"group:工程.xcodeproj\"/></Workspace>".utf8).write(to: workspace.appendingPathComponent("contents.xcworkspacedata"))
        precondition(XcodeProjectDetector.canOpen(project))
        precondition(!XcodeProjectDetector.canOpen(source))
        try requireEqual(opener.projectCandidates(from: xcodeProject), [xcodeProject])
        try requireEqual(opener.projectCandidates(from: workspace), [workspace])
        try requireEqual(opener.projectCandidates(from: source), [])
        opener.open(project)
        precondition(openedTargets.last?.resolvingSymlinksInPath() == workspace.resolvingSymlinksInPath() && chosenCandidates.isEmpty)
        let secondWorkspace = project.appendingPathComponent("第二工程.xcworkspace", isDirectory: true)
        try fileManager.createDirectory(at: secondWorkspace, withIntermediateDirectories: true)
        try Data("<Workspace><FileRef location=\"group:工程.xcodeproj\"/></Workspace>".utf8).write(to: secondWorkspace.appendingPathComponent("contents.xcworkspacedata"))
        let candidates = try opener.projectCandidates(from: project)
        precondition(Set(candidates.map { $0.resolvingSymlinksInPath() }) == Set([workspace, secondWorkspace].map { $0.resolvingSymlinksInPath() }))
        opener.open(project)
        precondition(chosenCandidates == [candidates] && openedTargets.last == candidates.last)
        let cancelOpener = ProjectOpener(
            openDocument: { _, _ in
                preconditionFailure("取消选择后不应打开项目")
            },
            chooseCandidate: { _ in
                nil
            },
            reportFailure: { _, _ in
                preconditionFailure("取消选择不应作为错误")
            }
        )
        cancelOpener.open(project)
        let failureOpener = ProjectOpener(
            openDocument: { _, completion in
                completion(NSError(domain: "TestOpenFailure", code: 1, userInfo: [NSLocalizedDescriptionKey: "系统打开失败"]))
            },
            chooseCandidate: { candidates in
                candidates.first
            },
            reportFailure: { title, _ in
                failures.append(title)
            }
        )
        failureOpener.open(project)
        let deadline = Date().addingTimeInterval(1)
        while failures.isEmpty && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        precondition(failures == ["Xcode 未能打开项目"])
        let countBeforeMissing = openedTargets.count
        opener.open(root.appendingPathComponent("不存在的项目"))
        precondition(openedTargets.count == countBeforeMissing)
        precondition(failures.last == "没有可用的 iOS 项目")
        print("PASS JobsXcodeOpener: 项目菜单识别、普通/Flutter 目录排除、纯 Swift Package / macOS 工程排除、伪工程排除、直接打开、特殊路径、workspace 优先、多候选选择/取消、系统打开失败与目标缺失")
    }

    static func verifyProjectDetection(in root: URL, fileManager: FileManager) throws {
        let ordinary = root.appendingPathComponent("普通文件夹", isDirectory: true)
        try fileManager.createDirectory(at: ordinary, withIntermediateDirectories: true)
        precondition(!XcodeProjectDetector.canOpen(ordinary))
        precondition(!XcodeProjectDetector.canOpen(root.appendingPathComponent("不存在")))
        precondition(!XcodeProjectDetector.canOpen(URL(string: "https://example.com/Project.xcodeproj")!))

        let fakeFile = ordinary.appendingPathComponent("伪工程.xcodeproj")
        try Data().write(to: fakeFile)
        let emptyBundle = ordinary.appendingPathComponent("空工作区.xcworkspace", isDirectory: true)
        try fileManager.createDirectory(at: emptyBundle, withIntermediateDirectories: true)
        let markerDirectory = emptyBundle.appendingPathComponent("contents.xcworkspacedata", isDirectory: true)
        try fileManager.createDirectory(at: markerDirectory, withIntermediateDirectories: true)
        precondition(!XcodeProjectDetector.canOpen(fakeFile))
        precondition(!XcodeProjectDetector.canOpen(emptyBundle))
        precondition(!XcodeProjectDetector.canOpen(ordinary))

        let flutter = root.appendingPathComponent("Flutter项目", isDirectory: true)
        let ios = flutter.appendingPathComponent("ios", isDirectory: true)
        let nestedProject = ios.appendingPathComponent("Runner.xcodeproj", isDirectory: true)
        try fileManager.createDirectory(at: nestedProject, withIntermediateDirectories: true)
        try Data("name: fixture\ndependencies:\n  flutter:\n    sdk: flutter\n".utf8).write(to: flutter.appendingPathComponent("pubspec.yaml"))
        try Data("SDKROOT = iphoneos;".utf8).write(to: nestedProject.appendingPathComponent("project.pbxproj"))
        precondition(!XcodeProjectDetector.canOpen(flutter))
        precondition(XcodeProjectDetector.canOpen(ios))
        precondition(XcodeProjectDetector.canOpen(nestedProject))
        let hybridProject = flutter.appendingPathComponent("同层工程.xcodeproj", isDirectory: true)
        try fileManager.createDirectory(at: hybridProject, withIntermediateDirectories: true)
        try Data("SDKROOT = iphoneos;".utf8).write(to: hybridProject.appendingPathComponent("project.pbxproj"))
        precondition(!XcodeProjectDetector.canOpen(flutter))
        precondition(XcodeProjectDetector.canOpen(hybridProject))
        let flutterLink = root.appendingPathComponent("Flutter链接", isDirectory: true)
        try fileManager.createSymbolicLink(at: flutterLink, withDestinationURL: flutter)
        precondition(!XcodeProjectDetector.canOpen(flutterLink))
        var rejectedFlutterTargets = 0
        let flutterOpener = ProjectOpener(
            openDocument: { _, _ in
                preconditionFailure("Flutter 根目录不能用 Xcode 打开")
            },
            chooseCandidate: { _ in
                preconditionFailure("Flutter 根目录不能进入 Xcode 候选选择")
            },
            reportFailure: { title, _ in
                precondition(title == "没有可用的 iOS 项目")
                rejectedFlutterTargets += 1
            }
        )
        flutterOpener.open(flutter)
        precondition(rejectedFlutterTargets == 1)

        let package = root.appendingPathComponent("Swift Package", isDirectory: true)
        try fileManager.createDirectory(at: package, withIntermediateDirectories: true)
        let manifest = package.appendingPathComponent("Package.swift")
        try fileManager.createDirectory(at: manifest, withIntermediateDirectories: true)
        precondition(!XcodeProjectDetector.canOpen(package))
        try fileManager.removeItem(at: manifest)
        try Data("// swift-tools-version: 5.9".utf8).write(to: manifest)
        precondition(!XcodeProjectDetector.canOpen(package))
        precondition(!XcodeProjectDetector.canOpen(manifest))
        try fileManager.removeItem(at: manifest)
        precondition(!XcodeProjectDetector.canOpen(package))

        let upperCaseBundle = package.appendingPathComponent("工程.XCODEPROJ", isDirectory: true)
        try fileManager.createDirectory(at: upperCaseBundle, withIntermediateDirectories: true)
        try Data("SDKROOT = iphoneos;".utf8).write(to: upperCaseBundle.appendingPathComponent("project.pbxproj"))
        precondition(XcodeProjectDetector.canOpen(package))
        precondition(XcodeProjectDetector.canOpen(upperCaseBundle))
        try verifyFlutterPrecedence(in: package)
        let hiddenRoot = root.appendingPathComponent("隐藏工程", isDirectory: true)
        let hiddenProject = hiddenRoot.appendingPathComponent(".隐藏.xcodeproj", isDirectory: true)
        try fileManager.createDirectory(at: hiddenProject, withIntermediateDirectories: true)
        try Data("SDKROOT = iphoneos;".utf8).write(to: hiddenProject.appendingPathComponent("project.pbxproj"))
        precondition(XcodeProjectDetector.canOpen(hiddenRoot))
    }

    static func verifyFlutterPrecedence(in nativeProject: URL) throws {
        let flutterManifests = [
            "dependencies:\n  flutter:\n    sdk: flutter\n",
            "dependencies:\n  flutter: {sdk: flutter}\n",
            "dependencies: {flutter: {sdk: flutter}, collection: any}\n",
            "'dependencies':\n  \"flutter\": { 'sdk': 'flutter' }\n"
        ]
        let otherManifests = [
            "name: dart_only\n",
            "# dependencies:\n#   flutter:\n#     sdk: flutter\n",
            "description: |\n  dependencies:\n    flutter:\n      sdk: flutter\n",
            "dev_dependencies:\n  flutter_test:\n    sdk: flutter\n",
            "dependencies:\n  flutter:\n    sdk: dart\n",
            "dependencies: {flutter: {sdk: flutter}, flutter: {sdk: dart}}\n"
        ]
        let manifest = nativeProject.appendingPathComponent("pubspec.yaml")
        for text in flutterManifests {
            try Data(text.utf8).write(to: manifest)
            precondition(!XcodeProjectDetector.canOpen(nativeProject))
        }
        for text in otherManifests {
            try Data(text.utf8).write(to: manifest)
            precondition(XcodeProjectDetector.canOpen(nativeProject))
        }
    }

    static func requireEqual(_ actual: [URL], _ expected: [URL]) throws {
        precondition(actual.map { $0.resolvingSymlinksInPath() } == expected.map { $0.resolvingSymlinksInPath() })
    }
}
