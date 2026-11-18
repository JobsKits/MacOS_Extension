//
//  SendToSource.swift
//  JobsSendToCore
//
//  Created by Jobs on 2026年11月18日，星期三.
//

import Foundation

struct SendToSource: Codable, Equatable {
    enum Kind: String, Codable {
        case file
        case directory
    }

    let url: URL
    let identity: SendToIdentity
    let kind: Kind
}
