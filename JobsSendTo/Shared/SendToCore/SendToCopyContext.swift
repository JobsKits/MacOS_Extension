//
//  SendToCopyContext.swift
//  JobsSendToCore
//
//  Created by Jobs on 2026年11月18日，星期三.
//

import Foundation
import Darwin

final class SendToCopyContext {
    let cancelled: () -> Bool
    let progress: () -> Void
    let dataCheckpoint: (Int64) -> Void
    private(set) var firstFailure: Int32?
    private(set) var userCancelled = false

    init(cancelled: @escaping () -> Bool, progress: @escaping () -> Void,
         dataCheckpoint: @escaping (Int64) -> Void) {
        self.cancelled = cancelled
        self.progress = progress
        self.dataCheckpoint = dataCheckpoint
    }

    // This callback runs during fcopyfile's data blocks, so a large file remains cancellable.
    static let callback: copyfile_callback_t = { kind, stage, state, _, _, pointer in
        let systemError = errno
        guard let pointer else {
            return COPYFILE_QUIT
        }
        let context = Unmanaged<SendToCopyContext>.fromOpaque(pointer).takeUnretainedValue()
        // CONTINUE at COPYFILE_ERR asks copyfile to retry indefinitely, including on ENOSPC.
        if stage == COPYFILE_ERR {
            if !context.userCancelled, context.firstFailure == nil {
                context.firstFailure = systemError == 0 ? EIO : systemError
            }
            return COPYFILE_QUIT
        }
        if context.cancelled() {
            context.userCancelled = true
            return COPYFILE_QUIT
        }
        if kind == COPYFILE_COPY_DATA, stage == COPYFILE_PROGRESS, let state {
            var copied: Int64 = 0
            if copyfile_state_get(state, UInt32(COPYFILE_STATE_COPIED), &copied) == 0 {
                context.dataCheckpoint(copied)
            }
        }
        if context.cancelled() {
            context.userCancelled = true
            return COPYFILE_QUIT
        }
        context.progress()
        return COPYFILE_CONTINUE
    }
}
