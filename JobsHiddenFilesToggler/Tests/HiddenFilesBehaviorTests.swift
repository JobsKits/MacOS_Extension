//
//  HiddenFilesBehaviorTests.swift
//  JobsHiddenFilesTogglerTests
//
//  Created by Jobs on 2026年10月23日，星期五.
//

import Foundation

@main
enum HiddenFilesBehaviorTests {
    private static var assertionCount = 0
    private static let simulatedError = NSError(domain: "Fixture", code: 99)

    static func main() throws {
        try testBooleanValues()
        try testRealtimeToggleAndFailureOrdering()
        try testPreferenceSynchronization()
        try testMenuContextAndFixedRequest()
        print("✔ 隐藏文件业务、偏好同步、背景范围与固定请求通过（\(assertionCount) 条断言）。")
    }

    private static func testBooleanValues() throws {
        let trueValues: [Any] = [true, NSNumber(value: 1), "1", "true", " TRUE\n", "yes", "YES"]
        let falseValues: [Any] = [false, NSNumber(value: 0), "0", "false", " FALSE\n", "no", "NO"]
        for value in trueValues {
            try check(try HiddenFilesToggleService.booleanValue(value), "规范真值应识别")
        }
        for value in falseValues {
            try check(try !HiddenFilesToggleService.booleanValue(value), "规范假值应识别")
        }
        try check(try !HiddenFilesToggleService.booleanValue(nil), "未设置时默认隐藏")
        for value: Any in ["", "maybe", 2, -1, 0.5, [true], ["value": true], NSNull()] {
            try expectFailure("异常值必须拒绝") {
                _ = try HiddenFilesToggleService.booleanValue(value)
            }
        }
    }

    private static func testRealtimeToggleAndFailureOrdering() throws {
        var current: Any? = nil
        var calls: [String] = []
        let toggler = HiddenFilesToggleService(
            read: {
                calls.append("read")
                return current
            },
            write: { target in
                calls.append("write:\(target)")
                current = target
            },
            refresh: {
                calls.append("refresh")
            }
        )
        try check(try toggler.toggle(), "首次缺省值应变为显示")
        try check(calls == ["read", "write:true", "refresh"], "必须先读、再写、最后刷新")
        current = "YES"
        try check(try !toggler.toggle(), "外部修改应在下次点击时实时读取")
        try check(calls.suffix(3) == ["read", "write:false", "refresh"], "再次切换保持顺序")

        for readFails in [true, false] {
            calls = []
            let failing = HiddenFilesToggleService(
                read: {
                    calls.append("read")
                    if readFails {
                        throw simulatedError
                    }
                    return "invalid"
                },
                write: { _ in
                    calls.append("write")
                },
                refresh: {
                    calls.append("refresh")
                }
            )
            try expectFailure("读失败或类型异常必须停止") {
                _ = try failing.toggle()
            }
            try check(calls == ["read"], "读取失败不得写入或刷新")
        }
        calls = []
        let writeFailure = HiddenFilesToggleService(
            read: {
                return false
            },
            write: { _ in
                calls.append("write")
                throw simulatedError
            },
            refresh: {
                calls.append("refresh")
            }
        )
        try expectFailure("写失败不得报告成功") {
            _ = try writeFailure.toggle()
        }
        try check(calls == ["write"], "写失败不得刷新")

        let refreshFailure = HiddenFilesToggleService(
            read: {
                return false
            },
            write: { target in
                current = target
            },
            refresh: {
                throw simulatedError
            }
        )
        do {
            _ = try refreshFailure.toggle()
            try check(false, "刷新失败必须抛错")
        } catch {
            try check(current as? Bool == true, "刷新失败时保留已确认的新偏好")
            try check(error.localizedDescription.contains("偏好已写入") && error.localizedDescription.contains("再次点击会反转"), "部分成功必须说明已写偏好及再次反转后果")
        }
    }

