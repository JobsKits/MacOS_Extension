//
//  IDEProjectDetectionTests.swift
//  JobsProjectToolsTests
//
//  Created by Jobs on 2026年10月26日，星期一.
//

import Foundation

@main
enum IDEProjectDetectionTests {
    static func main() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("JobsIDEDetection-\(UUID().uuidString)")
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            try? manager.removeItem(at: root)
        }
        var count = 0
        func file(_ path: String, _ text: String = "fixture") throws {
            let url = root.appendingPathComponent(path)
            try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
        func expect(_ path: String, android: Bool, vscode: Bool, xcode: Bool) {
            let url = root.appendingPathComponent(path)
            precondition(IDEProjectDirectory.canOpenInAndroidStudio(url) == android, "Android: \(path)")
            precondition(IDEProjectDirectory.canOpenInVSCode(url) == vscode, "VSCode: \(path)")
            precondition(XcodeProjectDetector.canOpen(url) == xcode, "Xcode: \(path)")
            count += 3
        }
        try manager.createDirectory(at: root.appendingPathComponent("empty"), withIntermediateDirectories: true)
        try file("metadata/.DS_Store")
        try file("metadata/Thumbs.db")
        try file("metadata/desktop.ini")
        try file("ordinary/README.md")
        try file("hidden/.git/config")
        try file("gradle/settings.gradle", "rootProject.name = 'ordinary'")
        try file("gradle/build.gradle", "plugins { id 'java' }")
        try file("commented/settings.gradle")
        try file("commented/build.gradle", "// plugins { id 'com.android.application' }\n")
        try file("android/settings.gradle.kts")
        try file("android/app/src/main/AndroidManifest.xml", "<manifest/>")
        try file("android-library/settings.gradle")
        try file("android-library/build.gradle", "plugins { id 'com.android.library' }")
        try file("not-root/child/settings.gradle")
        try file("not-root/child/app/src/main/AndroidManifest.xml", "<manifest/>")
        let flutter = "dependencies:\n  flutter:\n    sdk: flutter\n"
        try file("flutter/pubspec.yaml", flutter)
        try file("flutter/ios/App.xcodeproj/project.pbxproj", "SDKROOT = iphoneos;")
        try file("flutter/App.xcodeproj/project.pbxproj", "SDKROOT = iphoneos;")
        try file("flutter-ohos/pubspec.yaml", flutter)
        try file("flutter-ohos/ohos/build-profile.json5")
        try file("dart/pubspec.yaml", "name: ordinary_dart\n")
        try file("ios/App.xcodeproj/project.pbxproj", "SDKROOT = iphoneos;")
        try file("ios/App.xcworkspace/contents.xcworkspacedata", "<Workspace><FileRef location=\"group:App.xcodeproj\"/></Workspace>")
        try file("grouped/Projects/A&B.xcodeproj/project.pbxproj", "SDKROOT = iphoneos;")
        try file("grouped/App.xcworkspace/contents.xcworkspacedata", "<Workspace><Group location=\"group:Projects\"><FileRef location=\"group:A&amp;B.xcodeproj\"/></Group></Workspace>")
        try file("mac/App.xcodeproj/project.pbxproj", "SDKROOT = macosx; SUPPORTED_PLATFORMS = \"macosx\";")
        try file("mac/App.xcworkspace/contents.xcworkspacedata", "<Workspace><FileRef location=\"group:App.xcodeproj\"/></Workspace>")
        try file("package/Package.swift", "// swift-tools-version:5.9\n")
        try file("fake/App.xcodeproj/project.pbxproj", "/* SDKROOT = iphoneos; */\nSDKROOT = macosx;")
        try file("simulator/App.xcodeproj/project.pbxproj", "SUPPORTED_PLATFORMS = \"iphonesimulator iphoneos\";")
        try file("dangling/App.xcworkspace/contents.xcworkspacedata", "<Workspace><FileRef location=\"group:Missing.xcodeproj\"/></Workspace>")
        try file("macro-mac/App.xcodeproj/project.pbxproj", "SDKROOT = \"$(MACOS_SDK)\"; productType = application;")
        try file("large/App.xcodeproj/project.pbxproj", String(repeating: " ", count: 1_048_576) + "SDKROOT = iphoneos;")
        try file("large-mac/App.xcodeproj/project.pbxproj", String(repeating: " ", count: 1_048_576) + "SDKROOT = macosx;")
        try file("bad-encoding/App.xcodeproj/project.pbxproj")
        try Data([0xff, 0xfe, 0xff]).write(to: root.appendingPathComponent("bad-encoding/App.xcodeproj/project.pbxproj"))
        try file("broken-xml/App.xcworkspace/contents.xcworkspacedata", "<Workspace><FileRef")
        try file("unsupported-reference/App.xcworkspace/contents.xcworkspacedata", "<Workspace><FileRef location=\"custom:App.xcodeproj\"/></Workspace>")
        try file("relative/App.xcworkspace/contents.xcworkspacedata", "<Workspace><FileRef location=\"group:../ios/App.xcodeproj\"/></Workspace>")
        try file("cycle/One.xcworkspace/contents.xcworkspacedata", "<Workspace><FileRef location=\"group:Two.xcworkspace\"/></Workspace>")
        try file("cycle/Two.xcworkspace/contents.xcworkspacedata", "<Workspace><FileRef location=\"group:One.xcworkspace\"/></Workspace>")
        try manager.createSymbolicLink(at: root.appendingPathComponent("linked"), withDestinationURL: root.appendingPathComponent("android"))
        for path in ["empty", "metadata", "missing", "ordinary/README.md", "linked", "ios/App.xcodeproj/project.pbxproj"] {
            expect(path, android: false, vscode: false, xcode: false)
        }
        for path in ["ordinary", "hidden", "gradle", "commented", "not-root", "dart", "mac", "package", "fake", "macro-mac"] {
            expect(path, android: false, vscode: true, xcode: false)
        }
        for path in ["dangling", "large", "large-mac", "bad-encoding", "broken-xml", "unsupported-reference", "cycle"] {
            expect(path, android: false, vscode: false, xcode: false)
        }
        for path in ["android", "android-library", "flutter", "flutter-ohos"] {
            expect(path, android: true, vscode: true, xcode: false)
        }
        for path in ["ios", "ios/App.xcodeproj", "ios/App.xcworkspace", "flutter/ios", "simulator", "grouped", "relative"] {
            expect(path, android: false, vscode: false, xcode: true)
        }
        try manager.removeItem(at: root.appendingPathComponent("android/app/src/main/AndroidManifest.xml"))
        expect("android", android: false, vscode: true, xcode: false)
        try manager.removeItem(at: root.appendingPathComponent("ordinary/README.md"))
        expect("ordinary", android: false, vscode: false, xcode: false)
        print("PASS: \(count) IDE selection policy assertions")
    }
}
