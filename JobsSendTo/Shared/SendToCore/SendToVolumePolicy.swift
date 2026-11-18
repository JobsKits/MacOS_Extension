//
//  SendToVolumePolicy.swift
//  JobsSendToCore
//
//  Created by Jobs on 2026年11月18日，星期三.
//

import Foundation

enum SendToVolumePolicy {

    // A local disk image on a NAS is not a physical external device.
    static func accepts(isLocal: Bool?, readOnly: Bool?, writable: Bool,
                        internalDevice: Bool?, protocolName: String?, deviceModel: String?,
                        requireWriteAccess: Bool = true) -> Bool {
        guard readOnly == false, let isLocal, !requireWriteAccess || writable else {
            return false
        }
        if !isLocal {
            return true
        }
        guard internalDevice == false,
              let protocolName, !protocolName.isEmpty else {
            return false
        }
        let evidence = (protocolName + " " + (deviceModel ?? "")).lowercased()
        return !evidence.contains("disk image") && !evidence.contains("virtual")
    }
}
