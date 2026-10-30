"""Exercise the production menu with real NSMenu/selectors and a fake Finder/workspace."""
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[2]
shared = (root / 'JobsProjectTools/Shared/ProjectMenuAction.swift').read_text()
start = shared.index('    static func enabledFeatures()')
end = shared.index('\n}\n\nstruct ProjectMenuRequest', start)
shared = shared[:start] + '''    static var enabled = Set(ProjectMenuAction.allCases)
    static func enabledFeatures() -> Set<ProjectMenuAction> { enabled }
''' + shared[end:]
menu = (root / 'JobsProjectTools/JobsProjectToolsFinderSync/FinderSync.swift').read_text()
menu = menu.replace('import FinderSync', '').replace('NSWorkspace.shared.open(request)', 'TestWorkspace.open(request)')
sources = [shared, menu, (root / 'JobsProjectTools/Shared/GitRepositoryValidator.swift').read_text()]
for relative in ['JobsAndroidStudioOpener/JobsAndroidStudioFinderSync/XcodeProjectDetector.swift',
                 'JobsAndroidStudioOpener/JobsAndroidStudioFinderSync/FlutterProjectValidator.swift',
                 'JobsGitPuller/JobsGitPullShared/GitFolderValidator/GitFolderValidator.swift',
                 'JobsGitRollback/JobsGitRollbackShared/GitRollbackMenuContext/GitRollbackMenuContext.swift']:
    sources.append((root / relative).read_text())
