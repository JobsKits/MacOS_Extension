"""Exercise production Sourcetree discovery and opening without launching an app."""

import pathlib
import subprocess
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[1]

STUBS = r'''import AppKit

final class TestWorkspace {
    static let shared = TestWorkspace()
    var candidates: [URL] = []
    var queriedIdentifiers: [String] = []
    var openedURLs: [[URL]] = []
    var applications: [URL] = []
    var activations: [Bool] = []
    var pending: ((NSRunningApplication?, Error?) -> Void)?

    func urlsForApplications(withBundleIdentifier identifier: String) -> [URL] {
        queriedIdentifiers.append(identifier)
        return candidates
    }

    func open(_ urls: [URL], withApplicationAt application: URL,
              configuration: NSWorkspace.OpenConfiguration,
              completionHandler: @escaping (NSRunningApplication?, Error?) -> Void) {
        openedURLs.append(urls)
        applications.append(application)
        activations.append(configuration.activates)
        pending = completionHandler
    }
}

enum AppDelegate {
    static var failures: [String] = []
    static var failureOnMain: [Bool] = []

    static func showFailure(_ message: String) {
        failures.append(message)
        failureOnMain.append(Thread.isMainThread)
    }
}
'''

CHECKS = r'''
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let fm = FileManager.default
let workspace = TestWorkspace.shared
var assertions = 0

func expect(_ value: @autoclosure () -> Bool, _ message: String) {
    assertions += 1
    if !value() {
        fatalError(message)
    }
}

func write(_ url: URL, _ data: Data) throws {
    try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url)
}

func app(_ name: String, identifier: String = SourcetreeApplication.bundleIdentifier,
         executable: Bool = true, permissions: Int = 0o700) throws -> URL {
    let url = root.appendingPathComponent(name + ".app", isDirectory: true)
    let plist: [String: Any] = [
        "CFBundleIdentifier": identifier,
        "CFBundleName": name,
        "CFBundleExecutable": "Fixture",
        "CFBundlePackageType": "APPL"
    ]
    let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    try write(url.appendingPathComponent("Contents/Info.plist"), data)
    if executable {
        let binary = url.appendingPathComponent("Contents/MacOS/Fixture")
        try write(binary, Data("fixture; never executed".utf8))
        try fm.setAttributes([.posixPermissions: permissions], ofItemAtPath: binary.path)
    }
    return url
}

func repository(_ url: URL) throws {
    let metadata = url.appendingPathComponent(".git", isDirectory: true)
    try fm.createDirectory(at: metadata.appendingPathComponent("objects"), withIntermediateDirectories: true)
    try fm.createDirectory(at: metadata.appendingPathComponent("refs"), withIntermediateDirectories: true)
    try write(metadata.appendingPathComponent("HEAD"), Data("ref: refs/heads/main\n".utf8))
    try write(metadata.appendingPathComponent("config"), Data("[core]\n bare = false\n".utf8))
}

func drain(until completed: @autoclosure () -> Bool) {
    let deadline = Date().addingTimeInterval(2)
    while !completed(), Date() < deadline {
        _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
    }
    expect(completed(), "asynchronous callback completed before deadline")
}

func completeOnBackground(_ error: Error? = nil) {
    guard let pending = workspace.pending else {
        fatalError("missing open callback")
    }
    workspace.pending = nil
    DispatchQueue.global(qos: .userInitiated).async {
        pending(nil, error)
    }
}

workspace.candidates = []
expect(SourcetreeApplication.installedURL() == nil, "no registered application stays hidden")
expect(!SourcetreeApplication.isUsableApplication(at: URL(string: "https://example.invalid/Sourcetree.app")!),
       "network URL is not an installed application")

let ordinary = root.appendingPathComponent("ordinary", isDirectory: true)
try fm.createDirectory(at: ordinary, withIntermediateDirectories: true)
let wrongID = try app("Wrong", identifier: "invalid.other.application")
let missingExecutable = try app("MissingExecutable", executable: false)
let notExecutable = try app("NotExecutable", permissions: 0o600)
let removed = try app("Removed")
try fm.removeItem(at: removed)
for invalid in [ordinary, wrongID, missingExecutable, notExecutable, removed] {
    workspace.candidates = [invalid]
    expect(SourcetreeApplication.installedURL() == nil,
           "invalid or stale registration skipped: \(invalid.lastPathComponent)")
}

let installed = try app("Sourcetree 中文 & ' %")
workspace.candidates = [wrongID, installed]
expect(SourcetreeApplication.installedURL() == installed, "later usable candidate wins over stale/wrong candidate")
expect(workspace.queriedIdentifiers.allSatisfy { $0 == SourcetreeApplication.bundleIdentifier },
       "application query remains scoped to Sourcetree")

let outer = root.appendingPathComponent("外层 ' $(touch NEVER); # %", isDirectory: true)
let nested = outer.appendingPathComponent("内层 repo & [child]", isDirectory: true)
let selected = nested.appendingPathComponent("普通子目录", isDirectory: true)
try repository(outer)
try repository(nested)
try fm.createDirectory(at: selected, withIntermediateDirectories: true)
let opener = SourcetreeProjectOpener()
var completions = 0
var completionOnMain = true
try opener.open(at: selected) {
    completions += 1
    completionOnMain = completionOnMain && Thread.isMainThread
}
expect(workspace.openedURLs.count == 1, "opening is dispatched once")
expect(workspace.openedURLs.last == [nested.standardizedFileURL.resolvingSymlinksInPath()],
       "nested selection opens the nearest repository with special characters preserved")
expect(workspace.applications.last == installed, "open uses the validated application URL")
expect(workspace.activations.last == true, "opened repository activates Sourcetree")
expect(completions == 0, "completion waits for workspace callback")
completeOnBackground()
drain(until: completions == 1)
expect(completionOnMain, "completion returns to the main thread")
expect(AppDelegate.failures.isEmpty, "successful opening shows no failure")
expect(!fm.fileExists(atPath: root.appendingPathComponent("NEVER").path), "path text never executes as shell")

try opener.open(at: selected) {
    completions += 1
    completionOnMain = completionOnMain && Thread.isMainThread
}
let openingFailure = NSError(domain: "SourcetreeFixture", code: 7,
                            userInfo: [NSLocalizedDescriptionKey: "fixture open failure 中文"])
completeOnBackground(openingFailure)
drain(until: completions == 2)
expect(AppDelegate.failures == ["fixture open failure 中文"], "workspace error reaches the host failure handler")
expect(AppDelegate.failureOnMain == [true] && completionOnMain, "failure and completion run on the main thread")

let dispatched = workspace.openedURLs.count
workspace.candidates = [installed]
try fm.removeItem(at: installed)
do {
    try opener.open(at: selected) { fatalError("unavailable app must not complete an open") }
    fatalError("app removed since menu creation must be rejected")
} catch {
    expect(error.localizedDescription.contains("Sourcetree"), "removed app produces an actionable error")
}
expect(workspace.openedURLs.count == dispatched, "uninstalled application never receives an open")

let replacement = try app("Replacement")
workspace.candidates = [replacement]
try fm.removeItem(at: nested.appendingPathComponent(".git"))
try write(nested.appendingPathComponent(".git"), Data("invalid marker".utf8))
do {
    try opener.open(at: selected) { fatalError("invalid Git must not complete an open") }
    fatalError("invalid inner Git cannot fall back to the outer repository")
} catch {
    expect(error.localizedDescription.contains("Git"), "changed Git metadata produces an actionable error")
}
expect(workspace.openedURLs.count == dispatched, "invalid repository never receives an open")

let independent = root.appendingPathComponent("independent", isDirectory: true)
try repository(independent)
try fm.removeItem(at: independent.appendingPathComponent(".git"))
do {
    try opener.open(at: independent) { fatalError("removed Git must not complete an open") }
    fatalError("Git removed since menu creation must be rejected")
} catch {
    expect(workspace.openedURLs.count == dispatched, "removed repository never receives an open")
}
print("PASS: \(assertions) Sourcetree behavior assertions")
'''


def main() -> None:
    sources = [STUBS]
    for relative in [
        'Shared/SourcetreeApplication.swift',
        'Shared/GitRepositoryValidator.swift',
        'JobsProjectTools/SourcetreeProjectOpener.swift',
    ]:
        source = (ROOT / relative).read_text(encoding='utf-8')
        sources.append(source.replace('NSWorkspace.shared', 'TestWorkspace.shared'))
    sources.append(CHECKS)
    with tempfile.TemporaryDirectory(prefix='sourcetree-behavior-') as directory:
        fixture = pathlib.Path(directory)
        source = fixture / 'main.swift'
        binary = fixture / 'test'
        source.write_text('\n'.join(sources), encoding='utf-8')
        subprocess.run(['xcrun', 'swiftc', str(source), '-o', str(binary)], check=True)
        subprocess.run([str(binary), directory], check=True)


if __name__ == '__main__':
    main()
