//
//  SendToReconnectController.swift
//  JobsSendTo
//
//  Created by Jobs on 2026年11月18日，星期三.
//

import Foundation
import Darwin

final class SendToReconnectController {
    enum Probe {
        case ready
        case missing
        case identityChanged
    }

    struct Dependencies {
        var probe: (SendToVolumeProof, @escaping (Result<Probe, Error>) -> Void) -> Void
        var mountShare: (URL, @escaping (Int32) -> Void) -> () -> Void
        var openShare: (URL, @escaping (Bool) -> Void) -> Void
        var schedule: (TimeInterval, @escaping () -> Void) -> () -> Void
        var deliver: (@escaping () -> Void) -> Void
        var delays: [TimeInterval] = [1, 2, 4, 8, 15, 30]
        var maximumAttempts = 8
        var operationTimeout: TimeInterval = 12

        static func live(openShare: @escaping (URL, @escaping (Bool) -> Void) -> Void) -> Dependencies {
            let queue = DispatchQueue(label: "com.jobs.sendto.reconnect-timers")
            return Dependencies(probe: { proof, completion in
                DispatchQueue.global(qos: .utility).async {
                    completion(Result {
                        try SendToReconnectController.probeMounted(proof)
                    })
                }
            }, mountShare: SendToReconnectMount.mount, openShare: openShare,
                                schedule: { delay, action in
                let item = DispatchWorkItem(block: action)
                queue.asyncAfter(deadline: .now() + max(0, delay), execute: item)
                return {
                    item.cancel()
                }
            }, deliver: { action in
                DispatchQueue.main.async(execute: action)
            })
        }
    }

    private struct Session {
        let token: UUID
        let taskID: UUID
        let proof: SendToVolumeProof
        let onState: (SendToReconnectState) -> Void
        let onReady: () -> Void
        var attempts = 0
    }

    private static let registryLock = NSLock()
    private static var tasks: Set<UUID> = []
    private static var endpoints: Set<String> = []
    private let lock = NSLock()
    private let dependencies: Dependencies
    private var session: Session?
    private var latestToken = UUID()
    private var operation: UUID?
    private var scheduledCancel: (() -> Void)?
    private var operationCancel: (() -> Void)?
    private var attemptsByTask: [UUID: Int] = [:]

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    deinit {
        cancel()
    }

    static func isNetworkCode(_ code: Int32) -> Bool {
        return [ENETDOWN, ENETUNREACH, ENETRESET, ECONNABORTED, ECONNRESET,
                ENOTCONN, ETIMEDOUT, EHOSTDOWN, EHOSTUNREACH, ECONNREFUSED, EPIPE, ESTALE].contains(code)
    }

    static func isReconnectable(_ result: SendToResult, destination: SendToVolume) -> Bool {
        return destination.isNetwork && result.resumeAvailable && result.taskID != nil && !result.cancelled &&
            !result.failures.isEmpty && result.failures.allSatisfy {
                $0.systemCode.map(isNetworkCode) == true
            }
    }

