//
//  PermanentDeleteBehaviorTests.swift
//  JobsPermanentDeleter
//
//  Created by Jobs on 2026年11月18日，星期三.
//

import Foundation
import Darwin

@main
struct PermanentDeleteBehaviorTests {

    // Delete only fresh fixtures owned by this test process; no user data is supplied to the service.
    static func main() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("JobsPermanentDeleteTest-" + UUID().uuidString).resolvingSymlinksInPath()
        try manager.createDirectory(at: root, withIntermediateDirectories: false)
        defer {
            try? manager.removeItem(at: root)
        }
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            precondition(value(), message)
            checks += 1
        }
        func write(_ name: String, _ body: String = "fixture") throws -> URL {
            let url = root.appendingPathComponent(name)
            try Data(body.utf8).write(to: url)
            return url
        }
        let file = try write("文件 空格 ' $() ; ☀️")
        let first = PermanentDeleteContext.snapshot(file)!
        let request = PermanentDeleteRequest(urls: [file])!
        check(PermanentDeleteRequest(url: request.url!)?.items.first?.path == first.path, "URL round trip")
        check(PermanentDeleteRequest(urls: []) == nil, "empty blocked")
        check(PermanentDeleteRequest(urls: [file, file]) == nil, "duplicates blocked")
        check(PermanentDeleteContext.snapshot(URL(fileURLWithPath: "/")) == nil, "root blocked")
        check(PermanentDeleteContext.snapshot(URL(fileURLWithPath: NSHomeDirectory())) == nil, "home blocked")
        check(PermanentDeleteContext.snapshot(URL(fileURLWithPath: "/Applications")) == nil, "applications blocked")
        try PermanentDeleteService.apply(first)
        check(!manager.fileExists(atPath: file.path), "file directly deleted")
        let stale = try write("stale")
        let staleItem = PermanentDeleteContext.snapshot(stale)!
        try manager.moveItem(at: stale, to: root.appendingPathComponent("old-stale"))
        try Data("new-object".utf8).write(to: stale)
        do {
            try PermanentDeleteService.apply(staleItem)
            preconditionFailure("replaced root must fail")
        } catch {
            check(try! String(contentsOf: stale, encoding: .utf8) == "new-object", "new root preserved")
        }
        let outside = try write("outside", "keep")
        let tree = root.appendingPathComponent("folder")
        try manager.createDirectory(at: tree.appendingPathComponent("nested"), withIntermediateDirectories: true)
        try Data("child".utf8).write(to: tree.appendingPathComponent("nested/child"))
        try manager.createSymbolicLink(at: tree.appendingPathComponent("link"), withDestinationURL: outside)
        check(PermanentDeleteRequest(urls: [tree, tree.appendingPathComponent("nested")]) == nil, "overlap blocked")
        try PermanentDeleteService.apply(PermanentDeleteContext.snapshot(tree)!)
        check(!manager.fileExists(atPath: tree.path), "recursive deletion")
        check(try! String(contentsOf: outside, encoding: .utf8) == "keep", "nested symlink target preserved")
        let link = root.appendingPathComponent("direct-link")
        try manager.createSymbolicLink(at: link, withDestinationURL: outside)
        try PermanentDeleteService.apply(PermanentDeleteContext.snapshot(link)!)
        check(!manager.fileExists(atPath: link.path), "selected link removed")
        check(try! String(contentsOf: outside, encoding: .utf8) == "keep", "selected link target preserved")
        let deniedTree = root.appendingPathComponent("special-tree")
        try manager.createDirectory(at: deniedTree, withIntermediateDirectories: false)
        check(mkfifo(deniedTree.appendingPathComponent("fifo").path, 0o600) == 0, "fifo fixture")
        do {
            try PermanentDeleteService.apply(PermanentDeleteContext.snapshot(deniedTree)!)
            preconditionFailure("unsupported child must fail")
        } catch let failure as PermanentDeleteService.Failure {
            check(failure.remainingPath == PermanentDeleteContext.snapshot(deniedTree)?.path, "remainder restored path reported")
            check(manager.fileExists(atPath: deniedTree.appendingPathComponent("fifo").path), "unsupported child retained")
        }
        let parent = root.appendingPathComponent("parent")
        try manager.createDirectory(at: parent, withIntermediateDirectories: false)
        let child = parent.appendingPathComponent("child")
        try Data("old".utf8).write(to: child)
        let childItem = PermanentDeleteContext.snapshot(child)!
        try manager.moveItem(at: parent, to: root.appendingPathComponent("moved-parent"))
        try manager.createSymbolicLink(at: parent, withDestinationURL: root)
        do {
            try PermanentDeleteService.apply(childItem)
            preconditionFailure("changed parent must fail")
        } catch {
            check(manager.fileExists(atPath: root.appendingPathComponent("moved-parent/child").path), "old parent contents preserved")
        }
        let leftovers = try manager.contentsOfDirectory(atPath: root.path).filter { $0.hasPrefix(".jobs-permanent-delete-") }
        check(leftovers.isEmpty, "no undisclosed staging leftovers")
        print("PermanentDeleteBehaviorTests: \(checks) checks passed")
    }
}
