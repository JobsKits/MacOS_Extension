//
//  SendToReconnectTests.swift
//  JobsSendToTests
//
//  Created by Jobs on 2026年11月18日，星期三.
//

import Foundation
import Darwin

@main
struct SendToReconnectTests {
    static var checks = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        precondition(condition(), message)
    }

    final class Clock {
        struct Event {
            let id: UUID
            let time: TimeInterval
            let action: () -> Void
        }
        var now: TimeInterval = 0
        var events: [Event] = []
        var cancelled: Set<UUID> = []

        func schedule(_ delay: TimeInterval, action: @escaping () -> Void) -> () -> Void {
            let id = UUID()
            events.append(Event(id: id, time: now + delay, action: action))
            return {
                self.cancelled.insert(id)
            }
        }

        @discardableResult
        func next() -> Bool {
            events.removeAll {
                cancelled.contains($0.id)
            }
            guard let index = events.indices.min(by: { events[$0].time < events[$1].time }) else {
                return false
            }
            let event = events.remove(at: index)
            now = event.time
            event.action()
            return true
        }

        func drain() {
            for _ in 0..<200 {
                if !next() {
                    return
                }
            }
            preconditionFailure("Unbounded scheduling")
        }
    }

    final class Fixture {
        let clock = Clock()
        var mounted = false
        var mountStatuses: [Int32] = []
        var states: [SendToReconnectState] = []
        var ready = 0
        var probes = 0
        var mounts = 0
        var interactive = 0
        var mountCancellations = 0
        var probeOverride: ((@escaping (Result<SendToReconnectController.Probe, Error>) -> Void) -> Void)?
        var mountOverride: ((@escaping (Int32) -> Void) -> (() -> Void))?
        var delayedDeliveries: [() -> Void]?

        func controller() -> SendToReconnectController {
            let dependencies = SendToReconnectController.Dependencies(probe: { _, completion in
                self.probes += 1
                if let override = self.probeOverride {
                    override(completion)
                } else {
                    completion(.success(self.mounted ? .ready : .missing))
                }
            }, mountShare: { _, completion in
                self.mounts += 1
                if let override = self.mountOverride {
                    return override(completion)
                }
                let status = self.mountStatuses.isEmpty ? EHOSTUNREACH : self.mountStatuses.removeFirst()
                if status == 0 {
                    self.mounted = true
                }
                completion(status)
                return {}
            }, openShare: { _, completion in
                self.interactive += 1
                completion(true)
            }, schedule: clock.schedule, deliver: { action in
                if self.delayedDeliveries != nil {
                    self.delayedDeliveries!.append(action)
                } else {
                    action()
                }
            })
            return SendToReconnectController(dependencies: dependencies)
        }

        func start(_ controller: SendToReconnectController, id: UUID = UUID(), proof: SendToVolumeProof = SendToReconnectTests.proof()) -> Bool {
            return controller.start(taskID: id, proof: proof, onState: {
                self.states.append($0)
            }, onReady: {
                self.ready += 1
            })
        }
    }

    static func proof(source: String = "nas.local/Share", hint: URL? = nil) -> SendToVolumeProof {
        return SendToVolumeProof(rootURL: URL(fileURLWithPath: "/Volumes/Share"), uuid: nil, fsid: "old-mount",
                                 networkEndpoint: SendToPersistentIO.digest(Data(("smbfs:" + source).utf8)),
                                 fsType: "smbfs", rootIno: 2,
                                 reconnectURL: hint ?? URL(string: "smb://" + source)!)
    }

    static func main() throws {
        let target = SendToVolume(url: URL(fileURLWithPath: "/Volumes/Share"), name: "Share",
                                  identity: SendToIdentity(dev: 1, ino: 2), isNetwork: true)
        for code in [ENETDOWN, ENETUNREACH, ECONNRESET, ENOTCONN, ETIMEDOUT, EHOSTUNREACH, ECONNREFUSED] {
            var result = SendToResult()
            result.taskID = UUID()
            result.resumeAvailable = true
            result.failures = [SendToFailure(source: nil, code: "resume-blocked", message: "ignored", systemCode: code)]
            expect(SendToReconnectController.isReconnectable(result, destination: target), "Known network errno")
        }
        for code in [EACCES, EPERM, ENOSPC, ENOENT, EIO, EINVAL, EAUTH, -5997, -6600] {
            var result = SendToResult()
            result.taskID = UUID()
            result.resumeAvailable = true
            result.failures = [SendToFailure(source: nil, code: "resume-blocked", message: "network unreachable", systemCode: code)]
            expect(!SendToReconnectController.isReconnectable(result, destination: target), "No text-based or unknown-error retry")
        }
        var mixed = SendToResult()
        mixed.taskID = UUID()
        mixed.resumeAvailable = true
        mixed.failures = [SendToFailure(source: nil, code: "resume-blocked", message: "", systemCode: EHOSTUNREACH),
                          SendToFailure(source: nil, code: "journal", message: "source changed")]
        expect(!SendToReconnectController.isReconnectable(mixed, destination: target), "Do not mask additional unsafe failures")
        expect(SendToReconnectController.validatedReconnectURL(proof()) != nil, "Digest-bound SMB hint")
        for source in ["nas.local/中文 空格", "nas.local/中文%20空格", "nas.local/100%25", "nas.local:445/Share", "[fe80::1]:445/Share"] {
            expect(SendToReconnectController.validatedReconnectURL(proof(source: source)) != nil, "Endpoint spelling: " + source)
        }
        for url in ["smb://user:password@nas.local/Share", "smb://nas.local/Share?secret=x", "smb://nas.local/Share#x", "file:///Volumes/Share", "smb://other.local/Share", "smb://nas.local/"] {
            expect(SendToReconnectController.validatedReconnectURL(proof(hint: URL(string: url)!)) == nil, "Reject untrusted hint")
        }
        var oldJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(proof())) as! [String: Any]
        oldJSON.removeValue(forKey: "reconnectURL")
        let old = try JSONDecoder().decode(SendToVolumeProof.self, from: JSONSerialization.data(withJSONObject: oldJSON))
        expect(old.reconnectURL == nil && old.matches(proof()), "Old persisted proofs remain readable and authoritative")
        do {
            _ = try SendToReconnectController.probeMounted(proof(), mounts: nil)
            preconditionFailure("Failed mount enumeration treated as empty")
        } catch {
            expect(true, "Failed enumeration stops")
        }
        do {
            let fixture = Fixture()
            fixture.mountStatuses = [EHOSTUNREACH, 0]
            let controller = fixture.controller()
            expect(fixture.start(controller), "Begin approved task")
            fixture.clock.drain()
            expect(fixture.mounts == 2 && fixture.probes == 3 && fixture.ready == 1, "Offline first mount then real remount and proof verification")
            expect(fixture.interactive == 0, "No automatic Finder or authentication UI")
            expect(fixture.states.contains(.mounting(attempt: 1)) && fixture.states.last == .ready, "Report actual mounting and ready state")
        }
        do {
            let fixture = Fixture()
            fixture.mounted = true
            let controller = fixture.controller()
            let id = UUID()
            for _ in 0..<8 {
                expect(fixture.start(controller, id: id), "Retry original still-mounted task within one total budget")
                fixture.clock.drain()
            }
            expect(!fixture.start(controller, id: id), "Repeated resume failures do not reset eight-attempt budget")
            expect(fixture.probes == 8 && fixture.mounts == 0 && fixture.ready == 8, "Mounted SMB recovery only revalidates, never opens a share")
            expect(controller.resetRetryBudget(taskID: id), "Only explicit user retry resets exhausted budget")
            expect(fixture.start(controller, id: id), "Explicit reset permits another approved attempt")
            controller.cancel()
        }
        do {
            let fixture = Fixture()
            let controller = fixture.controller()
            expect(fixture.start(controller), "Begin bounded offline retry")
            fixture.clock.drain()
            expect(fixture.mounts == 8 && fixture.probes == 8 && fixture.ready == 0, "Exactly eight attempts while offline")
            expect(fixture.clock.now <= 91, "Capped delays have finite total wait with immediate synthetic errors")
            expect(fixture.interactive == 0, "No repeated login UI")
        }
        do {
            let fixture = Fixture()
            fixture.mountStatuses = [EACCES]
            let controller = fixture.controller()
            expect(fixture.start(controller), "Begin authorization-required scenario")
            fixture.clock.drain()
            expect(fixture.mounts == 1 && fixture.ready == 0 && fixture.interactive == 0, "Permission rejection stops without authentication loop")
        }
        do {
            let fixture = Fixture()
            fixture.probeOverride = {
                $0(.success(.identityChanged))
            }
            let controller = fixture.controller()
            expect(fixture.start(controller), "Begin replaced-target scenario")
            fixture.clock.drain()
            expect(fixture.mounts == 0 && fixture.ready == 0, "Identity mismatch cannot remount or resume")
        }
        do {
            let fixture = Fixture()
            var late: ((Int32) -> Void)?
            fixture.mountOverride = { completion in
                late = completion
                return {
                    fixture.mountCancellations += 1
                }
            }
            let controller = fixture.controller()
            expect(fixture.start(controller), "Begin pending mount")
            expect(fixture.clock.next(), "Dispatch first probe and mount")
            controller.cancel()
            late?(0)
            fixture.clock.drain()
            expect(fixture.mountCancellations == 1 && fixture.ready == 0 && fixture.mounts == 1, "Cancel pending NetFS and ignore late success")
            expect(fixture.states.last == .cancelled, "Visible cancellation")
        }
        do {
            let fixture = Fixture()
            let controller = fixture.controller()
            expect(controller.start(taskID: UUID(), proof: proof(), onState: { state in
                fixture.states.append(state)
                if case .mounting = state {
                    controller.cancel()
                }
            }, onReady: { fixture.ready += 1 }), "Begin cancellation immediately before issuing NetFS")
            fixture.clock.drain()
            expect(fixture.mounts == 0 && fixture.ready == 0 && fixture.states.last == .cancelled,
                   "Cancellation before mount invocation never issues a new system request")
        }
        do {
            let fixture = Fixture()
            var callbacks: [(Int32) -> Void] = []
            fixture.mountOverride = { completion in
                callbacks.append(completion)
                return {
                    fixture.mountCancellations += 1
                }
            }
            let controller = fixture.controller()
            expect(fixture.start(controller), "Begin hanging mount")
            fixture.clock.drain()
            expect(fixture.mounts == 8 && fixture.mountCancellations == 8, "Watchdog cancels each hanging request within bounded budget")
            callbacks.forEach {
                $0(0)
            }
            fixture.clock.drain()
            expect(fixture.ready == 0 && fixture.mounts == 8, "Timed-out callbacks never resume or remount")
        }
        do {
            let fixture = Fixture()
            var late: ((Result<SendToReconnectController.Probe, Error>) -> Void)?
            fixture.probeOverride = {
                late = $0
            }
            let controller = fixture.controller()
            expect(fixture.start(controller), "Begin hanging metadata probe")
            fixture.clock.drain()
            late?(.success(.ready))
            expect(fixture.probes == 1 && fixture.mounts == 0 && fixture.ready == 0, "Probe watchdog stops UI wait and ignores later metadata")
        }
        do {
            let fixture = Fixture()
            let other = Fixture()
            let controller = fixture.controller()
            let second = other.controller()
            let id = UUID()
            expect(fixture.start(controller, id: id), "Claim one task and endpoint")
            expect(!other.start(second, id: id) && !other.start(second), "Duplicate task or endpoint cannot start another mount coordinator")
            controller.cancel()
            expect(other.start(second, id: id), "Cancellation releases only this task's lease")
            second.cancel()
        }
        do {
            let fixture = Fixture()
            fixture.delayedDeliveries = []
            fixture.mounted = true
            let controller = fixture.controller()
            expect(fixture.start(controller), "Begin queued delivery scenario")
            fixture.clock.drain()
            controller.cancel()
            fixture.delayedDeliveries!.forEach {
                $0()
            }
            expect(fixture.ready == 0, "Cancel after probe completion suppresses queued resume")
        }
        do {
            let fixture = Fixture()
            fixture.delayedDeliveries = []
            let controller = fixture.controller()
            var completed = false
            controller.requestInteractiveConnection(proof: proof()) { _ in completed = true }
            controller.cancel()
            fixture.delayedDeliveries!.forEach {
                $0()
            }
            expect(fixture.interactive == 0 && !completed, "Cancel suppresses a queued explicit connection before system UI opens")
            fixture.delayedDeliveries = nil
            controller.requestInteractiveConnection(proof: proof()) { opened in completed = opened }
            expect(fixture.interactive == 1 && completed, "An explicit current user request may open the validated share")
        }
        do {
            let fixture = Fixture()
            let controller = fixture.controller()
            expect(fixture.start(controller, proof: old), "Old task can wait for manually restored original mount")
            fixture.clock.drain()
            expect(fixture.probes == 8 && fixture.mounts == 0, "A digest without a URL is never reversed or guessed")
        }
        var cancelCalls = 0
        let request = SendToReconnectMount.Request(cancelRequest: { _ in cancelCalls += 1 })
        request.cancel()
        request.attach(UnsafeMutableRawPointer(bitPattern: 1))
        request.cancel()
        expect(cancelCalls == 1, "Cancel-before-attach claims the handle exactly once")
        expect(!request.complete() && !request.complete(), "Late and repeated completion suppressed")
        let finished = SendToReconnectMount.Request(cancelRequest: { _ in cancelCalls += 1 })
        expect(finished.complete() && !finished.complete(), "Completion delivered once")
        finished.attach(UnsafeMutableRawPointer(bitPattern: 2))
        finished.cancel()
        expect(cancelCalls == 1, "Completed request never retains or cancels a stale handle")
        print("SendTo reconnect passed: \(checks) checks; injected clock/probe/mount only, no real share authentication, mount, disconnect, or transfer.")
    }
}
