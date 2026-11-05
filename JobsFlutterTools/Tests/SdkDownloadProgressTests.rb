# frozen_string_literal: true
# 只用临时假 SDK 验证首次初始化的实时进度，不下载、安装或修改真实缓存。
require 'fileutils'
require 'json'
require 'minitest/autorun'
require 'open3'
require 'shellwords'
require 'tmpdir'

class SdkDownloadProgressTests < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)
  FILTERS = %w[JobsFlutterDoctor/Scripts/InspectFlutterProject.zsh JobsFlutterCodegen/Scripts/GenerateFlutterCode.zsh
               JobsFlutterTools/Scripts/Tools/InspectFlutterProject.zsh JobsFlutterTools/Scripts/Tools/GenerateFlutterCode.zsh].freeze
  MANAGERS = %w[JobsFlutterVersionMgr/Scripts/ManageFlutterVersion.zsh JobsFlutterTools/Scripts/Tools/ManageFlutterVersion.zsh].freeze
  INSPECTORS = %w[JobsFlutterSdkInspector/Scripts/InspectFlutterSdkVersion.zsh JobsFlutterTools/Scripts/Tools/InspectFlutterSdkVersion.zsh].freeze

  def setup
    @root = Dir.mktmpdir('jobs-sdk-progress-')
    @log = File.join(@root, 'action.log')
    @machine = File.join(@root, 'machine.json')
    @fake = File.join(@root, 'fake flutter 中文')
    File.write(@log, '')
    File.write(@fake, <<~'ZSH')
      #!/bin/zsh
      printf 'Downloading Dart 25%%\r' >&2
      if [[ -n "${FIXTURE_RELEASE:-}" ]]; then
        while [[ ! -f "$FIXTURE_RELEASE" ]]; do /bin/sleep 0.1; done
      else
        /bin/sleep "${FIXTURE_DELAY:-0.2}"
      fi
      printf '100%%\rcomplete-no-newline' >&2
      printf '{"frameworkVersion":"3.99.1"}\n'
      exit "${FIXTURE_RESULT:-0}"
    ZSH
    File.chmod(0o700, @fake)
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def library(relative)
    File.read(File.join(ROOT, relative)).sub(/^main "\$@"\s*\z/, '')
  end

  def capture(relative, body, environment = {})
    Open3.capture3({ 'NO_COLOR' => '1' }.merge(environment), '/bin/zsh', '-f', '-c', library(relative) + "\n" + body)
  end

  def inspector_body
    <<~ZSH
      FSI_LOG_FILE=#{@log.shellescape}
      FSI_MACHINE_FILE=#{@machine.shellescape}
      fsi_probe_with_timeout #{@fake.shellescape} 10
    ZSH
  end

  def test_ansi_filters_stream_carriage_return_before_newline_and_preserve_split_escapes
    FILTERS.each do |relative|
      release = File.join(@root, 'release-filter')
      FileUtils.rm_f(release)
      body = <<~'ZSH'
        { printf '\033[3'; /bin/sleep 0.1; printf '1m25%%\r\033[0m'; while [[ ! -f "$FIXTURE_RELEASE" ]]; do /bin/sleep 0.1; done; printf '\344\270'; /bin/sleep 0.1; printf '\255文尾部'; } | strip_ansi_text
      ZSH
      Open3.popen3({ 'FIXTURE_RELEASE' => release }, '/bin/zsh', '-f', '-c', library(relative) + "\n" + body) do |input, output, errors, process|
        input.close
        first = ''
        begin
          assert IO.select([output], nil, nil, 10), "buffered CR progress: #{relative}"
          first = output.readpartial(4096)
          assert_includes first, "25%\r", relative
          assert process.alive?, relative
        ensure
          File.write(release, '')
        end
        assert_equal "25%\r中文尾部".b, (first + output.read).b, relative
        assert process.value.success?, errors.read
      end
    end
  end

  def test_osc_titles_do_not_swallow_download_lines_between_them
    FILTERS.each do |relative|
      body = <<~'ZSH'
        { printf '\033]0;first\033'; /bin/sleep 0.1; printf '\\\nDownloading SDK 25%%\r\n\033]0;second\033\\\nDone\n'; } | strip_ansi_text
      ZSH
      output, errors, result = capture(relative, body)
      assert result.success?, errors
      assert_equal "\nDownloading SDK 25%\r\n\nDone\n", output, relative
    end
  end

  def test_version_manager_keeps_machine_json_separate_and_preserves_failure
    MANAGERS.each do |relative|
      [0, 7].each do |code|
        body = <<~ZSH
          FM_FVM=#{@fake.shellescape}
          FM_RUN_DIR=#{@root.shellescape}
          LOG_FILE=#{@log.shellescape}
          fm_capture_flutter_version
        ZSH
        output, errors, result = capture(relative, body, 'FIXTURE_RESULT' => code.to_s)
        assert_equal code, result.exitstatus, errors
        assert_equal '3.99.1', JSON.parse(output)['frameworkVersion']
        assert_equal output.b, File.binread(File.join(@root, 'flutter-machine.json'))
        assert_includes errors, "25%\r100%\rcomplete-no-newline"
        assert_includes File.read(@log), "25%\r100%\rcomplete-no-newline"
      end
    end
  end

  def test_inspectors_stream_sdk_bootstrap_and_keep_parseable_machine_file
    INSPECTORS.each do |relative|
      [0, 7].each do |code|
        output, errors, result = capture(relative, inspector_body, 'FIXTURE_RESULT' => code.to_s)
        assert_equal code, result.exitstatus, errors
        assert_equal '3.99.1', JSON.parse(output)['frameworkVersion']
        assert_equal output.b, File.binread("#{@machine}.raw")
        assert_includes errors, "25%\r100%\rcomplete-no-newline"
        assert_includes File.read(@log), "25%\r100%\rcomplete-no-newline"
      end
    end
  end

  def test_inspector_exposes_live_stderr_before_sdk_exits
    INSPECTORS.each do |relative|
      release = File.join(@root, 'release-inspector')
      FileUtils.rm_f(release)
      Open3.popen3({ 'FIXTURE_RELEASE' => release }, '/bin/zsh', '-f', '-c', library(relative) + "\n" + inspector_body) do |input, output, errors, process|
        input.close
        begin
          assert IO.select([errors], nil, nil, 8), relative
          assert_includes errors.readpartial(4096), "Downloading Dart 25%\r"
          assert process.alive?, relative
        ensure
          File.write(release, '')
        end
        output.read
        errors.read
        assert process.value.success?, relative
      end
    end
  end

  def test_system_flutter_homebrew_install_preserves_tty_and_user_cancel_code
    [0, 130].each do |code|
      File.write(@fake, <<~'ZSH')
        #!/bin/zsh
        [[ -t 1 && "$*" == 'install --cask flutter' ]] || exit 81
        printf 'Flutter Cask 25%%\r100%%\n'
        exit "${FIXTURE_RESULT:-0}"
      ZSH
      body = <<~ZSH
        SF_PROJECT=#{@root.shellescape}
        PE_RUN_DIR=#{@root.shellescape}
        PE_LOG_FILE=#{@log.shellescape}
        PJ_BREW=#{@fake.shellescape}
        PJ_BREW_PREFIX=#{@root.shellescape}
        pe_select() { PE_SELECTION=install; }
        pj_find_brew() { return 0; }
        sf_probe_flutter() { return 0; }
        sf_prepare_system_flutter
      ZSH
      source = "source #{File.join(ROOT, 'JobsFlutterTools/Scripts/Tools/ProjectEnvironment.zsh').shellescape}\n" +
               "source #{File.join(ROOT, 'JobsFlutterTools/Scripts/Tools/SetupFlutterProject.zsh').shellescape}\n"
      output, errors, result = Open3.capture3({ 'FIXTURE_RESULT' => code.to_s }, '/bin/zsh', '-f', '-c', source + "\n" + body, stdin_data: "y\n")
      assert_equal code, result.exitstatus, output + errors
      assert_includes output, "Flutter Cask 25%\r100%"
      assert_includes File.read(@log), 'Flutter Cask 25%'
    end
  end

  def test_inspector_timeout_remains_bounded
    INSPECTORS.each do |relative|
      output, errors, result = capture(relative, inspector_body.sub(' 10', ' 0'), 'FIXTURE_DELAY' => '3')
      assert_equal 124, result.exitstatus, errors
      assert_includes output, 'SDK 版本查询超时'
    end
  end
end
