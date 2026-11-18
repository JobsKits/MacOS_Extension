//
//  SendToCancellation.swift
//  JobsSendTo
//
//  Created by Jobs on 2026年11月18日，星期三.
//

import Foundation

final class SendToCancellation {

    private let lock = NSLock.makeSendToLock()
    private var cancelled = false

    func cancel() {
        lock.withSendToLock {
            cancelled = true
        }
    }

    var isCancelled: Bool {
        return lock.withSendToLock {
            return cancelled
        }
    }
}

extension NSLock {

    static func makeSendToLock() -> NSLock {
        return NSLock()
    }

    func withSendToLock<T>(_ body: () -> T) -> T {
        lock()
        defer {
            unlock()
        }
        return body()
    }
}
