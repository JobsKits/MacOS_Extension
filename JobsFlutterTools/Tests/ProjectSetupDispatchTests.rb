# frozen_string_literal: true
# Created by Jobs on 2026年10月28日，星期三。
# 私有工程配假业务入口，验证环境选择不会被旧 FVM 门禁截断。
require 'fileutils'
require 'minitest/autorun'
require 'open3'
require 'tmpdir'

class ProjectSetupDispatchTests < Minitest::Test
  TOOLS = File.expand_path('../Scripts/Tools', __dir__)

  def setup
    @root = File.realpath(Dir.mktmpdir('jobs-setup-dispatch-'))
    @project = File.join(@root, "项目 空格 ' $(touch NEVER) ; literal")
    @tools = File.join(@root, 'tools')
    FileUtils.mkdir_p([File.join(@project, 'lib'), @tools])
    File.write(File.join(@project, 'pubspec.yaml'), "name: fixture\ndependencies:\n  flutter:\n    sdk: flutter\n")
    FileUtils.cp(File.join(TOOLS, 'DispatchFlutterTools.zsh'), @tools)
    %w[SetupFlutterProject.zsh DownloadProjectGradle.zsh].each do |name|
      File.write(File.join(@tools, name), <<~'SH')
        #!/bin/zsh
        printf '%s\0' "${0:t}" "$@" > "$JOBS_TEST_TRACE"
        exit "${JOBS_TEST_CODE:-0}"
      SH
    end
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def dispatch(action, code = 0, target = @project)
    Open3.capture3({ 'HOME' => @root, 'JOBS_TEST_TRACE' => File.join(@root, 'trace'),
                    'JOBS_TEST_CODE' => code.to_s }, '/bin/zsh',
                  File.join(@tools, 'DispatchFlutterTools.zsh'), action, target)
  end

  def test_setup_without_fvm_reaches_selector_and_preserves_literal_project_path
    out, err, result = dispatch('project-setup')
    assert result.success?, out + err
    assert_equal ['SetupFlutterProject.zsh', '--project', @project], File.binread(File.join(@root, 'trace')).force_encoding('UTF-8').split("\0")
    refute File.exist?(File.join(@project, 'NEVER'))
    refute File.exist?(File.join(@project, '.fvmrc'))
  end

  def test_gradle_download_without_fvm_uses_its_java_and_sdk_resolution
    out, err, result = dispatch('gradle-download')
    assert result.success?, out + err
    assert_equal ['DownloadProjectGradle.zsh', '--project', @project], File.binread(File.join(@root, 'trace')).force_encoding('UTF-8').split("\0")
  end

  def test_cancel_and_failure_codes_stop_dispatch
    [130, 41].each do |code|
      _, _, result = dispatch('project-setup', code)
      assert_equal code, result.exitstatus
    end
  end

  def test_nonproject_is_rejected_before_business
    target = File.join(@root, 'ordinary')
    FileUtils.mkdir_p(target)
    out, err, result = dispatch('gradle-download', 0, target)
    refute result.success?, out + err
    refute File.exist?(File.join(@root, 'trace'))
  end

  def test_existing_sdk_gate_remains_for_unrelated_actions
    out, err, result = dispatch('codegen')
    refute result.success?, out + err
    assert_includes out + err, '尚未通过 FVM'
    refute File.exist?(File.join(@root, 'trace'))
  end
end
