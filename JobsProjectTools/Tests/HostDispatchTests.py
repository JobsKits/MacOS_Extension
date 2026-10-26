"""Compile the production host with fake launchers; no Terminal or Git action is executed."""
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[2]
shared = (root / 'JobsProjectTools/Shared/ProjectMenuAction.swift').read_text()
start = shared.index('    static func enabledFeatures()')
end = shared.index('\n}\n\nstruct ProjectMenuRequest', start)
shared = shared[:start] + '''    static func enabledFeatures() -> Set<ProjectMenuAction> { Set(ProjectMenuAction.allCases) }
''' + shared[end:]
host = (root / 'JobsProjectTools/JobsProjectTools/AppDelegate.swift').read_text()
host = host.replace('@main\n', '').replace('private func handle(_ url:', 'func handle(_ url:')
sources = [shared, host]
for relative in ['JobsProjectTools/Shared/GitRepositoryValidator.swift',
                 'JobsAndroidStudioOpener/JobsAndroidStudioFinderSync/XcodeProjectDetector.swift',
                 'JobsAndroidStudioOpener/JobsAndroidStudioFinderSync/FlutterProjectValidator.swift',
                 'JobsGitRollback/JobsGitRollbackShared/GitRollbackMenuContext/GitRollbackMenuContext.swift']:
    sources.append((root / relative).read_text())
stubs = '''import AppKit
enum Launches { static var rollback = 0; static var pull = 0; static var proxy = 0; static var commit = 0 }
struct IDEProjectOpener {
 func open(_ action: ProjectMenuAction, at url: URL, completion: @escaping () -> Void) throws { completion() }
}
struct GitRollbackTerminalLauncher { func launch(projectURL: URL) throws { Launches.rollback += 1 } }
struct GitPullTerminalLauncher { func launch(projectURL: URL) throws { Launches.pull += 1 } }
struct GitProxyTerminalLauncher { func launch() throws { Launches.proxy += 1 } }
struct TerminalOpener {
 enum Action { case gitEmptyCommitPush }
 func openTerminal(from url: URL, action: Action) throws -> URL { Launches.commit += 1; return url }
}
struct GitRemoteResolver {
 func webURL(from url: URL) throws -> URL { URL(string: "https://example.invalid/")! }
 func remoteURLString(from url: URL) throws -> String { "https://example.invalid/" }
}
'''
checks = r'''
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let fm = FileManager.default
try fm.createDirectory(at: root.appendingPathComponent(".git/objects"), withIntermediateDirectories: true)
try fm.createDirectory(at: root.appendingPathComponent(".git/refs"), withIntermediateDirectories: true)
try Data("ref: refs/heads/main\n".utf8).write(to: root.appendingPathComponent(".git/HEAD"))
try Data("[core]\n bare = false\n".utf8).write(to: root.appendingPathComponent(".git/config"))
let host = AppDelegate()
var assertions = 0
func expect(_ value: @autoclosure () -> Bool, _ label: String) {
 assertions += 1
 if !value() { fatalError(label) }
}
func wait() {
 let until = Date().addingTimeInterval(0.2)
 while Date() < until { _ = RunLoop.current.run(mode: .default, before: until) }
}
for action in [ProjectMenuAction.gitRollback, .gitPull, .gitProxy, .gitEmptyCommitPush] {
 let url = ProjectMenuRequest(action: action, fileURL: root).url!
 host.handle(url)
 host.handle(url)
 wait()
}
expect(Launches.rollback == 1, "duplicate rollback URL dispatched once")
expect(Launches.pull == 1, "duplicate pull URL dispatched once")
expect(Launches.proxy == 1, "duplicate proxy URL dispatched once")
expect(Launches.commit == 1, "duplicate empty commit URL dispatched once")
Thread.sleep(forTimeInterval: 1.05)
host.handle(ProjectMenuRequest(action: .gitEmptyCommitPush, fileURL: root).url!)
wait()
expect(Launches.commit == 2, "later deliberate click remains usable")
print("PASS: \(assertions) host dispatch assertions")
'''
with tempfile.TemporaryDirectory(prefix='project-host-') as directory:
    source = pathlib.Path(directory) / 'main.swift'
    binary = pathlib.Path(directory) / 'test'
    source.write_text('\n'.join([stubs] + sources + [checks]))
    subprocess.run(['xcrun', 'swiftc', str(source), '-o', str(binary)], check=True)
    subprocess.run([str(binary), directory], check=True)
