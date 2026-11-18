//
//  SendToFailure.swift
//  JobsSendToCore
//
//  Created by Jobs on 2026年11月18日，星期三.
//

import Foundation

struct SendToFailure {
    let source: URL?
    let code: String
    let message: String
    let systemCode: Int32?

    init(source: URL?, code: String, message: String, systemCode: Int32? = nil) {
        self.source = source
        self.code = code
        self.message = message
        self.systemCode = systemCode
    }
}
