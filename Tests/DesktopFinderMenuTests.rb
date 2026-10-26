# frozen_string_literal: true
# 编译真实 FinderSync 源码，以内存控制器和菜单替身验证桌面边界；不加载系统扩展或打开应用。

require 'minitest/autorun'
require 'open3'
require 'tmpdir'

class DesktopFinderMenuTests < Minitest::Test
  ROOT = File.expand_path('..', __dir__)
  CONTAINER_EXTENSIONS = %w[
    JobsXcodeOpener/JobsXcodeFinderSync/FinderSync.swift
    JobsVSCodeOpener/JobsVSCodeFinderSync/FinderSync.swift
    JobsAndroidStudioOpener/JobsAndroidStudioFinderSync/FinderSync.swift
    JobsGitPuller/JobsGitPullFinderSync/FinderSync.swift
    JobsFlutterVersionMgr/JobsFlutterVersionFinderSync/FinderSync.swift
    JobsFlutterDependencyExtractor/JobsFlutterDependencyFinderSync/FinderSync.swift
    JobsFlutterRunner/JobsFlutterRunFinderSync/FinderSync.swift
    JobsFlutterDoctor/JobsFlutterDoctorFinderSync/FinderSync.swift
    JobsFlutterCodegen/JobsFlutterCodegenFinderSync/FinderSync.swift
  ].freeze
  ITEM_ONLY_EXTENSIONS = %w[
    JobsGitRemoteOpener/JobsGitRemoteFinderSync/FinderSync.swift
    JobsGitRemoteCopier/JobsGitRemoteCopyFinderSync/FinderSync.swift
    JobsPathCopier/JobsPathCopyFinderSync/FinderSync.swift
  ].freeze
  SIMULATOR = 'JobsIOSSimulatorCreator/JobsIOSSimulatorFinderSync/FinderSync.swift'
  ANDROID_SIMULATOR = 'JobsAndroidSimulatorCreator/JobsAndroidSimulatorFinderSync/FinderSync.swift'
  GIT_PROXY = 'JobsGitProxyConfigurator/JobsGitProxyFinderSync/FinderSync.swift'

  def test_independent_extensions_keep_their_expected_real_desktop_policy
    helpers = CONTAINER_EXTENSIONS.map do |path|
      source = File.read(File.join(ROOT, path))
      helper = source[/private enum FinderDesktopMenuPolicy \{.*\z/m]
      refute_nil helper, path
      assert_match(/!FinderDesktopMenuPolicy\.isDesktopContainer\(targetURL\)/, source, path)
      assert_operator source.scan(/candidateURL\(for: menuKind\)/).length, :>=, 2, path
      helper
    end
    assert_equal 1, helpers[0...-2].uniq.length, '既有工程的桌面策略应保持一致。'
    assert_equal 1, helpers.last(2).uniq.length, '体检与生成各自携带一致的目录服务桌面策略。'
    helpers.last(2).each { |helper| assert_includes helper, 'getpwuid_r' }
  end

  def test_existing_item_only_extensions_have_no_container_entry
    ITEM_ONLY_EXTENSIONS.each do |path|
      source = File.read(File.join(ROOT, path))
      assert_match(/guard menuKind == \.contextualMenuForItems/, source, path)
      refute_includes source, '.contextualMenuForContainer', path
    end
  end

  def test_build_artifact_menu_identifies_the_selected_project_before_display
    Dir.mktmpdir('jobs-build-menu-tests-') do |directory|
      source = isolated_source('JobsTerminalOpener/JobsTerminalFinderSync/FinderSync.swift', 950)
      source = source.sub('FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory',
                          'URL(fileURLWithPath: CommandLine.arguments[1])')
      validator = File.read(File.join(ROOT, 'JobsTerminalOpener/JobsTerminalShared/DependencyProjectValidator.swift'))
      features = File.read(File.join(ROOT, 'JobsTerminalOpener/JobsTerminalShared/FinderMenuFeatureConfiguration.swift')).split('struct FinderMenuFeatureConfiguration').first
      configuration = <<~'SWIFT'
        struct FinderMenuFeatureConfiguration {
            static var enabled: Set<FinderMenuFeature> = [.cleanBuildArtifacts]
            static func enabledFeatures(fallbackBundle: Bundle) -> Set<FinderMenuFeature> { enabled }
        }
      SWIFT
      checks = <<~'SWIFT'
        let manager = FileManager.default
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            if !condition() { fatalError(message) }
        }
        func file(_ relative: String, _ text: String = "") throws {
            let url = root.appendingPathComponent(relative)
            try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
        try file("flutter/pubspec.yaml", "dependencies:\n  flutter:\n    sdk: flutter\n")
        try file("flutter/lib/main.dart")
        let flutterManifests = [
            "flutter-flow": "dependencies: { flutter: { sdk: flutter } }\n",
            "flutter-inline": "dependencies:\n  flutter: { sdk: 'flutter' }\n",
            "flutter-quoted": "\"dependencies\":\n  'flutter':\n    \"sdk\": \"flutter\" # SDK declaration\n"
        ]
        for (prefix, manifest) in flutterManifests {
            try file("\(prefix)/pubspec.yaml", manifest)
            try file("\(prefix)/lib/main.dart")
            try file("\(prefix)-no-lib/pubspec.yaml", manifest)
        }
        let flutterPaths = ["flutter"] + flutterManifests.keys.sorted().flatMap { [$0, "\($0)-no-lib"] }
        try file("android/settings.gradle.kts")
        try file("android/app/build.gradle.kts", "plugins { alias(libs.plugins.android.application) }")
        try file("android/app/src/main/AndroidManifest.xml")
        try file("ios/Demo.xcodeproj/project.pbxproj", "SDKROOT = iphoneos;")
        for prefix in ["harmony", "flutter/ohos"] {
            try file("\(prefix)/hvigorfile.ts")
            try file("\(prefix)/build-profile.json5")
            try file("\(prefix)/oh-package.json5")
            try file("\(prefix)/AppScope/app.json5")
        }
        try file("unknown/build/keep")
        try file("macos/Demo.xcodeproj/project.pbxproj", "SDKROOT = macosx;")
        let controller = FIFinderSyncController.default()
        let finder = FinderSync950()
        // Flutter 识别优先，混合标记也保持平台限定清理。
        for prefix in flutterPaths {
            try file("\(prefix)/Demo.xcodeproj/project.pbxproj", "SDKROOT = iphoneos;")
            try file("\(prefix)/build.gradle", "plugins { id 'com.android.application' }")
        }
        let supportedPaths = ["android", "harmony", "flutter/ohos"] + flutterPaths
        for path in supportedPaths {
            let selected = root.appendingPathComponent(path)
            controller.selected = [selected]
            let menu = finder.menu(for: .contextualMenuForItems)
            expect(menu?.items.map(\.title) == ["🧯 清理 Android / OpenHarmony 构建产物"], "wrong title for \(path)")
            let item = menu!.items[0]
            _ = (item.target as! NSObject).perform(item.action!, with: item)
            let components = URLComponents(url: TestActions.lastURL!, resolvingAgainstBaseURL: false)!
            expect(components.queryItems?.first(where: { $0.name == "path" })?.value == selected.path, "wrong cleanup target")
            expect(components.queryItems?.first(where: { $0.name == "action" })?.value == "clean-build-artifacts", "stable action identifier")
        }
        for path in ["unknown", "macos", "ios", "flutter/lib", "ios/Demo.xcodeproj", "flutter/pubspec.yaml"] {
            controller.selected = [root.appendingPathComponent(path)]
            expect(finder.menu(for: .contextualMenuForItems) == nil, "unsupported folder/file must hide cleanup")
        }
        controller.selected = [root.appendingPathComponent("flutter"), root.appendingPathComponent("android")]
        expect(finder.menu(for: .contextualMenuForItems) == nil, "multiple selection must hide cleanup")
        controller.selected = []
        controller.targeted = nil
        expect(finder.menu(for: .contextualMenuForContainer) == nil, "background must hide cleanup")
        FinderMenuFeatureConfiguration.enabled = [.open, .cleanBuildArtifacts]
        for path in flutterPaths {
            controller.selected = [root.appendingPathComponent(path)]
            expect(finder.menu(for: .contextualMenuForItems)?.items.map(\.title) == ["💻 用终端打开", "🧯 清理 Android / OpenHarmony 构建产物"], "\(path) offers terminal and scoped cleanup")
        }
        FinderMenuFeatureConfiguration.enabled = [.open, .cleanBuildArtifacts, .codeGraphBootstrap]
        for path in supportedPaths {
            let target = root.appendingPathComponent(path)
            controller.targeted = target
            controller.selected = [root.appendingPathComponent("ios")]
            let menu = finder.menu(for: .contextualMenuForContainer)
            expect(menu?.items.map(\.title) == ["🧯 清理 Android / OpenHarmony 构建产物"], "container offers only scoped cleanup")
            let item = menu!.items[0]
            _ = (item.target as! NSObject).perform(item.action!, with: item)
            let components = URLComponents(url: TestActions.lastURL!, resolvingAgainstBaseURL: false)!
            expect(components.queryItems?.first(where: { $0.name == "path" })?.value == target.path, "container click uses targeted folder instead of stale selection")
            controller.targeted = root.appendingPathComponent("unknown")
            let before = TestActions.count
            _ = (item.target as! NSObject).perform(item.action!, with: item)
            expect(TestActions.count == before, "changed container target is revalidated before dispatch")
        }
        for path in ["unknown", "macos", "ios", "flutter/lib", "ios/Demo.xcodeproj", "flutter/pubspec.yaml"] {
            controller.targeted = root.appendingPathComponent(path)
            expect(finder.menu(for: .contextualMenuForContainer) == nil, "unsupported container hides cleanup")
        }
        FinderMenuFeatureConfiguration.enabled = []
        expect(finder.menu(for: .contextualMenuForItems) == nil, "disabled feature must stay hidden")
        FinderMenuFeatureConfiguration.enabled = [.podInstall, .gitEmptyCommitPush, .cleanBuildArtifacts]
        controller.selected = [root.appendingPathComponent("ios")]
        try file("ios/Podfile")
        expect(finder.menu(for: .contextualMenuForItems) == nil, "migrated iOS and Git actions must not return to the outer menu")
        print("PASS: build artifact menu titles, targets and visibility")
      SWIFT
      source_path = File.join(directory, 'main.swift')
      binary = File.join(directory, 'menu-test')
      File.write(source_path, [swift_stubs, validator, features, configuration, source, checks].join("\n"))
      output, status = Open3.capture2e('/usr/bin/xcrun', 'swiftc', source_path, '-o', binary)
      assert status.success?, output
      output, status = Open3.capture2e(binary, directory)
      assert status.success?, output
      assert_includes output, 'PASS: build artifact menu'
    end
  end

  def test_actual_menus_click_callbacks_and_injected_desktop_paths
    Dir.mktmpdir('jobs-desktop-menu-tests-') do |directory|
      source_path = File.join(directory, 'main.swift')
      binary_path = File.join(directory, 'desktop-menu-tests')
      sources = CONTAINER_EXTENSIONS.each_with_index.map { |path, index| isolated_source(path, index) }
      sources << isolated_source(SIMULATOR, CONTAINER_EXTENSIONS.length)
      sources << isolated_source(ANDROID_SIMULATOR, CONTAINER_EXTENSIONS.length + 1)
      %w[IOSSimulatorMenuContext IOSSimulatorRequest AndroidSimulatorMenuContext AndroidSimulatorRequest].each do |type|
        platform = type.start_with?('Android') ? 'Android' : 'IOS'
        path = File.join(ROOT, "Jobs#{platform}SimulatorCreator/Jobs#{platform}SimulatorShared/#{type}/#{type}.swift")
        source = File.read(path)
        if type.end_with?('MenuContext')
          # 模拟两种 Foundation Home API 均重定向到沙盒；真实 passwd 查询保持原样。
          source = source.gsub('FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)',
                               'TestSandboxEnvironment.desktopURLs')
          source = source.gsub('NSHomeDirectoryForUser(NSUserName())', 'TestSandboxEnvironment.redirectedHome')
        end
        sources << source
      end
      File.write(source_path, swift_stubs + "\n" + sources.join("\n") + "\n" + swift_checks)
      output, status = Open3.capture2e('/usr/bin/xcrun', 'swiftc', source_path, '-o', binary_path)
      assert status.success?, output
      fake_home = File.join(directory, 'Library/Containers/com.jobs.fixture/Data')
      output, status = Open3.capture2e({ 'HOME' => fake_home, 'JOBS_TEST_SANDBOX_HOME' => fake_home }, binary_path, directory)
      assert status.success?, output
      assert_match(/PASS: \d+ desktop menu assertions/, output)
      puts output.lines.grep(/^PASS:/)
    end
  end

def test_harmony_simulator_menu_only_uses_the_real_desktop_background
  Dir.mktmpdir('jobs-harmony-desktop-tests-') do |directory|
    source_path = File.join(directory, 'main.swift')
    binary_path = File.join(directory, 'harmony-menu-tests')
    sources = [isolated_source('JobsHarmonySimulatorCreator/JobsHarmonySimulatorFinderSync/FinderSync.swift', 901)]
    %w[HarmonySimulatorMenuContext HarmonySimulatorRequest].each do |type|
      source = File.read(File.join(ROOT, "JobsHarmonySimulatorCreator/JobsHarmonySimulatorShared/#{type}/#{type}.swift"))
      source = source.gsub('FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)', 'TestSandboxEnvironment.desktopURLs')
      sources << source
    end
    checks = <<~'SWIFT'
      var assertionCount = 0
      func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
          assertionCount += 1
          guard condition() else { fatalError(message) }
      }
        func click(_ menu: NSMenu?) {
            guard let item = menu?.items.first, let target = item.target as? NSObject,
                  let action = item.action else { expect(false, "missing menu action"); return }
            _ = target.perform(action, with: item)
        }
      let controller = FIFinderSyncController.default()
      let desktop = URL(fileURLWithPath: String(cString: getpwuid(getuid())!.pointee.pw_dir), isDirectory: true).appendingPathComponent("Desktop", isDirectory: true)
      let folder = URL(fileURLWithPath: "/fixture/ordinary", isDirectory: true)
      let extensionMenu = FinderSync901()
      expect(controller.directoryURLs.contains(URL(fileURLWithPath: "/", isDirectory: true)), "Harmony must observe root for real Finder desktop dispatch")
      controller.targeted = desktop
      controller.selected = nil
      let menu = extensionMenu.menu(for: .contextualMenuForContainer)
      expect(menu?.items.map(\.title) == ["🌈 新建 Harmony 模拟器"], "Only desktop background may show Harmony action")
      TestActions.count = 0
        click(menu)
      expect(TestActions.count == 1, "Desktop click dispatches once")
        controller.selected = [folder]
        expect(extensionMenu.menu(for: .contextualMenuForContainer)?.items.count == 1, "Container callback stays eligible despite stale selection metadata")
      controller.targeted = folder
      expect(extensionMenu.menu(for: .contextualMenuForContainer) == nil, "Ordinary folder must hide Harmony action")
      TestActions.count = 0
        click(menu)
      expect(TestActions.count == 0, "Stale desktop menu must not dispatch from a folder")
      controller.targeted = desktop
      for selected in [[], [desktop], [folder], [desktop, folder]] {
          controller.selected = selected
          expect(extensionMenu.menu(for: .contextualMenuForItems) == nil, "All item selections must hide Harmony action")
      }
      expect(extensionMenu.menu(for: .toolbarItemMenu) == nil, "Toolbar must not add Harmony action")
      controller.targeted = nil
      controller.selected = nil
      expect(extensionMenu.menu(for: .contextualMenuForContainer)?.items.count == 1, "Known desktop fallback remains available")
      expect(HarmonySimulatorRequest.isCreateRequest(HarmonySimulatorRequest.canonicalURL), "Fixed request must pass")
      expect(!HarmonySimulatorRequest.isCreateRequest(URL(string: "jobsharmonysimulatorcreator://simulator/create?command=bad")!), "Extra URL parameters must be rejected")
      print("PASS: \(assertionCount) Harmony desktop menu assertions")
    SWIFT
    File.write(source_path, swift_stubs + "\n" + sources.join("\n") + "\n" + checks)
    output, status = Open3.capture2e('/usr/bin/xcrun', 'swiftc', source_path, '-o', binary_path)
    assert status.success?, output
    output, status = Open3.capture2e(binary_path)
    assert status.success?, output
    assert_includes output, 'Harmony desktop menu assertions'
    puts output.lines.grep(/^PASS:/)
  end
