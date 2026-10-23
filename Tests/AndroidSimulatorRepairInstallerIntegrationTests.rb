# frozen_string_literal: true
# 只读取真实安装器定义并在临时 Shell 内核对映射，不构建、注册扩展或操作模拟器。

require 'minitest/autorun'
require 'open3'
require 'tmpdir'

class AndroidSimulatorRepairInstallerIntegrationTests < Minitest::Test
  ROOT = File.expand_path('..', __dir__)
  INSTALLER = File.join(ROOT, '【MacOS】🧩安装Finder扩展.command')
  UNINSTALLER = File.join(ROOT, '【MacOS】🧩卸载Finder扩展.command')
  PROJECT = File.join(ROOT, 'JobsAndroidSimulatorRepairer')
  KEY = 'android-simulator-repair'
  APP = 'JobsAndroidSimulatorRepairer'
  APP_ID = 'com.jobs.androidsimulatorrepairer'

  def test_selector_contains_android_once_next_to_ios
    selector = File.read(File.join(ROOT, 'Scripts/SelectFinderExtensionFeatures.swift'))
    options = selector.scan(/FeatureOption\(identifier: "([^"]+)", title: "([^"]+)"\)/)
    assert_equal [[KEY, 'Android 模拟器检测与修复']], options.select { |identifier, _| identifier == KEY }
    identifiers = options.map(&:first)
    assert_operator identifiers.index(KEY), :>, identifiers.index('ios-simulator-create')
    assert_operator identifiers.index(KEY), :<, identifiers.index('terminal_open')
  end

  def test_install_mapping_is_independent_and_keeps_explicit_android_identity
    output = run_definitions(INSTALLER, <<~'ZSH', ROOT)
      WORKSPACE_DIR="$1"
      parse_feature_selection 'android-simulator-repair,android-simulator-repair' || exit 1
      print -r -- "${(j:,:)SELECTED_KEYS}"
      print -r -- "${FEATURE_TITLE[android-simulator-repair]}"
      print -r -- "${FEATURE_SCHEME[android-simulator-repair]}"
      print -r -- "${FEATURE_APP_NAME[android-simulator-repair]}"
      print -r -- "${FEATURE_EXTENSION_NAME[android-simulator-repair]}"
      app_bundle_id_for_key android-simulator-repair
      print -r -- "${FEATURE_EXTENSION_ID[android-simulator-repair]}"
      print -r -- "terminal:${TERMINAL_OPENER_ENABLED_FEATURES}"
      project_file_for_key android-simulator-repair
      derived_data_dir_for_key android-simulator-repair
    ZSH
    assert_equal [KEY, 'Android 模拟器检测与修复', APP, APP, 'JobsAndroidSimulatorRepairFinderSync.appex',
                  APP_ID, "#{APP_ID}.findersync", 'terminal:', File.join(PROJECT, "#{APP}.xcodeproj"),
                  File.join(ROOT, "work/#{APP}DerivedData")], output.lines.map(&:strip)
  end

  def test_install_selection_can_combine_both_mobile_platforms_and_terminal
    output = run_definitions(INSTALLER, <<~'ZSH')
      parse_feature_selection 'android-simulator-repair,ios-simulator-create,terminal_open,android-simulator-repair' || exit 1
      print -r -- "${(j:,:)SELECTED_KEYS}"
      print -r -- "$TERMINAL_OPENER_ENABLED_FEATURES"
    ZSH
    assert_equal ['android-simulator-repair,ios-simulator-create,terminal_opener', 'open'], output.lines.map(&:strip)
  end

  def test_uninstall_mapping_keeps_android_process_marker_log_and_derived_data
    output = run_definitions(UNINSTALLER, <<~'ZSH', ROOT)
      WORKSPACE_DIR="$1"
      parse_fzf_selection "${FEATURE_TITLE[android-simulator-repair]}" || exit 1
      print -r -- "${(j:,:)SELECTED_KEYS}"
      print -r -- "${FEATURE_PROJECT_DIR[android-simulator-repair]}"
      print -r -- "${FEATURE_APP_NAME[android-simulator-repair]}"
      print -r -- "${FEATURE_EXTENSION_PROCESS_NAME[android-simulator-repair]}"
      print -r -- "${FEATURE_EXTENSION_ID[android-simulator-repair]}"
      print -r -- "${FEATURE_REFRESH_MARKER[android-simulator-repair]}"
      print -r -- "${FEATURE_RUNTIME_LOG[android-simulator-repair]}"
      local_derived_data_dir_for_key android-simulator-repair
    ZSH
    assert_equal [KEY, APP, APP, 'JobsAndroidSimulatorRepairFinderSync', "#{APP_ID}.findersync",
                  "/tmp/#{APP}NeedsFinderRestart", "/tmp/#{APP}.log",
                  File.join(ROOT, "work/#{APP}DerivedData")], output.lines.map(&:strip)
  end

  def test_registration_initializes_android_host_without_creating_a_simulator
    output = run_definitions(INSTALLER, <<~'ZSH', replacements: {'/usr/bin/open' => 'jobs_record_open'})
      jobs_record_open() {
        print -r -- "${(j:|:)@}"
      }
      open_host_for_extension_registration android-simulator-repair '/fixture/中文 space/JobsAndroidSimulatorRepairer.app'
    ZSH
    assert_equal ['-gj|/fixture/中文 space/JobsAndroidSimulatorRepairer.app|--args|--initialize-finder-extension'], output.lines.map(&:strip)
  end

  def test_missing_android_project_is_reported_before_building
    Dir.mktmpdir('jobs-android-missing-project-') do |workspace|
      output = run_definitions(INSTALLER, <<~'ZSH', workspace)
        WORKSPACE_DIR="$1"
        for key in "${FEATURE_KEYS[@]}"; do
          [[ "$key" == android-simulator-repair ]] && continue
          /bin/mkdir -p "$(project_file_for_key "$key")"
          print -r -- '// fixture' > "$(project_file_for_key "$key")/project.pbxproj"
        done
        log() { print -r -- "$1"; }
        if ensure_feature_projects_exist; then
          exit 1
        fi
        print -r -- 'installation-stopped'
      ZSH
      assert_includes output, 'JobsAndroidSimulatorRepairer.xcodeproj/project.pbxproj'
      assert_includes output, 'installation-stopped'
      assert_includes output, '重新取得包含全部工程源码的完整 MacOS@Extension 仓库'
      refute_includes output, 'JobsIOSSimulatorCreator.xcodeproj/project.pbxproj'
    end
  end

  def test_standalone_project_declares_both_targets_and_bundled_business_script
    project = File.read(File.join(PROJECT, "#{APP}.xcodeproj/project.pbxproj"))
    assert_includes project, 'PRODUCT_BUNDLE_IDENTIFIER = com.jobs.androidsimulatorrepairer;'
    assert_includes project, 'PRODUCT_BUNDLE_IDENTIFIER = com.jobs.androidsimulatorrepairer.findersync;'
    assert_includes project, 'RepairAndroidSimulator.zsh in Resources'
    assert_includes project, 'JobsAndroidSimulatorRepairFinderSync.appex in Embed App Extensions'
    assert File.file?(File.join(PROJECT, '【MacOS】安装Android模拟器检测修复Finder扩展.command'))
    assert File.file?(File.join(PROJECT, '【MacOS】卸载Android模拟器检测修复Finder扩展.command'))
    refute_includes project, 'IOSSimulator'
    refute_includes project, 'iossimulator'
  end

  private

  def run_definitions(path, checks, *arguments, replacements: {})
    source = File.read(path)
    raise '真实主入口未找到' unless source.sub!(/^main "\$@"\s*\z/, '')
    replacements.each { |from, to| source = source.gsub(from, to) }
    Dir.mktmpdir('jobs-android-install-mapping-') do |directory|
      fixture = File.join(directory, 'mapping.zsh')
      File.write(fixture, source + "\n" + checks)
      output, status = Open3.capture2e({'NO_COLOR' => '1'}, '/bin/zsh', '-f', fixture, *arguments)
      assert status.success?, output
      output
    end
  end
end
