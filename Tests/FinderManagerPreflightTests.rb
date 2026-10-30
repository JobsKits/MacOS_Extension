# frozen_string_literal: true
# 只在临时工程夹具中验证源码预检隔离；所有构建、登记、卸载与 Finder 刷新均被替身阻断。
require 'minitest/autorun'
require 'open3'
require 'tmpdir'
require 'fileutils'
require_relative 'IsolatedInstallerDefinitions'

class FinderManagerPreflightTests < Minitest::Test
  include IsolatedInstallerDefinitions
  ROOT = File.expand_path('..', __dir__)
  MANAGER = File.join(ROOT, 'Scripts/ManageFinderExtensions.zsh')
  SOURCE = File.read(MANAGER)
  KEYS = SOURCE[/^FEATURE_KEYS=\(([^)]+)\)/, 1].split.freeze
  PROJECTS = SOURCE.scan(/^FEATURE_PROJECT_DIR\[([^\]]+)\]="([^"]+)"/).to_h.freeze
  PANEL_FEATURES = File.read(File.join(ROOT, 'Scripts/SelectFinderExtensionFeatures.swift')).scan(/FeatureOption\(identifier: "([^"]+)"/).flatten.freeze

  def test_missing_unselected_project_does_not_block_selected_project
    output, errors, result = run_fixture('path_copier', available: ['path_copier'])
    assert result.success?, output + errors
    assert_includes output, 'INSTALL=path_copier'
    assert_includes output, 'SUMMARY=0|1|0'
    refute_includes output, 'JobsFileCreator.xcodeproj'
    refute_includes errors, 'blocked unexpected system operation'
  end

  def test_selecting_every_leaf_with_one_missing_project_only_fails_that_unit
    output, errors, result = run_fixture(PANEL_FEATURES.join(','), available: KEYS - ['file-create'])
    assert_equal 1, result.exitstatus, output + errors
    installs = output.lines.grep(/^INSTALL=/).map { |line| line.chomp.delete_prefix('INSTALL=') }
    assert_equal (KEYS - ['file-create']).sort, installs.sort
    assert_includes output, "SUMMARY=1|#{PANEL_FEATURES.length - 1}|1"
    assert_includes output, 'JobsFileCreator/JobsFileCreator.xcodeproj/project.pbxproj'
    events = output.lines.grep(/^JOBS_MANAGER_EVENT\t/).map { |line| line.split("\t")[1, 2] }
    assert_equal [['file-create', 'failed']], events.select { |_, state| state == 'failed' }
    assert_equal PANEL_FEATURES.length - 1, events.count { |_, state| state == 'succeeded' }
    assert_includes output, "JOBS_MANAGER_EVENT\tflutter-maintenance\tsucceeded"
    refute_includes errors, 'blocked unexpected system operation'
  end

  def test_missing_shared_project_fails_its_selected_leaves_and_continues
    output, errors, result = run_fixture('git-pull,git-rollback,path_copier', available: ['path_copier'])
    assert_equal 1, result.exitstatus, output + errors
    assert_equal ['INSTALL=path_copier'], output.lines.map(&:chomp).grep(/^INSTALL=/)
    assert_includes output, 'SUMMARY=1|1|2'
    assert_includes output, 'JobsProjectTools/JobsProjectTools.xcodeproj/project.pbxproj'
    assert_includes output, "JOBS_MANAGER_EVENT\tgit-pull\tfailed"
    assert_includes output, "JOBS_MANAGER_EVENT\tgit-rollback\tfailed"
    refute_includes output, 'JobsFileCreator.xcodeproj'
    refute_includes errors, 'blocked unexpected system operation'
  end

  def test_no_argument_source_diagnostic_only_checks_the_selected_plan
    output, errors, result = run_fixture('path_copier', available: ['path_copier'], checks: <<~'ZSH')
      parse_feature_selection "$CLI_FEATURES" || exit 1
      ensure_feature_projects_exist || exit 1
      print -r -- selected-project-ready
    ZSH
    assert result.success?, output + errors
    assert_equal "selected-project-ready\n", output
  end

  def test_missing_selected_source_reports_the_exact_runtime_path_before_any_work
    output, errors, result = run_fixture('file-create', available: [])
    assert_equal 1, result.exitstatus, output + errors
    assert_includes output, 'SUMMARY=1|0|1'
    assert_match(%r{jobs-finder-preflight-[^\n]+/搬迁后的源码 中文/JobsFileCreator/JobsFileCreator\.xcodeproj/project\.pbxproj}, output)
    refute_match(/^(?:INSTALL|UNINSTALL)=/, output)
    refute_includes errors, 'blocked unexpected system operation'
  end

  def test_required_global_environment_failures_still_stop_before_all_work
    [
      { 'JOBS_TEST_PLATFORM' => 'Linux' },
      { 'JOBS_TEST_MISSING_COMMAND' => 'pluginkit' },
      { 'JOBS_TEST_XCODE_RESULT' => '1' },
      { 'JOBS_TEST_MISSING_LSREGISTER' => '1' }
    ].each do |environment|
      output, errors, result = run_fixture('path_copier', available: ['path_copier'], environment: environment)
      assert_equal 1, result.exitstatus, environment.inspect + output + errors
      refute_match(/^(?:INSTALL|UNINSTALL|REFRESH)=/, output)
      refute_includes output, "JOBS_MANAGER_EVENT\t"
      refute_includes errors, 'blocked unexpected system operation'
    end
  end

  def test_uninstall_does_not_require_project_sources_or_xcode
    output, errors, result = run_fixture('path_copier,file-create', available: [], action: 'uninstall', environment: { 'JOBS_TEST_XCODE_RESULT' => '1' })
    assert result.success?, output + errors
    assert_equal ['UNINSTALL=path_copier', 'UNINSTALL=file-create'], output.lines.map(&:chomp).grep(/^UNINSTALL=/)
    assert_includes output, 'SUMMARY=0|2|0'
    refute_includes output, '.xcodeproj/project.pbxproj'
    refute_includes errors, 'blocked unexpected system operation'
  end

  private

  def run_fixture(selection, available:, action: 'install', environment: {}, checks: nil)
    replacements = {
      '/usr/bin/xcode-select' => 'jobs_fixture_xcode_select',
      'command -v "$command_name"' => 'jobs_fixture_command_present "$command_name"'
    }
    definitions = isolated_installer_source(MANAGER, replacements: replacements)
    Dir.mktmpdir('jobs-finder-preflight-') do |temporary|
      workspace = File.join(File.realpath(temporary), '搬迁后的源码 中文')
      FileUtils.mkdir_p(workspace)
      available.each do |key|
        project = File.join(workspace, PROJECTS.fetch(key), "#{PROJECTS.fetch(key)}.xcodeproj")
        FileUtils.mkdir_p(project)
        File.write(File.join(project, 'project.pbxproj'), '// isolated source-presence fixture; never built')
      end
      File.write(File.join(workspace, 'selector.swift'), '// isolated UI source presence fixture')
      setup = <<~'ZSH'
        WORKSPACE_DIR="$1"
        FEATURE_SELECTOR_SOURCE_PATH="$WORKSPACE_DIR/selector.swift"
        LOG_FILE="$WORKSPACE_DIR/session.log"
        CLI_FEATURES="$2"
        MANAGEMENT_ACTION="$3"
        MANAGER_NON_INTERACTIVE=1
        [[ "$CLI_FEATURES" == all ]] && CLI_FEATURES="${(j:,:)SELECTABLE_FUNCTION_IDS}"
        uname() { print -r -- "${JOBS_TEST_PLATFORM:-Darwin}"; }
        jobs_fixture_command_present() { [[ "$1" != "${JOBS_TEST_MISSING_COMMAND:-}" ]]; }
        jobs_fixture_xcode_select() { return "${JOBS_TEST_XCODE_RESULT:-0}"; }
        lsregister_path() { [[ "${JOBS_TEST_MISSING_LSREGISTER:-0}" == 0 ]] && print -r -- fixture-lsregister; }
        install_feature() { print -r -- "INSTALL=$1"; }
        uninstall_feature() { print -r -- "UNINSTALL=$1"; }
        restart_finder_after_install() { print -r -- 'REFRESH=fixture-only'; }
      ZSH
      checks ||= <<~'ZSH'
        run_management_worker
        worker_result=$?
        print -r -- "SUMMARY=$worker_result|${#SUCCEEDED_FEATURES[@]}|${#FAILED_FEATURES[@]}"
        exit "$worker_result"
      ZSH
      fixture = File.join(temporary, 'preflight.zsh')
      File.write(fixture, definitions + setup + checks)
      Open3.capture3(isolated_installer_environment(temporary).merge(environment), '/bin/zsh', '-f', fixture, workspace, selection, action)
    end
  end
end
