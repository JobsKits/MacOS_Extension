//
//  IOSToolsBehaviorTests.swift
//  JobsIOSToolsTests
//
//  Created by Jobs on 2026年10月23日，星期五.
//

import Foundation

@main
enum IOSToolsBehaviorTests {
    static func main() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("JobsIOSToolsTests-\(UUID().uuidString)")
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            try? manager.removeItem(at: root)
        }
        let project = root.appendingPathComponent("中文 '项目 $() `x` \\\n换行\u{2028}终点")
        try manager.createDirectory(at: project, withIntermediateDirectories: true)
        try Data().write(to: project.appendingPathComponent("Podfile"))
        let validator = IOSProjectValidator()
        precondition(validator.isIOSProject(at: project))
        precondition(!validator.supports(.podBuildCheck, at: project))
        let nested = project.appendingPathComponent("Nested")
        try manager.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data().write(to: nested.appendingPathComponent("Nested.podspec"))
        precondition(!validator.supports(.podBuildCheck, at: project))
        try Data().write(to: project.appendingPathComponent("Direct.podspec"))
        precondition(validator.supports(.podBuildCheck, at: project))
        try manager.removeItem(at: project.appendingPathComponent("Direct.podspec"))
        try Data().write(to: project.appendingPathComponent(".Current.podspec"))
        precondition(validator.supports(.podBuildCheck, at: project))
        try manager.removeItem(at: project.appendingPathComponent(".Current.podspec"))
        try manager.createDirectory(at: project.appendingPathComponent("Directory.podspec"), withIntermediateDirectories: true)
        precondition(!validator.supports(.podBuildCheck, at: project))
        try Data().write(to: project.appendingPathComponent("Upper.PODSPEC"))
        precondition(!validator.supports(.podBuildCheck, at: project))
        precondition(!validator.isIOSProject(at: root))
        let link = root.appendingPathComponent("link")
        try manager.createSymbolicLink(at: link, withDestinationURL: project)
        precondition(!validator.isIOSProject(at: link))
        if let desktop = FinderDesktopMenuPolicy.realHomeDirectory?.appendingPathComponent("Desktop") {
            precondition(FinderDesktopMenuPolicy.isDesktopContainer(desktop))
            precondition(!validator.isIOSProject(at: desktop))
        }
        precondition(IOSFeatureConfiguration.parse("").isEmpty)
        precondition(IOSFeatureConfiguration.parse("ios-clean-cache,ios-pod-build-check,unknown") == [.cleanCache, .podBuildCheck])
        for action in IOSToolsAction.allCases {
            let request = IOSToolsRequest.url(for: project, action: action)!
            precondition(IOSToolsRequest.projectURL(from: request)?.path == project.path)
            precondition(IOSToolsRequest.action(from: request) == action)
        }
        for malformed in [
            "jobsiostools://ios-clean-cache?path=relative",
            "jobsiostools://ios-clean-cache?path=/tmp&path=/other",
            "jobsiostools://unknown?path=/tmp",
            "jobsiostools://ios-clean-cache?path=/tmp#fragment",
            "jobsiostools://ios-clean-cache:2?path=/tmp"
        ] {
            precondition(IOSToolsRequest.projectURL(from: URL(string: malformed)!) == nil)
        }
        let tools = root.appendingPathComponent("stubTools")
        try manager.createDirectory(at: tools, withIntermediateDirectories: true)
        try "#!/bin/zsh\n/usr/bin/printf '%s\\0' \"$@\" > \"$JOBS_IOS_TEST_OUTPUT\"\n".write(to: tools.appendingPathComponent("DispatchIOSTools.zsh"), atomically: true, encoding: .utf8)
        let output = root.appendingPathComponent("arguments.bin")
        let launcher = IOSToolsLauncher()
        let carrier = try launcher.prepare(projectURL: project, action: .cleanCache, toolsURL: tools)
        precondition(!carrier.commandLine.contains("\n"))
        let attributes = try manager.attributesOfItem(atPath: carrier.directoryURL.path)
        precondition((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
        let process = Process.jobsMake {
            $0.byExecutableURL(URL(fileURLWithPath: "/bin/zsh"))
                .byArguments(["-f", "-c", carrier.commandLine.replacingOccurrences(of: "/bin/zsh -l ", with: "/bin/zsh -f ")])
        }
        var environment = ProcessInfo.processInfo.environment
        environment["JOBS_IOS_TEST_OUTPUT"] = output.path
        process.environment = environment
        try process.run()
        process.waitUntilExit()
        precondition(process.terminationStatus == 0)
        let raw = try Data(contentsOf: output)
        precondition(raw == Data((IOSToolsAction.cleanCache.rawValue + "\0" + project.path + "\0").utf8))
        precondition(!manager.fileExists(atPath: carrier.directoryURL.path))
        print("IOSTools Swift behavior, URL and private carrier checks passed")
    }
}
