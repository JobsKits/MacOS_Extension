//
//  FileHashFailure.swift
//  JobsFileHasher
//
//  Created by Jobs on 2026年11月6日，星期五.
//

import Foundation

enum FileHashFailure: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message):
            return message
        }
    }
}
