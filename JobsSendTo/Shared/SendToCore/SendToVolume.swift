//
//  SendToVolume.swift
//  JobsSendToCore
//
//  Created by Jobs on 2026年11月18日，星期三.
//

import Foundation

struct SendToVolume: Codable, Equatable {
    let url: URL
    let name: String
    let identity: SendToIdentity
    let isNetwork: Bool
    let rootURL: URL?
    let rootIdentity: SendToIdentity?

    init(url: URL, name: String, identity: SendToIdentity, isNetwork: Bool,
         rootURL: URL? = nil, rootIdentity: SendToIdentity? = nil) {
        self.url = url
        self.name = name
        self.identity = identity
        self.isNetwork = isNetwork
        self.rootURL = rootURL
        self.rootIdentity = rootIdentity
    }

    var volumeURL: URL {
        return rootURL ?? url
    }

    var volumeIdentity: SendToIdentity {
        return rootIdentity ?? identity
    }

    var identifier: String {
        return "\(identity.dev):\(identity.ino)"
    }
}
