//
//  GitProxyAppDelegateTests.swift
//  JobsGitProxyConfiguratorTests
//
//  Created by Jobs on 2026年10月21日，星期三.
//

import AppKit

/// 与真实 AppDelegate 隔离编译，只记录派发，不控制 Terminal、注册扩展或修改Git配置。
final class GitProxyModel {
    static var instances: [GitProxyModel] = []
    private(set) var createCount = 0
    private(set) var completions: [() -> Void] = []
    private(set) var messages: [String] = []
    var onCreate: (() -> Void)?

    init() {
        Self.instances.append(self)
    }

    func record(_ message: String) {
        messages.append(message)
    }

    func configureGitProxy(completion: @escaping () -> Void) {
        createCount += 1
        completions.append(completion)
        onCreate?()
    }

    func enableExtension(completion: @escaping () -> Void) {
        completion()
    }

    func finishNextRequest() {
        let completion = completions.removeFirst()
        completion()
    }
}

@main
enum GitProxyAppDelegateTests {
    private static var assertionCount = 0

    private enum Receiver: CaseIterable {
        case openURLs
        case appleEvent

        var other: Receiver {
            return self == .openURLs ? .appleEvent : .openURLs
        }
    }

    static func main() throws {
        for receiver in Receiver.allCases {
            try testInterleavedCallbacks(firstReceiver: receiver)
            try testInvalidRequestsPreserveCreateOpportunity(receiver: receiver)
            try testReentrantCallbackIsIgnored(receiver: receiver)
        }
        try testNewDelegateAcceptsNewRequest()
        print("✔ 真实 AppDelegate 两种 URL 回调去重回归通过（\(assertionCount) 条断言）。")
    }

    private static func testInterleavedCallbacks(firstReceiver: Receiver) throws {
        let (delegate, model) = makeDelegate()
        try deliver(GitProxyRequest.canonicalURL, to: delegate, via: firstReceiver)
        try check(model.createCount == 1 && model.completions.count == 1, "首次合法请求应只派发一次")

        try deliver(GitProxyRequest.canonicalURL, to: delegate, via: firstReceiver.other)
        try deliver(GitProxyRequest.canonicalURL, to: delegate, via: firstReceiver)
        try check(model.createCount == 1 && model.completions.count == 1, "完成前交错重复回调不得再次派发")

        model.finishNextRequest()
        try deliver(GitProxyRequest.canonicalURL, to: delegate, via: firstReceiver.other)
        try check(model.createCount == 1 && model.completions.isEmpty, "派发完成后，同一宿主仍应忽略重复请求")
        try check(model.messages.filter { $0.contains("忽略重复") }.count == 3, "每个重复请求应记录忽略原因")
    }

    private static func testInvalidRequestsPreserveCreateOpportunity(receiver: Receiver) throws {
        let (delegate, model) = makeDelegate()
        delegate.application(NSApplication.shared, open: [])
        delegate.application(NSApplication.shared, open: [GitProxyRequest.canonicalURL, GitProxyRequest.canonicalURL])
        try deliver(URL(string: "jobsgitproxyconfigurator://git/other")!, to: delegate, via: receiver)
        try deliverAppleEvent(value: nil, to: delegate)
        try check(model.createCount == 0 && model.completions.isEmpty, "无效 URL 或事件不得派发")

        try deliver(GitProxyRequest.canonicalURL, to: delegate, via: receiver.other)
        try check(model.createCount == 1 && model.completions.count == 1, "无效请求不占用首次合法请求机会")
        model.finishNextRequest()
    }

    private static func testReentrantCallbackIsIgnored(receiver: Receiver) throws {
        let (delegate, model) = makeDelegate()
        var deliveryError: Error?
        model.onCreate = {
            model.onCreate = nil
            do {
                try deliver(GitProxyRequest.canonicalURL, to: delegate, via: receiver.other)
            } catch {
                deliveryError = error
            }
        }
        try deliver(GitProxyRequest.canonicalURL, to: delegate, via: receiver)
        if let deliveryError {
            throw deliveryError
        }
        try check(model.createCount == 1 && model.completions.count == 1, "进入配置函数前应已阻止重入请求")
        model.finishNextRequest()
    }

    private static func testNewDelegateAcceptsNewRequest() throws {
        let (firstDelegate, firstModel) = makeDelegate()
        try deliver(GitProxyRequest.canonicalURL, to: firstDelegate, via: .openURLs)
        firstModel.finishNextRequest()
        let (secondDelegate, secondModel) = makeDelegate()
        try deliver(GitProxyRequest.canonicalURL, to: secondDelegate, via: .appleEvent)
        try check(firstModel.createCount == 1 && secondModel.createCount == 1, "新宿主实例应拥有独立请求机会")
        secondModel.finishNextRequest()
    }

    private static func makeDelegate() -> (AppDelegate, GitProxyModel) {
        let delegate = AppDelegate()
        return (delegate, GitProxyModel.instances.last!)
    }

    private static func deliver(_ url: URL, to delegate: AppDelegate, via receiver: Receiver) throws {
        switch receiver {
        case .openURLs:
            delegate.application(NSApplication.shared, open: [url])
        case .appleEvent:
            try deliverAppleEvent(value: url.absoluteString, to: delegate)
        }
    }

    private static func deliverAppleEvent(value: String?, to delegate: AppDelegate) throws {
        let event = NSAppleEventDescriptor.appleEvent(
            withEventClass: AEEventClass(kInternetEventClass),
            eventID: AEEventID(kAEGetURL),
            targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        if let value {
            event.setParam(NSAppleEventDescriptor(string: value), forKeyword: keyDirectObject)
        }
        let selector = NSSelectorFromString("handleOpenURL:withReplyEvent:")
        try check(delegate.responds(to: selector), "真实 AppDelegate 应暴露 Apple Event 接收方法")
        _ = delegate.perform(selector, with: event, with: NSAppleEventDescriptor.null())
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        assertionCount += 1
        guard condition() else {
            throw NSError(domain: "GitProxyAppDelegateTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
}
