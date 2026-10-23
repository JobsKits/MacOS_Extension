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
sources = [shared, menu]
for relative in ['JobsAndroidStudioOpener/JobsAndroidStudioFinderSync/XcodeProjectDetector.swift',
                 'JobsAndroidStudioOpener/JobsAndroidStudioFinderSync/FlutterProjectValidator.swift',
                 'JobsGitPuller/JobsGitPullShared/GitFolderValidator/GitFolderValidator.swift']:
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
try file("普通 ' $(touch NEVER) ; 中文/code.txt")
try file("ios/App.xcodeproj/project.pbxproj")
try file("ios/App.xcworkspace/contents.xcworkspacedata")
try file("flutter/pubspec.yaml", "name: fixture\ndependencies:\n  flutter:\n    sdk: flutter\n")
try file("flutter/lib/main.dart")
try file("flutter/ios/App.xcodeproj/project.pbxproj")
try file("flutter/App.xcodeproj/project.pbxproj")
try file("package/Package.swift")
try file("invalid/Fake.xcodeproj/not-a-project")
let finder = FinderSync()
let controller = FIFinderSyncController.default()
let git = ["拉取 Git 到最新", "打开 Git 远程地址", "复制 Git 远程地址"]
let editors = ["用 Android Studio 打开项目", "用 VSCode 打开项目"]
for (path, titles) in [("普通 ' $(touch NEVER) ; 中文", editors + git),
                       ("ios", ["用 Xcode 打开项目"] + git),
                       ("ios/App.xcodeproj", ["用 Xcode 打开项目"] + git),
                       ("flutter", editors + git),
                       ("flutter/ios", ["用 Xcode 打开项目"] + git),
                       ("package", ["用 Xcode 打开项目"] + git),
                       ("invalid", editors + git)] {
 let url = root.appendingPathComponent(path)
 for kind in [FIMenuKind.contextualMenuForItems, .contextualMenuForContainer] {
  controller.selected = kind == .contextualMenuForItems ? [url] : nil
  controller.targeted = kind == .contextualMenuForContainer ? url : nil
  let menu = finder.menu(for: kind)!
  expect(menu.items.map(\.title) == titles, "order/visibility for \(path)")
  for item in menu.items {
   expect(item.submenu == nil, "top-level actions")
   _ = (item.target as! NSObject).perform(item.action!, with: item)
   let request = ProjectMenuRequest(url: TestWorkspace.requests.last!)!
   expect(request.fileURL.path == url.path, "path transport")
   expect(request.action.title == item.title, "selector/action transport")
  }
 }
}
controller.selected = [root.appendingPathComponent("普通 ' $(touch NEVER) ; 中文/code.txt")]
expect(finder.menu(for: .contextualMenuForItems)?.items.map(\.title) == editors + Array(git.dropFirst()), "files preserve remote actions but hide pull")
controller.selected = [root, root]
expect(finder.menu(for: .contextualMenuForItems) == nil, "multi-select")
controller.selected = nil
expect(finder.menu(for: .contextualMenuForItems) == nil, "empty selection")
expect(finder.menu(for: .toolbarItemMenu) == nil, "toolbar")
controller.targeted = nil
expect(finder.menu(for: .contextualMenuForContainer) == nil, "unknown container")
controller.targeted = URL(fileURLWithPath: NSHomeDirectoryForUser(NSUserName())!).appendingPathComponent("Desktop")
expect(finder.menu(for: .contextualMenuForContainer) == nil, "desktop hidden")
controller.selected = [root.appendingPathComponent("ios")]
let oldMenu = finder.menu(for: .contextualMenuForItems)!
controller.selected = [root.appendingPathComponent("flutter")]
let before = TestWorkspace.requests.count
_ = (oldMenu.items[0].target as! NSObject).perform(oldMenu.items[0].action!, with: oldMenu.items[0])
expect(TestWorkspace.requests.count == before, "stale Xcode selection rejected")
ProjectMenuConfiguration.enabled = [.vscode, .gitRemoteCopy]
expect(finder.menu(for: .contextualMenuForItems)?.items.map(\.title) == ["用 VSCode 打开项目", "复制 Git 远程地址"], "partial installation")
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
