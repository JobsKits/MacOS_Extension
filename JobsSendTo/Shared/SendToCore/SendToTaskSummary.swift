//
//  SendToTaskSummary.swift
//  JobsSendToCore
//
//  Created by Jobs on 2026年11月18日，星期三.
//

import Foundation

struct SendToTaskSummary: Codable {
    let id: UUID
    var destination: SendToVolume
    let sourcePaths: [String]
    var state: String
    var completed: Int
    let total: Int
    var updatedAt: Date
    var detail: String?
    var isBusy: Bool
}

struct SendToTaskMatch {
    let summary: SendToTaskSummary
    let canResume: Bool
    let reason: String?
    var canRestart = true
}
