//
//  FlutterPackagingAppDelegateTests.swift
//  JobsFlutterPackagerTests
//
//  Created by Jobs on 2026年10月22日，星期四.
//

import AppKit

/// 用假 Model 验证真实 AppDelegate 的 URL 去重；不调用 Terminal 或扩展注册。
final class FlutterPackagingModel {
    static var projects: [URL] = []
    static var initializations = 0

    func record(_ message: String) {}

    func enableExtension(completion: @escaping () -> Void) {
        Self.initializations += 1
        completion()
    }

    func package(_ projectURL: URL, completion: @escaping () -> Void) {
        Self.projects.append(projectURL)
        completion()
    }
}

@main
enum FlutterPackagingAppDelegateTests {
    static func main() throws {
        let application = NSApplication.shared
        let first = AppDelegate()
        first.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        let project = URL(fileURLWithPath: "/tmp/Flutter 中文 ' $ project", isDirectory: true)
        guard let request = FlutterPackagingRequest.url(for: project) else {
            throw NSError.make(domain: "FlutterPackagingAppDelegateTests", message: "无法构造 URL")
        }
        first.application(application, open: [URL(string: "jobsflutterpackager://invalid")!])
        first.application(application, open: [])
        first.application(application, open: [request, request])
        try check(FlutterPackagingModel.projects.isEmpty, "无效请求不能进入打包")
        first.application(application, open: [request])
        first.application(application, open: [request])
        first.application(application, open: [FlutterPackagingRequest.url(for: URL(fileURLWithPath: "/tmp/other"))!])
        try check(FlutterPackagingModel.projects.count == 1, "一次宿主启动只允许一次合法派发")
        try check(FlutterPackagingModel.projects.first?.path == project.path, "传给 Model 的路径必须精确")
        try check(FlutterPackagingModel.initializations == 1, "初始化次数不正确")
        let second = AppDelegate()
        second.application(application, open: [request])
        try check(FlutterPackagingModel.projects.count == 2, "下一次宿主运行必须可以再次打包")
        print("✔ 5 条断言：真实 AppDelegate 无效请求拒绝与单次派发回归通过。")
    }

    private static func check(_ condition: Bool, _ message: String) throws {
        guard condition else {
            throw NSError.make(domain: "FlutterPackagingAppDelegateTests", message: message)
        }
    }
}
