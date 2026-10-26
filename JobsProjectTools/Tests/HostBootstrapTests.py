"""Run the production host entry with a weak delegate and fake application loop."""

import json
import pathlib
import re
import subprocess
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[1]

STUBS = r'''import AppKit

enum BootstrapChecks {
    static var assertions = 0
    static var mainCalls = 0

    static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        if !value() {
            fatalError(message)
        }
    }
}

final class TestApplication {
    static let shared = TestApplication()
    var delegateAssignments = 0
    var terminations = 0
    var terminatedOnMain = false
    weak var delegate: NSApplicationDelegate? {
        didSet {
            delegateAssignments += 1
        }
    }

    func terminate(_ sender: Any?) {
        terminations += 1
        terminatedOnMain = Thread.isMainThread
    }
}

final class TestAppleEventManager {
    static let instance = TestAppleEventManager()
    weak var handler: AnyObject?
    var selector: Selector?
    var eventClass: AEEventClass?
    var eventID: AEEventID?

    static func shared() -> TestAppleEventManager {
        return instance
    }

    func setEventHandler(_ object: Any, andSelector selector: Selector,
                         forEventClass eventClass: AEEventClass, andEventID eventID: AEEventID) {
        handler = object as AnyObject
        self.selector = selector
        self.eventClass = eventClass
        self.eventID = eventID
    }
}

// Business launchers stay inert; this regression only enters the real host lifecycle.
enum ProjectMenuAction: String, CaseIterable {
    case androidStudio, vscode, xcode, gitSourcetree, gitPull, gitRollback
    case gitProxy, gitEmptyCommitPush, gitRemote, gitRemoteCopy

    static func visible(at url: URL, enabled: Set<Self>) -> [Self] {
        return []
    }
}
enum ProjectMenuConfiguration {
    static func enabledFeatures() -> Set<ProjectMenuAction> {
        return []
    }
}
struct ProjectMenuRequest {
    let action = ProjectMenuAction.gitSourcetree
    let fileURL = URL(fileURLWithPath: "/")
    let url: URL? = nil

    init?(url: URL) {
        return nil
    }
}
struct IDEProjectOpener {
    func open(_ action: ProjectMenuAction, at url: URL, completion: @escaping () -> Void) throws {
        fatalError("bootstrap must not dispatch an IDE")
    }
}
struct SourcetreeProjectOpener {
    func open(at url: URL, completion: @escaping () -> Void) throws {
        fatalError("bootstrap must not open Sourcetree")
    }
}
struct GitPullTerminalLauncher {
    func launch(projectURL: URL) throws {
        fatalError("bootstrap must not pull Git")
    }
}
struct GitRollbackTerminalLauncher {
    func launch(projectURL: URL) throws {
        fatalError("bootstrap must not roll back Git")
    }
}
struct GitProxyTerminalLauncher {
    func launch() throws {
        fatalError("bootstrap must not configure a proxy")
    }
}
struct TerminalOpener {
    enum Action {
        case gitEmptyCommitPush
    }

    func openTerminal(from url: URL, action: Action) throws -> URL {
        fatalError("bootstrap must not open Terminal")
    }
}
struct GitRemoteResolver {
    func webURL(from url: URL) throws -> URL {
        fatalError("bootstrap must not resolve a remote")
    }

    func remoteURLString(from url: URL) throws -> String {
        fatalError("bootstrap must not copy a remote")
    }
}

func TestApplicationMain(_ argc: Int32, _ argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Int32 {
    BootstrapChecks.mainCalls += 1
    BootstrapChecks.expect(argc > 0 && argv[0] != nil, "real command line reaches the application entry")
    BootstrapChecks.expect(TestApplication.shared.delegateAssignments == 1, "delegate is attached once before application main")
    BootstrapChecks.expect(TestApplication.shared.delegate is AppDelegate, "application main already has the production delegate")
    BootstrapChecks.expect(TestAppleEventManager.instance.handler == nil, "URL handler has not been registered before launch lifecycle")

    autoreleasepool {
        (TestApplication.shared.delegate as? AppDelegate)?.applicationWillFinishLaunching(
            Notification(name: NSApplication.willFinishLaunchingNotification))
    }
    BootstrapChecks.expect(TestApplication.shared.delegate != nil, "entry strongly retains delegate through autorelease pool")
    BootstrapChecks.expect(TestAppleEventManager.instance.handler === TestApplication.shared.delegate,
                           "will-finish lifecycle registers the actual delegate as URL handler")
    BootstrapChecks.expect(TestAppleEventManager.instance.selector != nil, "URL selector is registered")
    BootstrapChecks.expect(TestAppleEventManager.instance.eventClass == AEEventClass(kInternetEventClass)
                           && TestAppleEventManager.instance.eventID == AEEventID(kAEGetURL),
                           "cold-start handler listens for the Get URL AppleEvent")
    (TestApplication.shared.delegate as? AppDelegate)?.applicationDidFinishLaunching(
        Notification(name: NSApplication.didFinishLaunchingNotification))
    BootstrapChecks.expect(TestApplication.shared.terminations == 0, "idle exit waits for the lifecycle timer")

    let deadline = Date().addingTimeInterval(2)
    while TestApplication.shared.terminations == 0, Date() < deadline {
        _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
    }
    BootstrapChecks.expect(TestApplication.shared.delegate != nil, "weak application delegate remains alive throughout event loop")
    BootstrapChecks.expect(TestAppleEventManager.instance.handler != nil, "weak URL handler remains alive throughout event loop")
    BootstrapChecks.expect(TestApplication.shared.terminations == 1, "production did-finish lifecycle exits idle host once")
    BootstrapChecks.expect(TestApplication.shared.terminatedOnMain, "idle host exit runs on the main thread")
    return 0
}
'''

