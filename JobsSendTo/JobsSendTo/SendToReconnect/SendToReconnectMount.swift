//
//  SendToReconnectMount.swift
//  JobsSendTo
//
//  Created by Jobs on 2026年11月18日，星期三.
//

import Foundation
import NetFS

enum SendToReconnectMount {
    final class Request {
        private let lock = NSLock()
        private let cancelRequest: (AsyncRequestID) -> Void
        private var identifier: AsyncRequestID?
        private var cancelled = false
        private var finished = false

        init(cancelRequest: @escaping (AsyncRequestID) -> Void = {
            _ = NetFSMountURLCancel($0)
        }) {
            self.cancelRequest = cancelRequest
        }

        func attach(_ identifier: AsyncRequestID?) {
            lock.lock()
            guard !finished else {
                lock.unlock()
                return
            }
            self.identifier = identifier
            let cancelNow = cancelled && !finished
            if cancelNow, let identifier {
                self.identifier = nil
                cancelRequest(identifier)
            }
            lock.unlock()
        }

        func complete() -> Bool {
            lock.lock()
            defer {
                lock.unlock()
            }
            guard !finished else {
                return false
            }
            finished = true
            identifier = nil
            return !cancelled
        }

        func cancel() {
            lock.lock()
            cancelled = true
            let identifier = finished ? nil : self.identifier
            self.identifier = nil
            if let identifier {
                cancelRequest(identifier)
            }
            lock.unlock()
        }
    }

    static func mount(_ url: URL, completion: @escaping (Int32) -> Void) -> () -> Void {
        let request = Request()
        let dictionary = [kNAUIOptionKey as String: kNAUIOptionNoUI as String] as CFDictionary
        let options = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, dictionary)
        var identifier: AsyncRequestID?
        // No username/password override and no UI: only the system's existing authenticated session is used.
        let status = NetFSMountURLAsync(url as CFURL, nil, nil, nil, options, nil, &identifier,
                                       DispatchQueue.global(qos: .utility)) { status, _, _ in
            if request.complete() {
                completion(status)
            }
        }
        request.attach(identifier)
        if status != 0, request.complete() {
            completion(status)
        }
        return {
            request.cancel()
        }
    }
}
