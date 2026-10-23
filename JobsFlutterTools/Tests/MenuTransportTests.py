import pathlib,subprocess,tempfile
root=pathlib.Path(__file__).resolve().parents[1]
shared=root/'JobsFlutterToolsShared'
sources=[(shared/'FlutterToolsRequest/FlutterToolsRequest.swift').read_text(),(shared/'FlutterProjectValidator/FlutterProjectValidator.swift').read_text(),(root/'JobsFlutterTools/FlutterToolsLauncher/FlutterToolsLauncher.swift').read_text()]
menu=(root/'JobsFlutterToolsFinderSync/FinderSync.swift').read_text().replace('import FinderSync','').replace('NSWorkspace.shared.open(requestURL)','TestWorkspace.open(requestURL)').replace('let alert = NSAlert()', 'let alert = TestAlert()')
stub='''import AppKit
import Foundation
import Darwin
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
 static var failures = 0
 static func open(_ url: URL) -> Bool { requests.append(url); return true }
}
final class TestAlert {
 var alertStyle: NSAlert.Style = .warning
 var messageText = ""
 var informativeText = ""
 func addButton(withTitle title: String) {}
 func runModal() { TestWorkspace.failures += 1 }
}
'''
checks=r'''
var assertions = 0
func expect(_ condition: @autoclosure () -> Bool, _ message: String) { assertions += 1; if !condition() { fatalError(message) } }
let base = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let project = base.appendingPathComponent("工程 ' $(touch NEVER) ; space")
try FileManager.default.createDirectory(at: project.appendingPathComponent("lib"), withIntermediateDirectories: true)
try "name: fixture\ndependencies:\n  flutter:\n    sdk: flutter\n".write(to: project.appendingPathComponent("pubspec.yaml"), atomically: true, encoding: .utf8)
let controller = FIFinderSyncController.default()
let ordinary = base.appendingPathComponent("ordinary", isDirectory: true)
try FileManager.default.createDirectory(at: ordinary, withIntermediateDirectories: true)
let singleFile = project.appendingPathComponent("lib/main.dart")
try "void main() {}\n".write(to: singleFile, atomically: true, encoding: .utf8)
let projectLink = base.appendingPathComponent("project-link", isDirectory: true)
try FileManager.default.createSymbolicLink(at: projectLink, withDestinationURL: project)
controller.selected = [project]
let provider = FinderSync()
func setContext(_ url: URL?, for kind: FIMenuKind) {
 controller.selected = kind == .contextualMenuForItems ? url.map { [$0] } : nil
 controller.targeted = kind == .contextualMenuForContainer ? url : nil
}
func leafItems(_ menu: NSMenu) -> [NSMenuItem] {
 menu.items.flatMap { item in item.submenu.map(leafItems) ?? [item] }
}
let actions: [FlutterToolsAction] = [.run,.pubGet,.extract,.sdkVersion,.sdkManage,.harmonySdkManage,.javaManage] + FlutterToolsAction.packaging + [.codegen] + FlutterToolsAction.doctors + FlutterToolsAction.repairs + FlutterToolsAction.cleaning
for kind in [FIMenuKind.contextualMenuForItems, .contextualMenuForContainer] {
 controller.selected = kind == .contextualMenuForItems ? [project] : nil
 controller.targeted = kind == .contextualMenuForContainer ? project : nil
 let menu = provider.menu(for: kind)!
 expect(menu.items.map(\.title) == ["Flutter开发相关辅助工具"], "one root menu")
 let development = menu.items[0].submenu!
 expect(development.items.map(\.title) == ["运行Flutter项目","拉取Flutter第三方依赖","提取Flutter第三方依赖","查看当前Flutter项目的SDK版本","安装/切换Flutter SDK版本","安装/切换 Flutter@OpenHarmony SDK","安装/切换Java环境","Flutter打包","Flutter自动化生产代码","Flutter项目体检","Flutter项目修复","Flutter清理维护工具"], "development fixed order")
 expect(development.items[7].submenu!.items.map(\.title) == ["iOS", "Android", "鸿蒙"], "packaging platforms")
 expect(!(development.items[7].target is FinderSync), "packaging parent does not launch a terminal")
 expect(development.items[9].submenu!.items.map(\.title) == ["原生Flutter项目体检", "鸿蒙Flutter环境体检"], "doctors")
 expect(development.items[10].submenu!.items.map(\.title) == ["修复 Android SDK / platforms 缺失","修复 Flutter 项目中文路径","修复 Flutter 插件 namespace","修复 Dart 相对 import 为 package 引用"], "nested repairs")
 expect(development.items[11].submenu!.items.map(\.title) == ["清理当前项目构建产物", "依赖与缓存维护"], "nested project cleaning and SDK maintenance")
 expect(!(development.items[11].target is FinderSync), "cleaning parent does not launch a terminal")
 let leaves = leafItems(menu)
 expect(leaves.count == actions.count, "all actions remain available")
 for (index,item) in leaves.enumerated() {
  _ = (item.target as! NSObject).perform(item.action!, with: item)
  let request = TestWorkspace.requests.last!
  expect(FlutterToolsRequest.action(from: request) == actions[index], "action transport")
  expect(FlutterToolsRequest.projectURL(from: request)?.path == project.path, "path transport")
 }
 let importRepair = development.items[10].submenu!.items.last!
 let requestCount = TestWorkspace.requests.count
 let failureCount = TestWorkspace.failures
 setContext(ordinary, for: kind)
 _ = (importRepair.target as! NSObject).perform(importRepair.action!, with: importRepair)
 expect(TestWorkspace.requests.count == requestCount, "changed non-Flutter context must not dispatch import repair")
 expect(TestWorkspace.failures == failureCount + 1, "changed context reports failure")
 setContext(project, for: kind)
 try "name: fixture\ndependencies: {}\n".write(to: project.appendingPathComponent("pubspec.yaml"), atomically: true, encoding: .utf8)
 _ = (importRepair.target as! NSObject).perform(importRepair.action!, with: importRepair)
 expect(TestWorkspace.requests.count == requestCount, "project losing Flutter declaration must not dispatch import repair")
 expect(TestWorkspace.failures == failureCount + 2, "changed manifest reports failure")
 try "name: fixture\ndependencies:\n  flutter:\n    sdk: flutter\n".write(to: project.appendingPathComponent("pubspec.yaml"), atomically: true, encoding: .utf8)
}
for kind in [FIMenuKind.contextualMenuForItems, .contextualMenuForContainer] {
 for (url, reason) in [(ordinary, "ordinary directory"), (project.appendingPathComponent("lib"), "lib child directory"), (singleFile, "single Dart file"), (projectLink, "symbolic link")] {
  setContext(url, for: kind)
  expect(provider.menu(for: kind) == nil, "hide all Flutter actions for \(reason)")
 }
}
controller.selected = [project,base]
expect(provider.menu(for: .contextualMenuForItems) == nil, "multiple selection")
controller.selected = nil
controller.targeted=URL(fileURLWithPath:String(cString:getpwuid(getuid())!.pointee.pw_dir)).appendingPathComponent("Desktop")
expect(provider.menu(for: .contextualMenuForContainer) == nil,"desktop excluded")
expect(FlutterToolsRequest.action(from:URL(string:"jobsfluttertools://maintenance?path=/legacy")!) == .maintenance,"legacy maintenance URL stays valid")
expect(FlutterToolsRequest.action(from:URL(string:"jobsfluttertools://repair-package-imports?path=/project")!) == .repairPackageImports,"package import repair URL")
for value in ["jobsfluttertools://unknown?path=/a","jobsfluttertools://package-macos?path=/a","jobsfluttertools://run?path=/a&path=/b","jobsfluttertools://run?path=relative","jobsfluttertools://run?path=/a%00b","jobsfluttertools://user@run?path=/a","jobsfluttertools://run:12?path=/a","jobsfluttertools://run/extra?path=/a","jobsfluttertools://run?path=/a#fragment"] {
 expect(FlutterToolsRequest.action(from:URL(string:value)!) == nil,"reject ambiguous request")
}
let tools=base.appendingPathComponent("stub-tools")
try FileManager.default.createDirectory(at:tools,withIntermediateDirectories:true)
try "#!/bin/zsh\n/usr/bin/printf '%s\\0' \"$@\" > \"$JOBS_TEST_ARGS\"\nexit 19\n".write(to:tools.appendingPathComponent("DispatchFlutterTools.zsh"),atomically:true,encoding:.utf8)
for action in [FlutterToolsAction.repairNamespace, .repairPackageImports, .cleanBuildArtifacts, .maintenance, .harmonySdkManage, .javaManage] + FlutterToolsAction.packaging {
let request=try FlutterToolsLauncher().prepare(projectURL:project,action:action,toolsURL:tools)
let attributes=try FileManager.default.attributesOfItem(atPath:request.directoryURL.path)
expect((attributes[.posixPermissions] as! NSNumber).intValue == 0o700,"private carrier")
let argsFile=base.appendingPathComponent("args")
let process=Process();process.executableURL=URL(fileURLWithPath:"/bin/zsh");process.arguments=["-f","-c",request.commandLine.replacingOccurrences(of:"/bin/zsh -l ",with:"/bin/zsh -f ")];process.environment=ProcessInfo.processInfo.environment.merging(["JOBS_TEST_ARGS":argsFile.path]){_,new in new}
try process.run();process.waitUntilExit()
expect(process.terminationStatus == 19,"preserve worker error")
let args=String(decoding:try Data(contentsOf:argsFile),as:UTF8.self).split(separator:"\0").map(String.init)
expect(args == [action.rawValue,project.path],"shell metacharacters remain data")
expect(!FileManager.default.fileExists(atPath:request.directoryURL.path),"private carrier cleanup")
expect(!FileManager.default.fileExists(atPath:base.appendingPathComponent("NEVER").path),"no command substitution")
}
print("PASS: \(assertions) menu and transport assertions")
'''
with tempfile.TemporaryDirectory(prefix='jobs-flutter-menu-') as temp:
 p=pathlib.Path(temp);(p/'main.swift').write_text(stub+'\n'+'\n'.join(sources)+'\n'+menu+'\n'+checks)
 subprocess.run(['/usr/bin/xcrun','swiftc',str(p/'main.swift'),'-o',str(p/'check')],check=True)
 subprocess.run([str(p/'check'),str(p)],check=True)