    private static func testPreferenceSynchronization() throws {
        var calls: [String] = []
        var current: Any? = "NO"
        var syncSucceeds = true
        var adapter = FinderHiddenFilesPreferences(
            synchronize: {
                calls.append("sync")
                return syncSucceeds
            },
            copyValue: {
                calls.append("copy")
                return current
            },
            setValue: { value in
                calls.append("set:\(value)")
                current = value
            }
        )
        try check(try adapter.read() as? String == "NO", "读取应保留原始值交给规范解析")
        try check(calls == ["sync", "copy"], "读取前必须刷新偏好缓存")
        calls = []
        try adapter.write(true)
        try check(calls == ["set:true", "sync", "copy"], "写入必须同步且回读")
        calls = []
        syncSucceeds = false
        try expectFailure("读取同步失败") {
            _ = try adapter.read()
        }
        try check(calls == ["sync"], "读取同步失败不得继续读旧缓存")
        calls = []
        try expectFailure("写入同步失败") {
            try adapter.write(false)
        }
        try check(calls == ["set:false", "sync"], "写同步失败不得把缓存读回当成功")
        calls = []
        syncSucceeds = true
        adapter.copyValue = {
            calls.append("copy")
            return true
        }
        try expectFailure("回读不符必须失败") {
            try adapter.write(false)
        }
        try check(calls == ["set:false", "sync", "copy"], "回读不符应保留失败证据")
        adapter.copyValue = {
            return nil
        }
        try expectFailure("写入 false 后读回缺失也不能报告成功") {
            try adapter.write(false)
        }
        adapter.copyValue = {
            return "invalid"
        }
        try expectFailure("写后读回异常类型必须按校验失败处理") {
            try adapter.write(true)
        }
    }

    private static func testMenuContextAndFixedRequest() throws {
        let directories = ["/", "/Users/example/Desktop", "/Volumes/External/普通 folder", "/no-read/目录"]
        for path in directories {
            let url = URL(fileURLWithPath: path, isDirectory: true)
            try check(HiddenFilesMenuContext.allowsMenu(isContainer: true, targetedURL: url), "任意目录背景应允许：\(path)")
            try check(!HiddenFilesMenuContext.allowsMenu(isContainer: false, targetedURL: url), "选中项和其它菜单类型拒绝")
        }
        try check(HiddenFilesMenuContext.allowsMenu(isContainer: true, targetedURL: nil), "无 target 的真实桌面背景应允许")
        try check(!HiddenFilesMenuContext.allowsMenu(isContainer: false, targetedURL: nil), "无 target 的 items / toolbar / sidebar 拒绝")
        try check(!HiddenFilesMenuContext.allowsMenu(isContainer: true, targetedURL: URL(string: "https://example.com")!), "网络地址拒绝")
        try check(!HiddenFilesMenuContext.allowsMenu(isContainer: true, targetedURL: URL(string: "file://remote/tmp/folder")!), "远程 file host 拒绝")
        try check(HiddenFilesRequest.isToggleRequest(HiddenFilesRequest.canonicalURL), "固定 URL 允许")
        let invalid = [
            "jobshiddenfilestoggler://finder/other", "jobshiddenfilestoggler://finder/toggle/",
            "jobshiddenfilestoggler://finder/toggle?command=anything", "jobshiddenfilestoggler://finder/toggle#fragment",
            "jobshiddenfilestoggler://user@finder/toggle", "jobshiddenfilestoggler://finder:80/toggle",
            "jobshiddenfilestoggler://finder/%74oggle", "JOBSHIDDENFILESTOGGLER://finder/toggle"
        ]
        for value in invalid {
            try check(!HiddenFilesRequest.isToggleRequest(URL(string: value)!), "非规范 URL 应拒绝")
        }
    }

    private static func expectFailure(_ message: String, operation: () throws -> Void) throws {
        var failed = false
        do {
            try operation()
        } catch {
            failed = true
        }
        try check(failed, message)
    }

    private static func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        assertionCount += 1
        guard try condition() else {
            throw NSError(domain: "HiddenFilesBehaviorTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
}