    // A share URL is only a reconnection hint; the original persisted proof remains the authority.
    static func validatedReconnectURL(_ proof: SendToVolumeProof) -> URL? {
        guard let endpoint = proof.networkEndpoint, let url = proof.reconnectURL,
              let value = URLComponents(url: url, resolvingAgainstBaseURL: false),
              value.scheme == (proof.fsType == "smbfs" ? "smb" : (proof.fsType == "afpfs" ? "afp" : "")),
              value.user == nil, value.password == nil, value.query == nil, value.fragment == nil,
              let host = value.percentEncodedHost, !host.isEmpty,
              value.path.hasPrefix("/"), value.path != "/",
              !(host + value.path).unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) else {
            return nil
        }
        let authority = host.lowercased() + (value.port.map { ":\($0)" } ?? "")
        let paths = Set([value.path, value.percentEncodedPath])
        guard paths.contains(where: {
            SendToPersistentIO.digest(Data((proof.fsType + ":" + authority + $0).utf8)) == endpoint
        }) else {
            return nil
        }
        return url
    }

    @discardableResult
    func start(taskID: UUID, proof: SendToVolumeProof,
               onState: @escaping (SendToReconnectState) -> Void, onReady: @escaping () -> Void) -> Bool {
        guard let endpoint = proof.networkEndpoint else {
            return false
        }
        lock.lock()
        guard session == nil else {
            lock.unlock()
            return false
        }
        let previousAttempts = attemptsByTask[taskID] ?? 0
        guard previousAttempts < dependencies.maximumAttempts else {
            lock.unlock()
            onState(.stopped("自动续接已达到本窗口的重试上限；断点保留，请检查共享连接后显式重试。"))
            return false
        }
        Self.registryLock.lock()
        guard !Self.tasks.contains(taskID), !Self.endpoints.contains(endpoint) else {
            Self.registryLock.unlock()
            lock.unlock()
            return false
        }
        Self.tasks.insert(taskID)
        Self.endpoints.insert(endpoint)
        Self.registryLock.unlock()
        let token = UUID()
        latestToken = token
        session = Session(token: token, taskID: taskID, proof: proof, onState: onState, onReady: onReady,
                          attempts: previousAttempts)
        lock.unlock()
        wait(token, attempt: previousAttempts, delay: delay(previousAttempts + 1))
        return true
    }

    @discardableResult
    func resetRetryBudget(taskID: UUID) -> Bool {
        lock.lock()
        defer {
            lock.unlock()
        }
        guard session == nil else {
            return false
        }
        attemptsByTask.removeValue(forKey: taskID)
        return true
    }

    func cancel() {
        lock.lock()
        let previous = session
        let pending = scheduledCancel
        let running = operationCancel
        let token = UUID()
        latestToken = token
        session = nil
        operation = nil
        scheduledCancel = nil
        operationCancel = nil
        lock.unlock()
        pending?()
        running?()
        if let previous {
            release(previous)
            emit(token, callback: previous.onState, state: .cancelled)
        }
    }

    // This is only called by an explicit user action after an authentication/permission stop.
    func requestInteractiveConnection(proof: SendToVolumeProof, completion: @escaping (Bool) -> Void) {
        guard let url = Self.validatedReconnectURL(proof) else {
            completion(false)
            return
        }
        lock.lock()
        let token = latestToken
        lock.unlock()
        dependencies.deliver { [weak self] in
            guard let self else {
                return
            }
            self.lock.lock()
            let valid = self.latestToken == token && self.session == nil
            self.lock.unlock()
            if valid {
                self.dependencies.openShare(url, completion)
            }
        }
    }

    private func current(_ token: UUID) -> Session? {
        lock.lock()
        defer {
            lock.unlock()
        }
        return session?.token == token ? session : nil
    }

    private func emit(_ token: UUID, callback: @escaping (SendToReconnectState) -> Void, state: SendToReconnectState) {
        dependencies.deliver { [weak self] in
            guard let self else {
                return
            }
            self.lock.lock()
            let valid = self.latestToken == token
            self.lock.unlock()
            if valid {
                callback(state)
            }
        }
    }

    private func delay(_ attempt: Int) -> TimeInterval {
        let values = dependencies.delays.isEmpty ? [30] : dependencies.delays
        return max(0.1, values[min(max(0, attempt - 1), values.count - 1)])
    }

    private func wait(_ token: UUID, attempt: Int, delay: TimeInterval) {
        guard let value = current(token) else {
            return
        }
        if attempt >= dependencies.maximumAttempts {
            finish(token, state: .stopped("网络目标未在重试范围内恢复；断点保留，可检查连接后再试。"))
            return
        }
        emit(token, callback: value.onState, state: .waiting(attempt: attempt, retryAfter: delay))
        lock.lock()
        if session?.token == token {
            scheduledCancel = dependencies.schedule(delay) { [weak self] in
                self?.tick(token)
            }
        }
        lock.unlock()
    }

    private func tick(_ token: UUID) {
        lock.lock()
        guard session?.token == token else {
            lock.unlock()
            return
        }
        session!.attempts += 1
        let attempt = session!.attempts
        attemptsByTask[session!.taskID] = attempt
        scheduledCancel = nil
        lock.unlock()
        probe(token, attempt: attempt, mayMount: true)
    }

    private func begin(_ token: UUID, timeout: @escaping () -> Void) -> UUID? {
        lock.lock()
        defer {
            lock.unlock()
        }
        guard session?.token == token else {
            return nil
        }
        let identifier = UUID()
        operation = identifier
        scheduledCancel = dependencies.schedule(dependencies.operationTimeout) { [weak self] in
            guard let self, self.complete(token, operation: identifier, cancelRunning: true) else {
                return
            }
            timeout()
        }
        return identifier
    }

    private func complete(_ token: UUID, operation identifier: UUID, cancelRunning: Bool = false) -> Bool {
        lock.lock()
        guard session?.token == token, operation == identifier else {
            lock.unlock()
            return false
        }
        operation = nil
        let timer = scheduledCancel
        let running = operationCancel
        scheduledCancel = nil
        operationCancel = nil
        lock.unlock()
        timer?()
        if cancelRunning {
            running?()
        }
        return true
    }

    private func probe(_ token: UUID, attempt: Int, mayMount: Bool) {
        guard let value = current(token) else {
            return
        }
        emit(token, callback: value.onState, state: .checking(attempt: attempt))
        guard let identifier = begin(token, timeout: { [weak self] in
            self?.finish(token, state: .stopped("读取网络卷状态超时；已停止自动操作，断点保留。"))
        }) else {
            return
        }
        dependencies.probe(value.proof) { [weak self] result in
            guard let self, self.complete(token, operation: identifier) else {
                return
            }
            switch result {
            /// A mounted stable proof is only permission to ask the original task to revalidate and resume.
            case .success(.ready):
                self.finish(token, state: .ready, ready: true)
            /// A same-path replacement is never treated as an offline original target.
            case .success(.identityChanged):
                self.finish(token, state: .stopped("原目标位置出现其它卷身份；自动续接已停止，原断点保留。"))
            /// Missing mounts may use only the persisted, digest-bound no-credential hint.
            case .success(.missing):
                if mayMount {
                    self.mount(token, attempt: attempt)
                } else {
                    self.wait(token, attempt: attempt, delay: self.delay(attempt))
                }
            /// Known network errors can retry; permissions and unknown failures stop visibly.
            case .failure(let error):
                if case SendToCoreError.system(_, _, let code) = error, Self.isNetworkCode(code) {
                    self.wait(token, attempt: attempt, delay: self.delay(attempt))
                } else {
                    self.finish(token, state: .stopped(error.localizedDescription))
                }
            }
        }
    }

    private func mount(_ token: UUID, attempt: Int) {
        guard let value = current(token) else {
            return
        }
        guard let url = Self.validatedReconnectURL(value.proof) else {
            if value.proof.reconnectURL != nil {
                finish(token, state: .stopped("任务的共享重连提示与原卷摘要不一致；不会连接其它地址。"))
            } else {
                wait(token, attempt: attempt, delay: delay(attempt))
            }
            return
        }
        emit(token, callback: value.onState, state: .mounting(attempt: attempt))
        guard let identifier = begin(token, timeout: { [weak self] in
            guard let self else {
                return
            }
            self.wait(token, attempt: attempt, delay: self.delay(attempt))
        }) else {
            return
        }
        lock.lock()
        guard session?.token == token, operation == identifier else {
            lock.unlock()
            return
        }
        // Serialize issuing a mount with cancellation; even a synchronous API error is delivered later.
        operationCancel = dependencies.mountShare(url) { [weak self] status in
            guard let self else {
                return
            }
            _ = self.dependencies.schedule(0) { [weak self] in
                self?.mounted(token, operation: identifier, attempt: attempt, status: status)
            }
        }
        lock.unlock()
    }

    private func mounted(_ token: UUID, operation identifier: UUID, attempt: Int, status: Int32) {
        guard complete(token, operation: identifier) else {
            return
        }
        if status == 0 || status == EEXIST {
            probe(token, attempt: attempt, mayMount: false)
        } else if Self.isNetworkCode(status) {
            wait(token, attempt: attempt, delay: delay(attempt))
        } else {
            finish(token, state: .stopped("系统后台重连未完成（\(status)）；请检查共享登录／权限后显式连接，原断点保留。"))
        }
    }

    private func release(_ value: Session) {
        Self.registryLock.lock()
        Self.tasks.remove(value.taskID)
        if let endpoint = value.proof.networkEndpoint {
            Self.endpoints.remove(endpoint)
        }
        Self.registryLock.unlock()
    }

    private func finish(_ token: UUID, state: SendToReconnectState, ready: Bool = false) {
        lock.lock()
        guard let value = session, value.token == token else {
            lock.unlock()
            return
        }
        let pending = scheduledCancel
        let running = operationCancel
        session = nil
        operation = nil
        scheduledCancel = nil
        operationCancel = nil
        lock.unlock()
        pending?()
        running?()
        release(value)
        emit(token, callback: value.onState, state: state)
        if ready {
            dependencies.deliver { [weak self] in
                guard let self else {
                    return
                }
                self.lock.lock()
                let valid = self.latestToken == token
                self.lock.unlock()
                if valid {
                    value.onReady()
                }
            }
        }
    }

    static func probeMounted(_ proof: SendToVolumeProof,
                             mounts: [URL]? = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [])) throws -> Probe {
        guard let mounts else {
            throw SendToCoreError.rejected("无法读取系统挂载清单，已停止自动重连。")
        }
        var identityChanged = false
        for mount in mounts {
            do {
                let candidate = try SendToPersistentIO.proof(mount)
                if proof.matches(candidate) {
                    return .ready
                }
                if candidate.rootURL.standardizedFileURL == proof.rootURL.standardizedFileURL {
                    identityChanged = true
                }
            } catch {
                if mount.standardizedFileURL == proof.rootURL.standardizedFileURL {
                    throw error
                }
            }
        }
        return identityChanged ? .identityChanged : .missing
    }
}