end

def test_android_repair_menu_only_uses_the_real_desktop_background
  Dir.mktmpdir('jobs-android-repair-desktop-tests-') do |directory|
    source_path = File.join(directory, 'main.swift')
    binary_path = File.join(directory, 'android-repair-menu-tests')
    sources = [isolated_source('JobsAndroidSimulatorRepairer/JobsAndroidSimulatorRepairFinderSync/FinderSync.swift', 901)]
    %w[AndroidSimulatorRepairMenuContext AndroidSimulatorRepairRequest].each do |type|
      source = File.read(File.join(ROOT, "JobsAndroidSimulatorRepairer/JobsAndroidSimulatorRepairShared/#{type}/#{type}.swift"))
      source = source.gsub('FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)', 'TestSandboxEnvironment.desktopURLs')
      sources << source
    end
    checks = <<~'SWIFT'
      var assertionCount = 0
      func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
          assertionCount += 1
          guard condition() else { fatalError(message) }
      }
        func click(_ menu: NSMenu?) {
            guard let item = menu?.items.first, let target = item.target as? NSObject,
                  let action = item.action else { expect(false, "missing menu action"); return }
            _ = target.perform(action, with: item)
        }
      let controller = FIFinderSyncController.default()
      let desktop = URL(fileURLWithPath: String(cString: getpwuid(getuid())!.pointee.pw_dir), isDirectory: true).appendingPathComponent("Desktop", isDirectory: true)
      let folder = URL(fileURLWithPath: "/fixture/ordinary", isDirectory: true)
      let extensionMenu = FinderSync901()
      expect(controller.directoryURLs.contains(URL(fileURLWithPath: "/", isDirectory: true)), "Android repair must observe root for real Finder desktop dispatch")
      controller.targeted = desktop
      controller.selected = nil
      let menu = extensionMenu.menu(for: .contextualMenuForContainer)
      expect(menu?.items.map(\.title) == ["🩺 Android 模拟器检测与修复"], "Only desktop background may show Android repair action")
      TestActions.count = 0
        click(menu)
      expect(TestActions.count == 1, "Desktop click dispatches once")
        controller.selected = [folder]
        expect(extensionMenu.menu(for: .contextualMenuForContainer)?.items.count == 1, "Container callback stays eligible despite stale selection metadata")
      controller.targeted = folder
      expect(extensionMenu.menu(for: .contextualMenuForContainer) == nil, "Ordinary folder must hide Android repair action")
      TestActions.count = 0
        click(menu)
      expect(TestActions.count == 0, "Stale desktop menu must not dispatch from a folder")
      controller.targeted = desktop
      for selected in [[], [desktop], [folder], [desktop, folder]] {
          controller.selected = selected
          expect(extensionMenu.menu(for: .contextualMenuForItems) == nil, "All item selections must hide Android repair action")
      }
      expect(extensionMenu.menu(for: .toolbarItemMenu) == nil, "Toolbar must not add Android repair action")
      controller.targeted = nil
      controller.selected = nil
      expect(extensionMenu.menu(for: .contextualMenuForContainer)?.items.count == 1, "Known desktop fallback remains available")
      expect(AndroidSimulatorRepairRequest.isRepairRequest(AndroidSimulatorRepairRequest.canonicalURL), "Fixed request must pass")
      expect(!AndroidSimulatorRepairRequest.isRepairRequest(URL(string: "jobsandroidsimulatorrepairer://simulator/repair?command=bad")!), "Extra URL parameters must be rejected")
      print("PASS: \(assertionCount) Android repair desktop menu assertions")
    SWIFT
    File.write(source_path, swift_stubs + "\n" + sources.join("\n") + "\n" + checks)
    output, status = Open3.capture2e('/usr/bin/xcrun', 'swiftc', source_path, '-o', binary_path)
    assert status.success?, output
    output, status = Open3.capture2e(binary_path)
    assert status.success?, output
    assert_includes output, 'Android repair desktop menu assertions'
    puts output.lines.grep(/^PASS:/)
  end
