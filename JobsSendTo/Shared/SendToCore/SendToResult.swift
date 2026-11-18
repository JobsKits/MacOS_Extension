//
//  SendToResult.swift
//  JobsSendToCore
//
//  Created by Jobs on 2026年11月18日，星期三.
//

import Foundation

struct SendToResult {
    var successes: [URL] = []
    var failures: [SendToFailure] = []
    var cancelled = false
    var taskID: UUID?
    var resumeAvailable = false
}
