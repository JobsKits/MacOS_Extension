import pathlib,subprocess,tempfile
root=pathlib.Path(__file__).resolve().parents[1]
shared=root/'JobsFlutterToolsShared'
sources=[(shared/'FlutterFeatureConfiguration/FlutterFeatureConfiguration.swift').read_text(),(shared/'FlutterToolsRequest/FlutterToolsRequest.swift').read_text(),(shared/'FlutterProjectValidator/FlutterProjectValidator.swift').read_text(),(root/'JobsFlutterTools/FlutterToolsLauncher/FlutterToolsLauncher.swift').read_text()]
menu=(root/'JobsFlutterToolsFinderSync/FinderSync.swift').read_text().replace('import FinderSync','').replace('NSWorkspace.shared.open(requestURL)','TestWorkspace.open(requestURL)').replace('let alert = NSAlert()', 'let alert = TestAlert()')
stub='''import AppKit
import Foundation
import Darwin
enum FIMenuKind: UInt { case contextualMenuForItems, contextualMenuForContainer, toolbarItemMenu }
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
 static var failureMessages: [String] = []
 static func open(_ url: URL) -> Bool { requests.append(url); return true }
}
final class TestAlert {
 var alertStyle: NSAlert.Style = .warning
 var messageText = ""
 var informativeText = ""
 func addButton(withTitle title: String) {}
 func runModal() { TestWorkspace.failures += 1; TestWorkspace.failureMessages.append(informativeText) }
}
'''
# Override only the compiled fixture, so no real user configuration is read or changed.
config_call='FlutterFeatureConfiguration.enabledFeatures(configurationURL: URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("features.conf"))'
sources=[source.replace('FlutterFeatureConfiguration.enabledFeatures()',config_call) for source in sources]
menu=menu.replace('FlutterFeatureConfiguration.enabledFeatures()',config_call)
checks=r'''
var assertions = 0
func expect(_ condition: @autoclosure () -> Bool, _ message: String) { assertions += 1; if !condition() { fatalError(message) } }
let base = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let project = base.appendingPathComponent("工程 ' $(touch NEVER) ; space")
try FileManager.default.createDirectory(at: project.appendingPathComponent("lib"), withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: project.appendingPathComponent("ohos"), withIntermediateDirectories: true)
for name in ["build-profile.json5", "oh-package.json5"] {
 try "{}".write(to: project.appendingPathComponent("ohos").appendingPathComponent(name), atomically: true, encoding: .utf8)
}
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
expect(FlutterToolsAction.dependencyFetch.map(\.rawValue) == ["pub-get", "android-dependencies", "pods-dependencies", "spm-dependencies", "ohos-dependencies", "web-dependencies"], "network fetch excludes native combo and platform resources")
expect(FlutterToolsAction.dependencyExports.map(\.rawValue) == ["extract", "export-private-dependencies", "export-gradle-dependencies", "export-pods-dependencies", "export-spm-dependencies", "export-ohos-dependencies", "export-native-dependencies", "export-precache-dependencies", "export-web-dependencies"], "export group preserves every raw action")
expect(FlutterToolsAction.dependencyImports.map(\.rawValue) == ["import-dependencies", "import-private-dependencies", "import-gradle-dependencies", "import-pods-dependencies", "import-spm-dependencies", "import-ohos-dependencies", "import-native-dependencies", "import-precache-dependencies", "import-web-dependencies"], "import group preserves every raw action")
expect(FlutterToolsAction.environments.map(\.rawValue) == ["sdk-manage", "ohos-sdk-manage", "java-manage"], "runtime environment children")
expect(FlutterToolsAction.resources.map(\.rawValue) == ["gradle-download", "flutter-precache", "native-dependencies"], "resource and build dependency children")
expect(FlutterToolsAction.doctors.map(\.rawValue) == ["sdk-version", "native-doctor", "harmony-doctor"], "SDK inspection belongs to project inspection")
let actions: [FlutterToolsAction] = [.projectSetup,.run] + FlutterToolsAction.dependencyFetch + FlutterToolsAction.dependencyExports + FlutterToolsAction.dependencyImports + FlutterToolsAction.environments + FlutterToolsAction.resources + FlutterToolsAction.packaging + [.codegen] + FlutterToolsAction.doctors + FlutterToolsAction.repairs + FlutterToolsAction.cleaning
expect(actions.count == 45 && Set(actions) == FlutterFeatureConfiguration.leafActions, "regrouping covers the same 45 unique leaves")
for kind in [FIMenuKind.contextualMenuForItems, .contextualMenuForContainer] {
 controller.selected = kind == .contextualMenuForItems ? [project] : nil
 controller.targeted = kind == .contextualMenuForContainer ? project : nil
 let menu = provider.menu(for: kind)!
 expect(menu.items.map(\.title) == ["🦋 Flutter开发相关辅助工具"], "one root menu")
 let development = menu.items[0].submenu!
 expect(development.items.map(\.title) == ["🚀 一键配置 Flutter 项目","▶️ 从终端运行 Flutter 项目","📥 拉取Flutter项目工程相关依赖","🧩 提取Flutter项目工程依赖","📤 导入Flutter项目工程依赖","🔀 安装/切换Flutter运行环境","🧱 Flutter 资源与构建依赖","📦 Flutter打包","⚙️ Flutter自动化生产代码","🏥 Flutter项目体检","🔧 Flutter项目修复","🧹 Flutter清理维护工具"], "development direct groups follow the requested wording and order")
 expect(development.items[2].submenu!.items.map(\.title) == ["📥 拉取 Flutter Pub 依赖","🤖 拉取 Android 原生依赖","🥥 拉取 CocoaPods 依赖","🧬 拉取 Swift Package 依赖","🕊️ 拉取 OpenHarmony 依赖","🌐 拉取 Web 工程依赖"], "network fetch group has only network package operations")
 expect(development.items[3].submenu!.items.map(\.title) == FlutterToolsAction.dependencyExports.map(\.title), "extract group contains Pub and every export action")
 expect(development.items[4].submenu!.items.map(\.title) == FlutterToolsAction.dependencyImports.map(\.title), "import group contains Pub and every import action")
 expect(development.items[5].submenu!.items.map(\.title) == ["🔀 安装/切换Flutter SDK","🕊️ 安装/切换Flutter@OpenHarmony SDK","☕ 安装/切换Java SDK"], "environment names match the request")
 expect(development.items[6].submenu!.items.map(\.title) == ["📚 下载Gradled分发与构建插件","🗃️ 下载Flutter平台资源","🧱 准备原生库与构建依赖（组合操作）"], "resources include the native build preparation combo")
 expect(development.items[7].submenu!.items.map(\.title) == ["🍏 iOS", "🤖 Android", "📦 打包鸿蒙（HAP + APP）"], "packaging platforms")
 expect(development.items[9].submenu!.items.map(\.title) == ["🔎 查看当前Flutter项目工程的SDK版本","🧑‍⚕️ 原生Flutter项目体检", "💓 OpenHarmony Flutter 环境体检"], "SDK version is nested in inspection")
 expect(development.items[10].submenu!.items.map(\.title) == ["🩹 修复 Android SDK / platforms 缺失","🈶 修复 Flutter 项目中文路径","🏷️ 修复 Flutter 插件 namespace","🔤 修复 Dart 相对 import 为 package 引用"], "nested repairs")
 expect(development.items[11].submenu!.items.map(\.title) == ["🗑️ 清理当前 Flutter 项目构建产物", "♻️ 依赖与缓存维护"], "nested cleaning")
 for index in [2,3,4,5,6,7,9,10,11] {
  expect(development.items[index].submenu != nil && !(development.items[index].target is FinderSync), "group parent expands its submenu without a Finder business target")
 }
 func checkEmoji(_ menu: NSMenu) {
  for item in menu.items {
   let first = item.title.unicodeScalars.first!
   expect(first.properties.isEmoji, "every custom menu caption starts with emoji")
   if let submenu = item.submenu { checkEmoji(submenu) }
  }
 }
 checkEmoji(menu)
 let leaves = leafItems(menu)
 expect(leaves.count == actions.count, "all actions remain available")
 for (index,item) in leaves.enumerated() {
  _ = (item.target as! NSObject).perform(item.action!, with: item)
  let request = TestWorkspace.requests.last!
  expect(FlutterToolsRequest.action(from: request) == actions[index], "action transport")
  expect(FlutterToolsRequest.projectURL(from: request)?.path == project.path, "path transport")
 }
 for guardedItem in [development.items[4].submenu!.items[0], development.items[10].submenu!.items.last!] {
  let requestCount = TestWorkspace.requests.count
  let failureCount = TestWorkspace.failures
  setContext(ordinary, for: kind)
  _ = (guardedItem.target as! NSObject).perform(guardedItem.action!, with: guardedItem)
  expect(TestWorkspace.requests.count == requestCount, "changed non-Flutter context must not dispatch \(guardedItem.title)")
  expect(TestWorkspace.failures == failureCount + 1, "changed context reports failure")
  setContext(project, for: kind)
  try "name: fixture\ndependencies: {}\n".write(to: project.appendingPathComponent("pubspec.yaml"), atomically: true, encoding: .utf8)
  _ = (guardedItem.target as! NSObject).perform(guardedItem.action!, with: guardedItem)
  expect(TestWorkspace.requests.count == requestCount, "project losing Flutter declaration must not dispatch \(guardedItem.title)")
  expect(TestWorkspace.failures == failureCount + 2, "changed manifest reports failure")
  try "name: fixture\ndependencies:\n  flutter:\n    sdk: flutter\n".write(to: project.appendingPathComponent("pubspec.yaml"), atomically: true, encoding: .utf8)
 }
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
expect(FlutterToolsRequest.action(from:URL(string:"jobsfluttertools://import-dependencies?path=/project")!) == .importDependencies,"dependency import URL")
expect(FlutterToolsRequest.action(from:URL(string:"jobsfluttertools://maintenance?path=/legacy")!) == .maintenance,"legacy maintenance URL stays valid")
expect(FlutterToolsRequest.action(from:URL(string:"jobsfluttertools://repair-package-imports?path=/project")!) == .repairPackageImports,"package import repair URL")
for value in ["jobsfluttertools://unknown?path=/a","jobsfluttertools://package-macos?path=/a","jobsfluttertools://run?path=/a&path=/b","jobsfluttertools://run?path=relative","jobsfluttertools://run?path=/a%00b","jobsfluttertools://user@run?path=/a","jobsfluttertools://run:12?path=/a","jobsfluttertools://run/extra?path=/a","jobsfluttertools://run?path=/a#fragment"] {
 expect(FlutterToolsRequest.action(from:URL(string:value)!) == nil,"reject ambiguous request")
}
let tools=base.appendingPathComponent("stub-tools")
try FileManager.default.createDirectory(at:tools,withIntermediateDirectories:true)
try "#!/bin/zsh\n/usr/bin/printf '%s\\0' \"$@\" > \"$JOBS_TEST_ARGS\"\nexit 19\n".write(to:tools.appendingPathComponent("DispatchFlutterTools.zsh"),atomically:true,encoding:.utf8)
for action in [FlutterToolsAction.projectSetup, .gradleDownload, .importDependencies, .repairNamespace, .repairPackageImports, .cleanBuildArtifacts, .maintenance, .harmonySdkManage, .javaManage] + FlutterToolsAction.dependencyPreparation + FlutterToolsAction.dependencyArchives + FlutterToolsAction.packaging {
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
let harmonyValidator = FlutterProjectValidator()
expect(harmonyValidator.isHarmonyFlutterProject(at: project), "recognize adapted Harmony Flutter root")
func expectUnadaptedHarmonyAction() {
 for kind in [FIMenuKind.contextualMenuForItems, .contextualMenuForContainer] {
  setContext(project, for: kind)
  let harmony = leafItems(provider.menu(for: kind)!).first { $0.title == FlutterToolsAction.packageHarmony.title }
  expect(harmony != nil, "unadapted Flutter project keeps configured Harmony packaging visible")
  let oldCount = TestWorkspace.requests.count
  let oldFailures = TestWorkspace.failures
  _ = (harmony!.target as! NSObject).perform(harmony!.action!, with: harmony!)
  expect(TestWorkspace.requests.count == oldCount, "unadapted Harmony click does not dispatch to host")
  expect(TestWorkspace.failures == oldFailures + 1, "unadapted Harmony click shows a warning")
  let message = TestWorkspace.failureMessages.last ?? ""
  expect(message.contains("ohos/build-profile.json5") && message.contains("ohos/oh-package.json5") && message.contains("请先完成鸿蒙适配"), "warning explains the missing Harmony adaptation")
 }
}
for name in ["build-profile.json5", "oh-package.json5"] {
 let manifest = project.appendingPathComponent("ohos").appendingPathComponent(name)
 let saved = try Data(contentsOf: manifest)
 setContext(project, for: .contextualMenuForItems)
 let stale = leafItems(provider.menu(for: .contextualMenuForItems)!).first { $0.title == FlutterToolsAction.packageHarmony.title }!
 try FileManager.default.removeItem(at: manifest)
 expect(!harmonyValidator.isHarmonyFlutterProject(at: project), "missing Harmony manifest rejects package")
 expectUnadaptedHarmonyAction()
 setContext(project, for: .contextualMenuForItems)
 let oldCount = TestWorkspace.requests.count
 _ = (stale.target as! NSObject).perform(stale.action!, with: stale)
 expect(TestWorkspace.requests.count == oldCount, "stale Harmony action is rejected after manifest removal")
 do {
  let request = try FlutterToolsLauncher().prepare(projectURL: project, action: .packageHarmony, toolsURL: tools)
  try FileManager.default.removeItem(at: request.directoryURL)
  fatalError("host accepted missing Harmony manifest")
 } catch { expect(true, "host rechecks Harmony project") }
 try FileManager.default.createSymbolicLink(at: manifest, withDestinationURL: singleFile)
 expect(!harmonyValidator.isHarmonyFlutterProject(at: project), "symlink Harmony manifest is rejected")
 try FileManager.default.removeItem(at: manifest)
 try saved.write(to: manifest)
}
let ohosDirectory = project.appendingPathComponent("ohos")
let savedOhos = project.appendingPathComponent("ohos-backup")
try FileManager.default.moveItem(at: ohosDirectory, to: savedOhos)
expect(!harmonyValidator.isHarmonyFlutterProject(at: project), "missing ohos directory rejects package")
expectUnadaptedHarmonyAction()
try FileManager.default.createSymbolicLink(at: ohosDirectory, withDestinationURL: savedOhos)
expect(!harmonyValidator.isHarmonyFlutterProject(at: project), "linked ohos directory rejected")
try FileManager.default.removeItem(at: ohosDirectory)
try FileManager.default.moveItem(at: savedOhos, to: ohosDirectory)
let config = base.appendingPathComponent("features.conf")
expect(FlutterFeatureConfiguration.enabledFeatures(configurationURL: config).count == 45, "missing config keeps legacy actions")
setContext(project, for: .contextualMenuForItems)
let staleMenu = provider.menu(for: .contextualMenuForItems)!
let staleRun = leafItems(staleMenu).first!
let staleImport = leafItems(staleMenu).first { $0.title == FlutterToolsAction.importDependencies.title }!
try "package-android,repair-package-imports".write(to: config, atomically: true, encoding: .utf8)
let partial = provider.menu(for: .contextualMenuForItems)!.items[0].submenu!
expect(partial.items.map(\.title) == ["📦 Flutter打包", "🔧 Flutter项目修复"], "empty action groups are hidden")
expect(leafItems(partial).map(\.title) == ["🤖 Android", "🔤 修复 Dart 相对 import 为 package 引用"], "selected leaves only")
let previousRequestCount = TestWorkspace.requests.count
_ = (staleRun.target as! NSObject).perform(staleRun.action!, with: staleRun)
expect(TestWorkspace.requests.count == previousRequestCount, "stale menu cannot launch disabled action")
_ = (staleImport.target as! NSObject).perform(staleImport.action!, with: staleImport)
expect(TestWorkspace.requests.count == previousRequestCount, "stale dependency import cannot launch a disabled action")
for action in [FlutterToolsAction.projectSetup, .gradleDownload, .run, .importDependencies, .package, .packageIOS, .packageHarmony] {
 do {
  let request = try FlutterToolsLauncher().prepare(projectURL: project, action: action, toolsURL: tools)
  try FileManager.default.removeItem(at: request.directoryURL)
  fatalError("disabled host action accepted")
 } catch {
  expect(true, "host rejects disabled or aggregate platform action")
 }
}
let groupExpectations: [(String, [FlutterToolsAction])] = [
 ("📥 拉取Flutter项目工程相关依赖", FlutterToolsAction.dependencyFetch),
 ("🧩 提取Flutter项目工程依赖", FlutterToolsAction.dependencyExports),
 ("📤 导入Flutter项目工程依赖", FlutterToolsAction.dependencyImports),
 ("🔀 安装/切换Flutter运行环境", FlutterToolsAction.environments),
 ("🧱 Flutter 资源与构建依赖", FlutterToolsAction.resources),
 ("📦 Flutter打包", FlutterToolsAction.packaging),
 ("🏥 Flutter项目体检", FlutterToolsAction.doctors),
 ("🔧 Flutter项目修复", FlutterToolsAction.repairs),
 ("🧹 Flutter清理维护工具", FlutterToolsAction.cleaning)
]
for action in actions {
 try action.rawValue.write(to: config, atomically: true, encoding: .utf8)
 let oneMenu = provider.menu(for: .contextualMenuForItems)!
 let one = leafItems(oneMenu)
 expect(one.count == 1 && one[0].title == action.title, "each individual selection survives its parent group")
 let direct = oneMenu.items[0].submenu!.items
 let expectedParent = groupExpectations.first { $0.1.contains(action) }?.0
 expect(direct.count == 1 && direct[0].title == (expectedParent ?? action.title), "old single-action configuration enters its new parent without enabling siblings")
}
try "package-android,repair-package-imports".write(to: config, atomically: true, encoding: .utf8)
let enabledRequest = try FlutterToolsLauncher().prepare(projectURL: project, action: .packageAndroid, toolsURL: tools)
try FileManager.default.removeItem(at: enabledRequest.directoryURL)
expect(FlutterFeatureConfiguration.permits(.package, enabled: Set(FlutterToolsAction.packaging)), "legacy package only when every platform is enabled")
for invalid in ["", "unknown", "run,unknown", "run,run", "run,", "package", "run\u{0000}", String(repeating: "r", count: 8193)] {
 try invalid.write(to: config, atomically: true, encoding: .utf8)
 expect(FlutterFeatureConfiguration.enabledFeatures(configurationURL: config).isEmpty, "empty or invalid configuration disables all actions")
 expect(provider.menu(for: .contextualMenuForItems) == nil, "all disabled hides Flutter root")
}
try Data([0xff, 0xfe]).write(to: config)
expect(FlutterFeatureConfiguration.enabledFeatures(configurationURL: config).isEmpty, "invalid UTF-8 rejected")
try FileManager.default.removeItem(at: config)
let other = base.appendingPathComponent("other-features.conf")
try "run".write(to: other, atomically: true, encoding: .utf8)
try FileManager.default.createSymbolicLink(at: config, withDestinationURL: other)
expect(FlutterFeatureConfiguration.enabledFeatures(configurationURL: config).isEmpty, "symlink configuration rejected")
try FileManager.default.removeItem(at: config)
try FileManager.default.createDirectory(at: config, withIntermediateDirectories: false)
expect(FlutterFeatureConfiguration.enabledFeatures(configurationURL: config).isEmpty, "directory configuration rejected")
let diagnosticURL = FileManager.default.temporaryDirectory.appendingPathComponent("JobsFlutterToolsFinderMenu-\(getpid()).jsonl")
let diagnosticData = try Data(contentsOf: diagnosticURL)
let records = try String(decoding: diagnosticData, as: UTF8.self).split(separator: "\n").map {
 try JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any]
}
expect(records.first?["event"] as? String == "initialized", "diagnostic records extension initialization")
expect(records.contains { $0["reason"] as? String == "returned" && $0["returnedLeafCount"] as? Int == 45 && $0["validator"] as? Bool == true }, "diagnostic confirms valid project and returned leaves")
expect(records.contains { $0["reason"] as? String == "non-flutter" && $0["validator"] as? Bool == false }, "diagnostic identifies validator refusal")
expect(records.contains { $0["reason"] as? String == "no-candidate" }, "diagnostic identifies missing selection")
expect(records.contains { $0["reason"] as? String == "no-enabled-actions" && $0["enabledCount"] as? Int == 0 }, "diagnostic identifies disabled features")
expect(records.allSatisfy { Set($0.keys).isSubset(of: ["event", "observedRoot", "time", "pid", "kind", "candidate", "validator", "enabledCount", "availableCount", "returnedLeafCount", "reason"]) }, "diagnostic contains only local menu metadata")
let diagnosticAttributes = try FileManager.default.attributesOfItem(atPath: diagnosticURL.path)
expect((diagnosticAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o600, "diagnostic is private")
try Data(repeating: 65, count: 131_072).write(to: diagnosticURL)
_ = provider.menu(for: .contextualMenuForItems)
let rotatedDiagnostic = try Data(contentsOf: diagnosticURL)
expect(rotatedDiagnostic.count < 4096, "diagnostic rotates before its bound")
try FileManager.default.removeItem(at: diagnosticURL)
try FileManager.default.createSymbolicLink(at: diagnosticURL, withDestinationURL: other)
_ = provider.menu(for: .contextualMenuForItems)
let symlinkTarget = try String(contentsOf: other, encoding: .utf8)
expect(symlinkTarget == "run", "diagnostic refuses symlink destination")
try FileManager.default.removeItem(at: diagnosticURL)
print("PASS: \(assertions) menu and transport assertions")
'''
with tempfile.TemporaryDirectory(prefix='jobs-flutter-menu-') as temp:
 p=pathlib.Path(temp);(p/'main.swift').write_text(stub+'\n'+'\n'.join(sources)+'\n'+menu+'\n'+checks)
 subprocess.run(['/usr/bin/xcrun','swiftc',str(p/'main.swift'),'-o',str(p/'check')],check=True)
 subprocess.run([str(p/'check'),str(p)],check=True)

# Exercise only the isolated config writer, never the real install/registration entry.
with tempfile.TemporaryDirectory(prefix='jobs-flutter-feature-install-') as temp:
 p=pathlib.Path(temp)
 installer=(root/'Scripts/ManageExtension.zsh').read_text()
 (p/'library.zsh').write_text(installer.rsplit('manager_main "$@"',1)[0])
 config=p/'Library/Application Support/JobsFinderExtensions/flutter-tools-features.conf'
 config.parent.mkdir(parents=True)
 config.write_text('run')
 result=subprocess.run(['/bin/zsh','-f','-c','source "$1"; LOG_FILE="$2"; manager_persist_flutter_selection','fixture',str(p/'library.zsh'),str(p/'install.log')],env={'HOME':temp,'PATH':'/usr/bin:/bin'},capture_output=True,text=True)
 assert result.returncode == 0,result.stdout+result.stderr
 selected=config.read_text().split(',')
 assert len(selected) == len(set(selected)) == 45,selected
 assert config.stat().st_mode & 0o777 == 0o600
 assert len(list(config.parent.iterdir())) == 1
 print('PASS: isolated independent installer enables all 45 actions atomically')