end

def test_harmony_repair_menu_only_uses_the_real_desktop_background
  Dir.mktmpdir('jobs-harmony-repair-desktop-tests-') do |directory|
    source_path = File.join(directory, 'main.swift')
    binary_path = File.join(directory, 'harmony-repair-menu-tests')
    sources = [isolated_source('JobsHarmonySimulatorRepairer/JobsHarmonySimulatorRepairFinderSync/FinderSync.swift', 901)]
    sources << isolated_source('JobsHarmonySimulatorRepairer/JobsHarmonySimulatorRepairShared/JobsHarmonyRepairFactories.swift', 902)
    %w[HarmonySimulatorRepairMenuContext HarmonySimulatorRepairRequest].each do |type|
      source = File.read(File.join(ROOT, "JobsHarmonySimulatorRepairer/JobsHarmonySimulatorRepairShared/#{type}/#{type}.swift"))
      source = source.gsub('FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)', 'TestSandboxEnvironment.desktopURLs')
      sources << source
    end
    checks = <<~'SWIFT'
      var assertionCount = 0
      func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
          assertionCount += 1
          guard condition() else { fatalError(message) }
      }
        func click(_ menu: NSMenu?) {
            guard let item = menu?.items.first, let target = item.target as? NSObject,
                  let action = item.action else { expect(false, "missing menu action"); return }
            _ = target.perform(action, with: item)
        }
      let controller = FIFinderSyncController.default()
      let desktop = URL(fileURLWithPath: String(cString: getpwuid(getuid())!.pointee.pw_dir), isDirectory: true).appendingPathComponent("Desktop", isDirectory: true)
      let folder = URL(fileURLWithPath: "/fixture/ordinary", isDirectory: true)
      let extensionMenu = FinderSync901()
      expect(controller.directoryURLs.contains(URL(fileURLWithPath: "/", isDirectory: true)), "Harmony repair must observe root for real Finder desktop dispatch")
      controller.targeted = desktop
      controller.selected = nil
      let menu = extensionMenu.menu(for: .contextualMenuForContainer)
      expect(menu?.items.map(\.title) == ["🧰 Harmony 模拟器检测与修复"], "Only desktop background may show Harmony repair action")
      TestActions.count = 0
        click(menu)
      expect(TestActions.count == 1, "Desktop click dispatches once")
        controller.selected = [folder]
        expect(extensionMenu.menu(for: .contextualMenuForContainer)?.items.count == 1, "Container callback stays eligible despite stale selection metadata")
      controller.targeted = folder
      expect(extensionMenu.menu(for: .contextualMenuForContainer) == nil, "Ordinary folder must hide Harmony repair action")
      TestActions.count = 0
        click(menu)
      expect(TestActions.count == 0, "Stale desktop menu must not dispatch from a folder")
      controller.targeted = desktop
      for selected in [[], [desktop], [folder], [desktop, folder]] {
          controller.selected = selected
          expect(extensionMenu.menu(for: .contextualMenuForItems) == nil, "All item selections must hide Harmony repair action")
      }
      expect(extensionMenu.menu(for: .toolbarItemMenu) == nil, "Toolbar must not add Harmony repair action")
      controller.targeted = nil
      controller.selected = nil
      expect(extensionMenu.menu(for: .contextualMenuForContainer)?.items.count == 1, "Known desktop fallback remains available")
      expect(HarmonySimulatorRepairRequest.isRepairRequest(HarmonySimulatorRepairRequest.canonicalURL), "Fixed request must pass")
      expect(!HarmonySimulatorRepairRequest.isRepairRequest(URL(string: "jobsharmonysimulatorrepairer://simulator/repair?command=bad")!), "Extra URL parameters must be rejected")
      print("PASS: \(assertionCount) Harmony repair desktop menu assertions")
    SWIFT