AFTER_ENTRY = r'''
BootstrapChecks.expect(BootstrapChecks.mainCalls == 1, "production entry enters application main once")
BootstrapChecks.expect(TestApplication.shared.delegate != nil, "entry keeps delegate strongly held after the fake main returns")
print("PASS: \(BootstrapChecks.assertions) host bootstrap assertions")
'''


def check_target_membership() -> None:
    project = ROOT / 'JobsProjectTools.xcodeproj/project.pbxproj'
    converted = subprocess.run(
        ['plutil', '-convert', 'json', '-o', '-', str(project)],
        check=True,
        capture_output=True,
        text=True,
    )
    objects = json.loads(converted.stdout)['objects']
    references = {
        identifier
        for identifier, value in objects.items()
        if value.get('isa') == 'PBXFileReference' and value.get('path') == 'main.swift'
    }
    assert len(references) == 1, 'one main.swift reference must exist'
    reference = next(iter(references))
    source_targets = []
    for target in objects.values():
        if target.get('isa') != 'PBXNativeTarget':
            continue
        for phase_id in target['buildPhases']:
            phase = objects[phase_id]
            if phase.get('isa') != 'PBXSourcesBuildPhase':
                continue
            for build_id in phase['files']:
                if objects[build_id].get('fileRef') == reference:
                    source_targets.append(target['name'])
    assert source_targets == ['JobsProjectTools'], 'main.swift must belong only to the host source phase'
    assert any(
        group.get('isa') == 'PBXGroup'
        and group.get('path') == 'JobsProjectTools'
        and reference in group.get('children', [])
        for group in objects.values()
    ), 'main.swift must resolve inside the host source directory'


def main() -> None:
    check_target_membership()
    host = (ROOT / 'JobsProjectTools/AppDelegate.swift').read_text(encoding='utf-8')
    assert not re.search(r'^\s*@main\b', host, re.MULTILINE), 'delegate must not define a competing @main entry'
    host = host.replace('NSAppleEventManager.shared()', 'TestAppleEventManager.shared()')
    host = host.replace('NSApp.terminate(nil)', 'TestApplication.shared.terminate(nil)')
    entry = (ROOT / 'JobsProjectTools/main.swift').read_text(encoding='utf-8')
    assert 'NSApplication.shared' in entry and 'NSApplicationMain(' in entry, 'production entry must attach and start application'
    entry = entry.replace('NSApplication.shared', 'TestApplication.shared')
    entry = entry.replace('NSApplicationMain(', 'TestApplicationMain(')
    with tempfile.TemporaryDirectory(prefix='project-bootstrap-') as directory:
        fixture = pathlib.Path(directory)
        source = fixture / 'main.swift'
        binary = fixture / 'test'
        source.write_text('\n'.join([STUBS, host, entry, AFTER_ENTRY]), encoding='utf-8')
        subprocess.run(['xcrun', 'swiftc', str(source), '-o', str(binary)], check=True)
        subprocess.run([str(binary)], check=True)
    print('PASS: host target membership and single entry checks')


if __name__ == '__main__':
    main()