stub = '''import AppKit
enum FIMenuKind { case contextualMenuForItems, contextualMenuForContainer, toolbarItemMenu }
class FIFinderSync: NSObject { func menu(for kind: FIMenuKind) -> NSMenu? { nil } }
final class FIFinderSyncController {
 static let shared = FIFinderSyncController()
 static func `default`() -> FIFinderSyncController { shared }
 var directoryURLs: Set<URL> = []
 var selected: [URL]?; var targeted: URL?
 func selectedItemURLs() -> [URL]? { selected }
 func targetedURL() -> URL? { targeted }
}
enum TestWorkspace {
 static var requests: [URL] = []
 static func open(_ url: URL) -> Bool { requests.append(url); return true }
}
enum SourcetreeApplication {
 static var installed = true
 static func installedURL() -> URL? { installed ? URL(fileURLWithPath: "/Applications/Sourcetree.app") : nil }
}
'''
checks = r'''

var assertions = 0
func expect(_ value: @autoclosure () -> Bool, _ message: String) {
 assertions += 1
 if !value() { fatalError(message) }
}
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let fm = FileManager.default
func file(_ path: String, _ text: String = "") throws {
 let url = root.appendingPathComponent(path)
 try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
 try Data(text.utf8).write(to: url)
}
func repository(_ path: String, bare: Bool = false) throws {
 try file(path + "/HEAD", "ref: refs/heads/main\n")
 try file(path + "/config", "[core]\n bare = \(bare ? "true" : "false")\n")
 try fm.createDirectory(at: root.appendingPathComponent(path + "/objects"), withIntermediateDirectories: true)
 try fm.createDirectory(at: root.appendingPathComponent(path + "/refs"), withIntermediateDirectories: true)
}
try file("普通 ' $(touch NEVER) ; 中文/code.txt")
try file("ios/App.xcodeproj/project.pbxproj", "SDKROOT = iphoneos;")
try file("flutter/pubspec.yaml", "name: fixture\ndependencies:\n  flutter:\n    sdk: flutter\n")
try file("flutter/lib/main.dart")
try file("package/Package.swift")
try repository("repo/.git")
try file("repo/sub/code.txt")
try file("repo/invalid/.git", "not a git pointer")
try file("repo/dangling/placeholder")
try fm.createSymbolicLink(atPath: root.appendingPathComponent("repo/dangling/.git").path, withDestinationPath: "/nonexistent/jobs-git-marker")
try repository("repo/bare.git", bare: true)
try file("worktree/.git", "gitdir: ../repo/.git/worktrees/linked\n")
try file("repo/.git/worktrees/linked/HEAD", "ref: refs/heads/linked\n")
try file("repo/.git/worktrees/linked/commondir", "../..\n")
try file("submodule/.git", "gitdir: ../repo/.git/modules/child\n")
try repository("repo/.git/modules/child")
let finder = FinderSync()
let controller = FIFinderSyncController.default()
let git = ["⬇️ 拉取 Git 到最新", "⏪ Git 提交回退", "🌐 打开 Git 远程地址", "🔗 复制 Git 远程地址", "📡 配置 Git 动态代理", "📤 在终端创建空白 Commit 并 Push"]
let editors = ["🧭 用 Android Studio 打开项目", "📝 用 VSCode 打开项目"]
let vscode = ["📝 用 VSCode 打开项目"]
for (path, titles) in [("普通 ' $(touch NEVER) ; 中文", vscode),
                       ("ios", ["🛠️ 用 Xcode 打开项目"]),
                       ("ios/App.xcodeproj", ["🛠️ 用 Xcode 打开项目"]),
                       ("flutter", editors), ("package", vscode),
                       ("repo", vscode + ["🌿 Git操作"]), ("repo/sub", vscode + ["🌿 Git操作"]),
                       ("worktree", vscode + ["🌿 Git操作"]), ("submodule", vscode + ["🌿 Git操作"]),
                       ("repo/invalid", vscode), ("repo/dangling", vscode),
                       ("repo/bare.git", vscode), ("repo/.git", vscode)] {
 let url = root.appendingPathComponent(path)
 for kind in [FIMenuKind.contextualMenuForItems, .contextualMenuForContainer] {
  controller.selected = kind == .contextualMenuForItems ? [url] : nil
  controller.targeted = kind == .contextualMenuForContainer ? url : nil
  let menu = finder.menu(for: kind)!
  expect(menu.items.map(\.title) == titles, "order/visibility for \(path)")
  let actualGit = menu.items.first(where: { $0.title == "🌿 Git操作" })?.submenu
  if titles.contains("🌿 Git操作") {
   expect(actualGit?.items.map(\.title) == git, "all six Git actions grouped")
  } else {
   expect(actualGit == nil, "Git hidden outside valid directory")
  }
  let actions = menu.items.flatMap { $0.submenu?.items ?? [$0] }
  for item in actions {
   _ = (item.target as! NSObject).perform(item.action!, with: item)
   let request = ProjectMenuRequest(url: TestWorkspace.requests.last!)!
   expect(request.fileURL.path == url.path, "path transport")
   expect(request.action.title == item.title, "selector/action transport")
  }
 }
}
for path in ["repo/sub/code.txt", "missing"] {
 controller.selected = [root.appendingPathComponent(path)]
 expect(finder.menu(for: .contextualMenuForItems) == nil, "files and missing paths have no IDE menus")
}
try fm.createDirectory(at: root.appendingPathComponent("empty"), withIntermediateDirectories: true)
try file("only-metadata/.DS_Store")
for path in ["empty", "only-metadata"] {
 controller.selected = [root.appendingPathComponent(path)]
 expect(finder.menu(for: .contextualMenuForItems) == nil, "empty directories have no IDE menus")
}
controller.selected = [root.appendingPathComponent("flutter")]
let previousFlutterMenu = finder.menu(for: .contextualMenuForItems)!
try fm.removeItem(at: root.appendingPathComponent("flutter/pubspec.yaml"))
let androidItem = previousFlutterMenu.items.first { $0.title == editors.first }!
let countBeforeChangedType = TestWorkspace.requests.count
_ = (androidItem.target as! NSObject).perform(androidItem.action!, with: androidItem)
expect(TestWorkspace.requests.count == countBeforeChangedType, "Android click rechecks changed project type")

controller.selected = [root, root]
expect(finder.menu(for: .contextualMenuForItems) == nil, "multi-select")
controller.selected = nil
expect(finder.menu(for: .contextualMenuForItems) == nil, "empty selection")
expect(finder.menu(for: .toolbarItemMenu) == nil, "toolbar")
controller.targeted = nil
expect(finder.menu(for: .contextualMenuForContainer) == nil, "unknown container")
controller.targeted = URL(fileURLWithPath: NSHomeDirectoryForUser(NSUserName())!).appendingPathComponent("Desktop")
expect(finder.menu(for: .contextualMenuForContainer) == nil, "desktop hidden")
controller.selected = [root.appendingPathComponent("repo")]
for installed in [false, true] {
 SourcetreeApplication.installed = installed
 expect(finder.menu(for: .contextualMenuForItems)?.items.last?.submenu?.items.map(\.title) == git, "retired Sourcetree entry never appears and other Git actions remain")
 ProjectMenuConfiguration.enabled = [.gitSourcetree]
 expect(finder.menu(for: .contextualMenuForItems) == nil, "legacy Sourcetree-only configuration never creates a menu")
 ProjectMenuConfiguration.enabled = Set(ProjectMenuAction.allCases)
}
expect(GitRepositoryValidator().workingDirectory(at: root.appendingPathComponent("repo/sub")) == root.appendingPathComponent("repo"), "subdirectory resolves to nearest working tree")
expect(GitRepositoryValidator().workingDirectory(at: root.appendingPathComponent("submodule")) == root.appendingPathComponent("submodule"), "submodule keeps its own root")
expect(GitRepositoryValidator().workingDirectory(at: root.appendingPathComponent("worktree")) == root.appendingPathComponent("worktree"), "linked worktree keeps its own root")
ProjectMenuConfiguration.enabled = Set(ProjectMenuAction.allCases)
let oldMenu = finder.menu(for: .contextualMenuForItems)!
let oldGit = oldMenu.items.last!.submenu!.items
controller.selected = [root.appendingPathComponent("flutter")]
let before = TestWorkspace.requests.count
for item in oldGit { _ = (item.target as! NSObject).perform(item.action!, with: item) }
expect(TestWorkspace.requests.count == before, "stale Git selection rejected")
controller.selected = [root.appendingPathComponent("repo")]
ProjectMenuConfiguration.enabled = [.vscode, .gitRemoteCopy]
let partial = finder.menu(for: .contextualMenuForItems)!
expect(partial.items.map(\.title) == ["📝 用 VSCode 打开项目", "🌿 Git操作"], "partial installation")
expect(partial.items.last!.submenu!.items.map(\.title) == ["🔗 复制 Git 远程地址"], "only selected Git feature")
ProjectMenuConfiguration.enabled = [.gitRollback]
expect(finder.menu(for: .contextualMenuForItems)?.items.last?.submenu?.items.map(\.title) == ["⏪ Git 提交回退"], "rollback-only installation")
ProjectMenuConfiguration.enabled = [.gitProxy]
expect(finder.menu(for: .contextualMenuForItems)?.items.map(\.title) == ["🌿 Git操作"], "Git-only installation")
controller.selected = [root.appendingPathComponent("flutter")]
expect(finder.menu(for: .contextualMenuForItems) == nil, "Git-only non-repo hidden")
ProjectMenuConfiguration.enabled = []
expect(finder.menu(for: .contextualMenuForItems) == nil, "all disabled")
for bad in ["jobsprojecttools://perform?path=/a&action=xcode_opener&path=/b",
            "jobsprojecttools://perform?path=relative&action=xcode_opener",
            "jobsprojecttools://perform?path=/a%00b&action=xcode_opener",
            "jobsprojecttools://perform?path=/a&action=unknown",
            "jobsprojecttools://user@perform?path=/a&action=xcode_opener",
            "jobsprojecttools://perform:12?path=/a&action=xcode_opener",
            "jobsprojecttools://perform/extra?path=/a&action=xcode_opener",
            "jobsprojecttools://perform?path=/a&action=xcode_opener#fragment"] {
 expect(ProjectMenuRequest(url: URL(string: bad)!) == nil, "malformed request")
}
print("PASS: \(assertions) grouped menu assertions")

'''
with tempfile.TemporaryDirectory(prefix='project-menu-') as directory:
    source = pathlib.Path(directory) / 'main.swift'
    binary = pathlib.Path(directory) / 'test'
    source.write_text('\n'.join([stub] + sources + [checks]))
    subprocess.run(['xcrun', 'swiftc', str(source), '-o', str(binary)], check=True)
    subprocess.run([str(binary), directory], check=True)

# The three standalone projects carry identical detection sources for independent builds.
detectors = [root / f'Jobs{name}Opener/Jobs{name}FinderSync/XcodeProjectDetector.swift'
             for name in ['AndroidStudio', 'VSCode', 'Xcode']]
assert len({path.read_text() for path in detectors}) == 1
with tempfile.TemporaryDirectory(prefix='ide-detection-') as directory:
    binary = pathlib.Path(directory) / 'test'
    subprocess.run(['xcrun', 'swiftc',
                    str(root / 'JobsAndroidStudioOpener/JobsAndroidStudioFinderSync/FlutterProjectValidator.swift'),
                    str(detectors[0]), str(root / 'JobsProjectTools/Tests/IDEProjectDetectionTests.swift'),
                    '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