application_stubs = <<~'SWIFT'
  protocol NSApplicationDelegate: AnyObject {}
  final class NSApplication {
      var delegate: NSApplicationDelegate?
      func activate(ignoringOtherApps: Bool) {}
  }
SWIFT
File.write(source_path, swift_stubs + "\n" + application_stubs + sources.join("\n") + "\n" + checks)
    output, status = Open3.capture2e('/usr/bin/xcrun', 'swiftc', source_path, '-o', binary_path)
    assert status.success?, output
    output, status = Open3.capture2e(binary_path)
    assert status.success?, output
    assert_includes output, 'Harmony repair desktop menu assertions'
    puts output.lines.grep(/^PASS:/)
  end
end

  def test_git_proxy_menu_uses_the_real_desktop_context_and_a_fixed_action
    Dir.mktmpdir('jobs-git-proxy-desktop-tests-') do |directory|
      source_path = File.join(directory, 'main.swift')
      binary_path = File.join(directory, 'git-proxy-menu-tests')
      sources = [isolated_source(GIT_PROXY, 900)]
      %w[GitProxyMenuContext GitProxyRequest].each do |type|
        path = File.join(ROOT, "JobsGitProxyConfigurator/JobsGitProxyShared/#{type}/#{type}.swift")
        source = File.read(path)
        if type == 'GitProxyMenuContext'
          source = source.gsub('FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)',
                               'TestSandboxEnvironment.desktopURLs')
        end
        sources << source
      end
      checks = <<~'SWIFT'
        var assertionCount = 0
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            assertionCount += 1
            if !condition() { fputs("FAILED: \(message)\n", stderr); exit(1) }
        }
        func click(_ menu: NSMenu?) {
            guard let item = menu?.items.first, let target = item.target as? NSObject,
                  let action = item.action else { expect(false, "missing menu action"); return }
            _ = target.perform(action, with: item)
        }
        let manager = FileManager.default
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        guard let account = getpwuid(getuid()), let home = account.pointee.pw_dir else { fatalError("passwd home missing") }
        let desktop = URL(fileURLWithPath: String(cString: home), isDirectory: true).appendingPathComponent("Desktop", isDirectory: true)
        expect(GitProxyMenuContext.desktopURL?.standardizedFileURL == desktop.standardizedFileURL, "real passwd desktop precedes sandbox alias")
        expect(GitProxyMenuContext.desktopURLs.contains(TestSandboxEnvironment.desktopURLs[0]), "Foundation sandbox alias remains available")
        let injected = root.appendingPathComponent("云盘/真实桌面", isDirectory: true)
        let ordinary = root.appendingPathComponent("普通目录", isDirectory: true)
        let child = injected.appendingPathComponent("子目录", isDirectory: true)
        let sameName = root.appendingPathComponent("其它/Desktop", isDirectory: true)
        let prefix = root.appendingPathComponent("云盘/真实桌面-copy", isDirectory: true)
        for url in [injected, ordinary, child, sameName, prefix] { try manager.createDirectory(at: url, withIntermediateDirectories: true) }
        let alias = root.appendingPathComponent("桌面别名", isDirectory: true)
        try manager.createSymbolicLink(at: alias, withDestinationURL: injected)
        expect(GitProxyMenuContext.candidateURL(isContainer: true, targetedURL: injected, selectedURLs: nil, desktopURL: injected)?.path == injected.path, "explicit desktop accepted")
        expect(GitProxyMenuContext.candidateURL(isContainer: true, targetedURL: alias, selectedURLs: nil, desktopURL: injected)?.path == injected.path, "desktop symlink accepted")
        expect(GitProxyMenuContext.candidateURL(isContainer: true, targetedURL: nil, selectedURLs: nil, desktopURL: injected)?.path == injected.path, "nil target falls back to known desktop")
        for invalid in [ordinary, child, sameName, prefix, URL(string: "https://example.test/Desktop")!] {
            expect(GitProxyMenuContext.candidateURL(isContainer: true, targetedURL: invalid, selectedURLs: nil, desktopURL: injected) == nil, "ordinary and non-file containers rejected")
        }
        expect(GitProxyMenuContext.candidateURL(isContainer: false, targetedURL: injected, selectedURLs: [ordinary], desktopURL: injected) == nil, "item menu rejected")
        expect(GitProxyMenuContext.candidateURL(isContainer: true, targetedURL: injected, selectedURLs: [ordinary], desktopURL: injected) == nil, "explicit nonempty selection rejected")
        let unavailable = root.appendingPathComponent("unavailable/Desktop", isDirectory: true)
        expect(!manager.fileExists(atPath: unavailable.path), "desktop metadata fixture is unavailable")
        expect(GitProxyMenuContext.candidateURL(isContainer: true, targetedURL: unavailable, selectedURLs: nil, desktopURL: unavailable)?.path == unavailable.path, "known desktop does not require filesystem access")
        let controller = FIFinderSyncController.default()
        let extensionInstance = FinderSync900()
        expect(controller.directoryURLs.contains(URL(fileURLWithPath: "/", isDirectory: true)), "root monitoring preserves real desktop dispatch")
        controller.selected = nil
        controller.targeted = desktop
        let desktopMenu = extensionInstance.menu(for: .contextualMenuForContainer)
        expect(desktopMenu?.items.map(\.title) == ["📡 配置 Git 动态代理"], "desktop has one Git proxy action")
        TestActions.count = 0
        TestActions.lastURL = nil
        click(desktopMenu)
        expect(TestActions.count == 1, "desktop click dispatches once")
        expect(TestActions.lastURL?.absoluteString == "jobsgitproxyconfigurator://git/configure", "desktop click uses only the fixed action URL")
        controller.targeted = ordinary
        expect(extensionInstance.menu(for: .contextualMenuForContainer) == nil, "ordinary container has no global configuration entry")
        TestActions.count = 0
        click(desktopMenu)
        expect(TestActions.count == 0, "stale menu cannot dispatch from an ordinary directory")
        controller.targeted = desktop
        controller.selected = [ordinary]
        expect(extensionInstance.menu(for: .contextualMenuForItems) == nil, "selected project has no global configuration entry")
        expect(extensionInstance.menu(for: .toolbarItemMenu) == nil, "toolbar remains unchanged")
        controller.targeted = nil
        controller.selected = nil
        expect(extensionInstance.menu(for: .contextualMenuForContainer)?.items.count == 1, "Finder nil target uses the real desktop fallback")
        print("PASS: \(assertionCount) Git proxy desktop menu assertions")
      SWIFT
      File.write(source_path, swift_stubs + "\n" + sources.join("\n") + "\n" + checks)
      output, status = Open3.capture2e('/usr/bin/xcrun', 'swiftc', source_path, '-o', binary_path)
      assert status.success?, output
      fake_home = File.join(directory, 'Library/Containers/com.jobs.fixture/Data')
      output, status = Open3.capture2e({ 'HOME' => fake_home, 'JOBS_TEST_SANDBOX_HOME' => fake_home }, binary_path, directory)
      assert status.success?, output
      assert_match(/PASS: \d+ Git proxy desktop menu assertions/, output)
      puts output.lines.grep(/^PASS:/)
    end
  end

  private

  def isolated_source(path, index)
    source = File.read(File.join(ROOT, path))
    source = source.gsub(/^import (?:AppKit|FinderSync)\s*$/, '')
    source = source.gsub(/\bFinderSync\b/, "FinderSync#{index}")
    source.gsub(/\bFinderDesktopMenuPolicy\b/, "FinderDesktopMenuPolicy#{index}")
  end

  def swift_stubs
    <<~'SWIFT'
      import Foundation
      import Darwin

      enum TestSandboxEnvironment {
          static var redirectedHome: String? { return ProcessInfo.processInfo.environment["JOBS_TEST_SANDBOX_HOME"] }
          static var desktopURLs: [URL] {
              guard let home = redirectedHome else { return [] }
              return [URL(fileURLWithPath: home, isDirectory: true).appendingPathComponent("Desktop", isDirectory: true)]
          }
      }

      enum FIMenuKind: Int { case contextualMenuForItems, contextualMenuForContainer, toolbarItemMenu }
      class FIFinderSync: NSObject {
          func menu(for menuKind: FIMenuKind) -> NSMenu? { return nil }
      }
      final class FIFinderSyncController {
          static let shared = FIFinderSyncController()
          var directoryURLs: Set<URL> = []
          var selected: [URL]?
          var targeted: URL?
          static func `default`() -> FIFinderSyncController { return shared }
          func selectedItemURLs() -> [URL]? { return selected }
          func targetedURL() -> URL? { return targeted }
      }
      final class NSMenu: NSObject {
          var items: [NSMenuItem] = []
          init(title: String) { super.init() }
          func addItem(_ item: NSMenuItem) { items.append(item) }
      }
      final class NSMenuItem: NSObject {
          let title: String
          var isEnabled = true
          let action: Selector?
          var target: AnyObject?
          var representedObject: Any?
          init(title: String, action: Selector?, keyEquivalent: String) {
              self.title = title
              self.action = action
              super.init()
          }
      }
      final class NSAlert {
          enum Style { case warning }
          var alertStyle = Style.warning
          var messageText = ""
          var informativeText = ""
          func addButton(withTitle: String) {}
          func runModal() {}
      }
      enum TestActions { static var count = 0; static var lastURL: URL? }
      enum TestProjectRules { static var qualifies = true }
      final class NSWorkspace {
          final class OpenConfiguration { var activates = false }
          static let shared = NSWorkspace()
          func open(_ url: URL) -> Bool { TestActions.count += 1; TestActions.lastURL = url; return true }
          func open(_ url: URL, configuration: OpenConfiguration, completionHandler: (NSObject?, Error?) -> Void) {
              TestActions.count += 1
              TestActions.lastURL = url
              completionHandler(nil, nil)
          }
      }
      struct ProjectOpener {
          static func isXcodeProject(at: URL) -> Bool { return !TestProjectRules.qualifies }
          func canOpen(_ url: URL) -> Bool { return TestProjectRules.qualifies }
          func open(_ url: URL) { TestActions.count += 1 }
      }
      enum XcodeProjectDetector {
          static func canOpen(_ url: URL) -> Bool { return TestProjectRules.qualifies }
      }
      struct FlutterProjectValidator {
          func isFlutterProject(at: URL) -> Bool { return TestProjectRules.qualifies }
      }
      struct GitFolderValidator {
          func isFolder(at: URL) -> Bool { return TestProjectRules.qualifies }
      }
      struct ProjectRequest {
          static let notificationName = Notification.Name("fixture")
          static let distributedObject = "fixture"
          static let pathUserInfoKey = "path"
          static func url(forPath: String) -> URL? { return URL(string: "fixture://project") }
      }
      struct FlutterManagerRequest { static func url(for: URL) -> URL? { return URL(string: "fixture://flutter") } }
      struct FlutterDependencyRequest { static func url(for: URL) -> URL? { return URL(string: "fixture://dependencies") } }
      struct FlutterDoctorRequest { static func url(for: URL) -> URL? { return URL(string: "fixture://doctor") } }
      struct FlutterCodegenRequest { static func url(for: URL) -> URL? { return URL(string: "fixture://codegen") } }
      struct FlutterRunRequest { static func url(for: URL) -> URL? { return URL(string: "fixture://run") } }
      struct GitPullRequest { static func url(for: URL) -> URL? { return URL(string: "fixture://git") } }
      final class DistributedNotificationCenter {
          static func `default`() -> DistributedNotificationCenter { return DistributedNotificationCenter() }
          func postNotificationName(_ name: Notification.Name, object: String?, userInfo: [String: String], deliverImmediately: Bool) {
              TestActions.count += 1
          }
      }
    SWIFT
  end

  def swift_checks
    factories = CONTAINER_EXTENSIONS.each_index.map { |index| "(\"extension#{index}\", FinderSync#{index}())" }.join(",\n")
    policies = CONTAINER_EXTENSIONS.each_index.map do |index|
      "{ FinderDesktopMenuPolicy#{index}.isDesktopContainer($0, desktopURLs: $1) }"
    end.join(",\n")
    <<~SWIFT
      var assertionCount = 0
      func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
          assertionCount += 1
          if !condition() {
              fputs("FAILED: \\(message)\\n", stderr)
              exit(1)
          }
      }
      func click(_ menu: NSMenu?) {
          guard let item = menu?.items.first, let target = item.target as? NSObject,
                let action = item.action else {
              expect(false, "missing action")
              return
          }
          _ = target.perform(action, with: item)
      }
      let fileManager = FileManager.default
      let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
      guard let passwordEntry = getpwuid(getuid()), let homePointer = passwordEntry.pointee.pw_dir else {
          fatalError("passwd home unavailable")
      }
      let passwdHome = URL(fileURLWithPath: String(cString: homePointer), isDirectory: true)
      let passwdDesktop = passwdHome.appendingPathComponent("Desktop", isDirectory: true).standardizedFileURL
      guard let redirectedHome = TestSandboxEnvironment.redirectedHome else {
          fatalError("sandbox fixture unavailable")
      }
      expect(passwdHome.path != redirectedHome, "passwd home must differ from injected sandbox HOME")
      expect(ProcessInfo.processInfo.environment["HOME"] == redirectedHome, "sandbox HOME is injected")
      expect(TestSandboxEnvironment.desktopURLs.first?.path.hasPrefix(redirectedHome) == true,
             "Foundation desktop discovery is redirected in the fixture")
      try fileManager.createDirectory(atPath: redirectedHome + "/Desktop", withIntermediateDirectories: true)
      expect(IOSSimulatorMenuContext.desktopURLs.first?.standardizedFileURL.path == passwdDesktop.path,
             "simulator: passwd desktop takes priority over sandbox aliases")
      expect(IOSSimulatorMenuContext.desktopURLs.dropFirst().contains(TestSandboxEnvironment.desktopURLs[0]),
             "simulator: the real discovery code consumes the redirected Foundation alias")
      expect(IOSSimulatorMenuContext.desktopURL?.standardizedFileURL.path == passwdDesktop.path,
             "simulator: default fallback uses actual passwd desktop")
      let injectedDesktop = root.appendingPathComponent("云盘/真实桌面", isDirectory: true)
      let injectedChild = injectedDesktop.appendingPathComponent("项目", isDirectory: true)
      let ordinary = root.appendingPathComponent("普通项目", isDirectory: true)
      let sameName = root.appendingPathComponent("其它/Desktop", isDirectory: true)
      let prefix = root.appendingPathComponent("云盘/真实桌面-copy", isDirectory: true)
      for directory in [injectedDesktop, injectedChild, ordinary, sameName, prefix] {
          try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
      }
      let desktopAlias = root.appendingPathComponent("桌面符号链接", isDirectory: true)
      try fileManager.createSymbolicLink(at: desktopAlias, withDestinationURL: injectedDesktop)
      let normalizedDesktop = URL(fileURLWithPath: injectedDesktop.path + "/项目/..", isDirectory: true)
      let policies: [(URL, [URL]) -> Bool] = [#{policies}]
      for policy in policies {
          expect(policy(injectedDesktop, [injectedDesktop]), "injected desktop")
          expect(policy(normalizedDesktop, [injectedDesktop]), "standardized desktop")
          expect(policy(desktopAlias, [injectedDesktop]), "desktop symlink")
          expect(policy(injectedDesktop, [desktopAlias]), "desktop location symlink")
          expect(!policy(injectedChild, [injectedDesktop]), "desktop subfolder remains")
          expect(!policy(sameName, [injectedDesktop]), "same-name Desktop remains")
          expect(!policy(prefix, [injectedDesktop]), "prefix directory remains")
          expect(!policy(ordinary, [injectedDesktop]), "ordinary folder remains")
          expect(!policy(URL(string: "https://example.test/Desktop")!, [injectedDesktop]), "non-file target")
          expect(!policy(injectedDesktop, []), "no configured desktop")
      }

      guard let desktop = FinderDesktopMenuPolicy0.desktopURLs.first else {
          fatalError("system desktop unavailable")
      }
      if let home = NSHomeDirectoryForUser(NSUserName()) {
          let actualDesktop = URL(fileURLWithPath: home, isDirectory: true).appendingPathComponent("Desktop", isDirectory: true)
          expect(FinderDesktopMenuPolicy0.isDesktopContainer(actualDesktop), "real user desktop included")
      }
      let controller = FIFinderSyncController.default()
      let extensions: [(String, FIFinderSync)] = [#{factories}]
      for (name, extensionInstance) in extensions {
          TestProjectRules.qualifies = true
          controller.selected = nil
          controller.targeted = desktop
          expect(extensionInstance.menu(for: .contextualMenuForContainer) == nil, "\\(name): desktop hidden")
          controller.targeted = ordinary
          let ordinaryMenu = extensionInstance.menu(for: .contextualMenuForContainer)
          expect(ordinaryMenu?.items.count == 1, "\\(name): ordinary container preserved")
          TestActions.count = 0
          click(ordinaryMenu)
          expect(TestActions.count == 1, "\\(name): ordinary click preserved")
          controller.targeted = desktop
          TestActions.count = 0
          click(ordinaryMenu)
          expect(TestActions.count == 0, "\\(name): stale desktop click rejected")
          controller.selected = [ordinary]
          let itemMenu = extensionInstance.menu(for: .contextualMenuForItems)
          expect(itemMenu?.items.count == 1, "\\(name): selected directory on desktop preserved")
          TestActions.count = 0
          click(itemMenu)
          expect(TestActions.count == 1, "\\(name): selected directory click preserved")
          controller.selected = [desktop]
          expect(extensionInstance.menu(for: .contextualMenuForItems)?.items.count == 1, "\\(name): selected desktop directory itself preserved")
          controller.targeted = desktop.appendingPathComponent("项目", isDirectory: true)
          expect(extensionInstance.menu(for: .contextualMenuForContainer)?.items.count == 1, "\\(name): desktop child container preserved")
          controller.targeted = sameName
          expect(extensionInstance.menu(for: .contextualMenuForContainer)?.items.count == 1, "\\(name): same-name folder container preserved")
          controller.targeted = nil
          expect(extensionInstance.menu(for: .contextualMenuForContainer) == nil, "\\(name): unknown container hidden")
          controller.targeted = ordinary
          TestProjectRules.qualifies = false
          expect(extensionInstance.menu(for: .contextualMenuForContainer) == nil, "\\(name): original project guard preserved")
          TestProjectRules.qualifies = true
          expect(extensionInstance.menu(for: .toolbarItemMenu) == nil, "\\(name): toolbar unchanged")
      }

      let simulator = FinderSync#{CONTAINER_EXTENSIONS.length}()
      expect(controller.directoryURLs.contains(URL(fileURLWithPath: "/", isDirectory: true)),
             "simulator: root monitoring must remain enabled for Finder desktop dispatch")
      controller.selected = nil
      controller.targeted = passwdDesktop
      let desktopMenu = simulator.menu(for: .contextualMenuForContainer)
      expect(desktopMenu?.items.map(\\.title) == ["🍎 新建 iOS 模拟器"], "simulator: desktop only item")
      TestActions.count = 0
      click(desktopMenu)
      expect(TestActions.count == 1, "simulator: desktop click dispatched")
      controller.targeted = ordinary
      expect(simulator.menu(for: .contextualMenuForContainer) == nil, "simulator: ordinary folder hidden")
      TestActions.count = 0
      click(desktopMenu)
      expect(TestActions.count == 0, "simulator: stale ordinary folder click rejected")
      controller.targeted = passwdDesktop
      controller.selected = [ordinary]
      expect(simulator.menu(for: .contextualMenuForItems) == nil, "simulator: desktop selected directory hidden")
      controller.targeted = ordinary
      expect(simulator.menu(for: .contextualMenuForItems) == nil, "simulator: ordinary selected directory hidden")
      controller.targeted = nil
      controller.selected = nil
      expect(simulator.menu(for: .contextualMenuForContainer)?.items.count == 1, "simulator: nil targeted desktop fallback")
      expect(IOSSimulatorMenuContext.candidateURL(isContainer: true, targetedURL: nil, selectedURLs: nil)?.path == passwdDesktop.path,
             "simulator: nil targeted fallback is the real user desktop, never sandbox Desktop")
      expect(IOSSimulatorMenuContext.candidateURL(isContainer: true, targetedURL: nil, selectedURLs: nil, desktopURL: injectedDesktop) != nil,
             "simulator: injected desktop fallback")
      expect(IOSSimulatorMenuContext.candidateURL(isContainer: true, targetedURL: ordinary, selectedURLs: nil, desktopURL: injectedDesktop) == nil,
             "simulator: injected ordinary container rejected")
      expect(IOSSimulatorMenuContext.candidateURL(isContainer: false, targetedURL: injectedDesktop, selectedURLs: [injectedDesktop], desktopURL: injectedDesktop) == nil,
             "simulator: injected items rejected")
      let unavailableDesktop = root.appendingPathComponent("unavailable-parent/Desktop", isDirectory: true)
      expect((try? fileManager.attributesOfItem(atPath: unavailableDesktop.path)) == nil,
             "fixture: known desktop metadata is actually unavailable")
      expect(IOSSimulatorMenuContext.candidateURL(isContainer: true, targetedURL: unavailableDesktop, selectedURLs: nil, desktopURL: unavailableDesktop)?.path == unavailableDesktop.path,
             "simulator: known desktop remains eligible when metadata cannot be read")
      expect(IOSSimulatorMenuContext.candidateURL(isContainer: true, targetedURL: nil, selectedURLs: nil, desktopURL: unavailableDesktop)?.path == unavailableDesktop.path,
             "simulator: known fallback desktop does not require metadata access")
      expect(IOSSimulatorMenuContext.candidateURL(isContainer: true, targetedURL: ordinary, selectedURLs: nil, desktopURL: unavailableDesktop) == nil,
             "simulator: unavailable desktop metadata never permits ordinary folders")
      #{android_simulator_checks}
      print("PASS: \\(assertionCount) desktop menu assertions")
    SWIFT
  end

  def android_simulator_checks
    <<~SWIFT
      expect(AndroidSimulatorMenuContext.desktopURLs.first?.standardizedFileURL.path == passwdDesktop.path,
             "android: passwd desktop takes priority over sandbox aliases")
      expect(AndroidSimulatorMenuContext.desktopURLs.dropFirst().contains(TestSandboxEnvironment.desktopURLs[0]),
             "android: the real discovery code consumes the redirected Foundation alias")
      expect(AndroidSimulatorMenuContext.desktopURL?.standardizedFileURL.path == passwdDesktop.path,
             "android: default fallback uses actual passwd desktop")
      let androidSimulator = FinderSync#{CONTAINER_EXTENSIONS.length + 1}()
      expect(controller.directoryURLs.contains(URL(fileURLWithPath: "/", isDirectory: true)),
             "android: root monitoring must remain enabled for Finder desktop dispatch")
      controller.selected = nil
      controller.targeted = passwdDesktop
      let androidDesktopMenu = androidSimulator.menu(for: .contextualMenuForContainer)
      expect(androidDesktopMenu?.items.map(\\.title) == ["📱 新建 Android 模拟器"], "android: desktop only item")
      TestActions.count = 0
      click(androidDesktopMenu)
      expect(TestActions.count == 1, "android: desktop click dispatched")
      controller.targeted = ordinary
      expect(androidSimulator.menu(for: .contextualMenuForContainer) == nil, "android: ordinary folder hidden")
      TestActions.count = 0
      click(androidDesktopMenu)
      expect(TestActions.count == 0, "android: stale ordinary folder click rejected")
      controller.targeted = passwdDesktop
      controller.selected = [ordinary]
      expect(androidSimulator.menu(for: .contextualMenuForItems) == nil, "android: desktop selected directory hidden")
      controller.targeted = ordinary
      expect(androidSimulator.menu(for: .contextualMenuForItems) == nil, "android: ordinary selected directory hidden")
      expect(androidSimulator.menu(for: .toolbarItemMenu) == nil, "android: toolbar unchanged")
      controller.targeted = nil
      controller.selected = nil
      expect(androidSimulator.menu(for: .contextualMenuForContainer)?.items.count == 1, "android: nil targeted desktop fallback")
      expect(AndroidSimulatorMenuContext.candidateURL(isContainer: true, targetedURL: nil, selectedURLs: nil)?.path == passwdDesktop.path,
             "android: nil targeted fallback is the real user desktop, never sandbox Desktop")
      expect(AndroidSimulatorMenuContext.candidateURL(isContainer: true, targetedURL: nil, selectedURLs: nil, desktopURL: injectedDesktop) != nil,
             "android: injected desktop fallback")
      expect(AndroidSimulatorMenuContext.candidateURL(isContainer: true, targetedURL: ordinary, selectedURLs: nil, desktopURL: injectedDesktop) == nil,
             "android: injected ordinary container rejected")
      expect(AndroidSimulatorMenuContext.candidateURL(isContainer: false, targetedURL: injectedDesktop, selectedURLs: [injectedDesktop], desktopURL: injectedDesktop) == nil,
             "android: injected items rejected")
      expect(AndroidSimulatorMenuContext.candidateURL(isContainer: true, targetedURL: desktopAlias, selectedURLs: nil, desktopURL: injectedDesktop)?.path == injectedDesktop.path,
             "android: desktop symlink remains eligible")
      expect(AndroidSimulatorMenuContext.candidateURL(isContainer: true, targetedURL: unavailableDesktop, selectedURLs: nil, desktopURL: unavailableDesktop)?.path == unavailableDesktop.path,
             "android: known desktop remains eligible when metadata cannot be read")
      expect(AndroidSimulatorMenuContext.candidateURL(isContainer: true, targetedURL: nil, selectedURLs: nil, desktopURL: unavailableDesktop)?.path == unavailableDesktop.path,
             "android: known fallback desktop does not require metadata access")
      expect(AndroidSimulatorMenuContext.candidateURL(isContainer: true, targetedURL: ordinary, selectedURLs: nil, desktopURL: unavailableDesktop) == nil,
             "android: unavailable desktop metadata never permits ordinary folders")
    SWIFT
  end
end
