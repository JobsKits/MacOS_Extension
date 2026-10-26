"""Verify production configuration loading without writing the user's configuration."""
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
production = (root / 'Shared/ProjectMenuAction.swift').read_text()
stubs = '''import Foundation
enum XcodeProjectDetector { static func canOpen(_ url: URL) -> Bool { false } }
enum IDEProjectDirectory {
    static func canOpenInAndroidStudio(_ url: URL) -> Bool { false }
    static func canOpenInVSCode(_ url: URL) -> Bool { false }
}
struct GitRepositoryValidator { func isWorkingDirectory(at url: URL) -> Bool { false } }
struct GitRollbackMenuContext { func isWorkingDirectory(at url: URL) -> Bool { false } }
'''
checks = r'''
var assertions = 0
func expect(_ value: @autoclosure () -> Bool, _ message: String) {
    assertions += 1
    if !value() { fatalError(message) }
}
let base = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let realHome = base.appendingPathComponent("真实 Home 中文", isDirectory: true)
let sandboxHome = realHome.appendingPathComponent("Library/Containers/com.jobs.JobsProjectTools.FinderSyncExtension/Data", isDirectory: true)
let realConfiguration = ProjectMenuConfiguration.configurationURL(realHomePath: realHome.path)!
let sandboxConfiguration = ProjectMenuConfiguration.configurationURL(realHomePath: sandboxHome.path)!
try FileManager.default.createDirectory(at: realConfiguration.deletingLastPathComponent(), withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: sandboxConfiguration.deletingLastPathComponent(), withIntermediateDirectories: true)
let all = Set(ProjectMenuAction.allCases)
try Data(ProjectMenuAction.allCases.map(\.rawValue).joined(separator: ",").utf8).write(to: realConfiguration)
try Data("git_remote".utf8).write(to: sandboxConfiguration)
expect(realConfiguration != sandboxConfiguration, "account and sandbox paths must differ")
expect(ProjectMenuConfiguration.enabledFeatures(at: realConfiguration) == all, "external account configuration loads all nine selected actions")
expect(ProjectMenuConfiguration.enabledFeatures(at: sandboxConfiguration) == [.gitRemote], "sandbox configuration is independent and must not shadow the account configuration")
try FileManager.default.removeItem(at: sandboxConfiguration)
expect(ProjectMenuConfiguration.enabledFeatures(at: realConfiguration) == all, "missing sandbox copy does not hide selected actions")
let actualHome = ProjectMenuConfiguration.accountHomeDirectory()
expect(actualHome?.hasPrefix("/") == true, "passwd resolves an absolute account Home")
expect(ProjectMenuConfiguration.fileURL == ProjectMenuConfiguration.configurationURL(realHomePath: actualHome), "production accessor uses the account Home")
expect(ProjectMenuConfiguration.enabledFeatures(at: nil).isEmpty, "unresolved account remains disabled")
expect(ProjectMenuConfiguration.configurationURL(realHomePath: nil) == nil, "nil account path rejected")
expect(ProjectMenuConfiguration.configurationURL(realHomePath: "relative") == nil, "relative account path rejected")
expect(ProjectMenuConfiguration.configurationURL(realHomePath: "/invalid\0home") == nil, "NUL account path rejected")
try Data("git-rollback,unknown\nvscode_opener git-rollback".utf8).write(to: realConfiguration)
expect(ProjectMenuConfiguration.enabledFeatures(at: realConfiguration) == [.gitRollback, .vscode], "known selections preserved, unknown and duplicate entries ignored")
try Data().write(to: realConfiguration)
expect(ProjectMenuConfiguration.enabledFeatures(at: realConfiguration).isEmpty, "empty configuration remains disabled")
try Data([0xff]).write(to: realConfiguration)
expect(ProjectMenuConfiguration.enabledFeatures(at: realConfiguration).isEmpty, "invalid encoding remains disabled")
try FileManager.default.removeItem(at: realConfiguration)
expect(ProjectMenuConfiguration.enabledFeatures(at: realConfiguration).isEmpty, "missing configuration remains disabled")
print("PASS: \(assertions) production configuration assertions")
'''
with tempfile.TemporaryDirectory(prefix='project-configuration-') as directory:
    source = pathlib.Path(directory) / 'main.swift'
    binary = pathlib.Path(directory) / 'test'
    source.write_text('\n'.join([stubs, production, checks]))
    subprocess.run(['xcrun', 'swiftc', str(source), '-o', str(binary)], check=True)
    subprocess.run([str(binary), directory], check=True)
