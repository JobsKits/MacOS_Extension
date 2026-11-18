//
//  SendToReconnectState.swift
//  JobsSendTo
//
//  Created by Jobs on 2026年11月18日，星期三.
//

import Foundation

enum SendToReconnectState: Equatable {
    case checking(attempt: Int)
    case mounting(attempt: Int)
    case requestingConnection
    case waiting(attempt: Int, retryAfter: TimeInterval)
    case ready
    case cancelled
    case stopped(String)
}
