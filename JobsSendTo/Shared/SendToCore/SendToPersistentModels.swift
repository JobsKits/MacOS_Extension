//
//  SendToPersistentModels.swift
//  JobsSendToCore
//
//  Created by Jobs on 2026年11月18日，星期三.
//

import Foundation

enum SendToResumePhase: String {
    case midchunk
    case checkpointDurable = "checkpoint-durable"
    case metadataAppliedBeforeCommit = "metadata-applied-before-commit"
    case directoryChildCommitted = "directory-child-committed"
    case publishingIntent = "publishing-intent"
    case afterRename = "after-rename"
}

struct SendToResumeEvent {
    let phase: SendToResumePhase
    let nodeIndex: Int?
    let bytes: Int64?
}

struct SendToVolumeProof: Codable, Equatable {
    let rootURL: URL
    let uuid: String?
    let fsid: String
    let networkEndpoint: String?
    let fsType: String
    let rootIno: UInt64
    let reconnectURL: URL?

    init(rootURL: URL, uuid: String?, fsid: String, networkEndpoint: String?, fsType: String,
         rootIno: UInt64, reconnectURL: URL? = nil) {
        self.rootURL = rootURL
        self.uuid = uuid
        self.fsid = fsid
        self.networkEndpoint = networkEndpoint
        self.fsType = fsType
        self.rootIno = rootIno
        self.reconnectURL = reconnectURL
    }

    func matches(_ other: SendToVolumeProof) -> Bool {
        guard fsType == other.fsType, rootIno == other.rootIno else {
            return false
        }
        if let uuid, let current = other.uuid {
            return uuid == current
        }
        if let networkEndpoint, let current = other.networkEndpoint {
            return networkEndpoint == current
        }
        return false
    }
}

struct SendToPersistentSource: Codable {
    let source: SendToSource
    let volume: SendToVolumeProof
    let relativePath: String?
}

struct SendToTaskRecord: Codable {
    let version: Int
    var summary: SendToTaskSummary
    let nonce: String
    let destinationProof: SendToVolumeProof
    let sources: [SendToPersistentSource]
    let nodeCount: Int
    var stageIno: UInt64?
    var durability: String
}

struct SendToPersistentNode: Codable {
    enum Kind: String, Codable {
        case file
        case directory
        case link
    }

    let index: Int
    let top: Int
    let relative: [String]
    let kind: Kind
    let ino: UInt64
    let size: Int64
    let modifiedSeconds: Int64
    let modifiedNanoseconds: Int64
    let changedSeconds: Int64
    let changedNanoseconds: Int64
    let link: String?
    let hashes: [String]
}

struct SendToNodeProgress: Codable {
    var stageIno: UInt64?
    var blocks = 0
    var dataComplete = false
    var metadataComplete = false
}

struct SendToTopProgress: Codable {
    var phase = "copying"
    var candidate: String?
    var payloadIno: UInt64?
    var tagged = false
    var originalMode: UInt16?
}

struct SendToCompletionReceipt: Codable {
    let id: UUID
    let published: [URL]
    let completedAt: Date
}

struct SendToStageOwner: Codable, Equatable {
    let version: Int
    let taskID: UUID
    let nonce: String
}

struct SendToJournalEnvelope: Codable {
    let version: Int
    let payload: Data
    let digest: String
}
