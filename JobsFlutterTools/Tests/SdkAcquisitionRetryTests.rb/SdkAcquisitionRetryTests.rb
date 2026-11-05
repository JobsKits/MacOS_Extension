# Created by Jobs. Isolated SDK acquisition, no real network or tool installation.
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'shellwords'
require 'timeout'
require 'digest'

class SdkAcquisitionRetryTests < Minitest::Test
  ROOT = File.expand_path('../../..', __dir__)
  MODULE = File.join(ROOT, 'JobsFlutterTools/Scripts/Tools/【MacOS】SDK获取重试.zsh/【MacOS】SDK获取重试.zsh')
  RUNNERS = %w[JobsFlutterRunner/Scripts/RunFlutterProject.zsh JobsFlutterTools/Scripts/Tools/RunFlutterProject.zsh].freeze

  def setup
    @tmp = Dir.mktmpdir('jobs-sdk-retry-中文')
    @log = File.join(@tmp, 'sdk.log')
    @counter = File.join(@tmp, 'attempt')
    @tool = File.join(@tmp, 'fake sdk')
    File.write(@tool, <<~'SH')
      #!/bin/zsh
      attempt=0
      [[ ! -f "$COUNT" ]] || attempt=$(<"$COUNT")
      (( attempt++ ))
      print -r -- "$attempt" > "$COUNT"
      printf 'download %s\r' "$attempt" >> "$LOG"
      if (( attempt <= ${FAILURES:-2} )); then
        print -r -- "${FAIL_TEXT:-Connection reset}" >> "$LOG"
        exit "${FAIL_CODE:-1}"
      fi
      print -r -- '{"sdk":"ready"}'
    SH
    File.chmod(0o700, @tool)
  end

  def teardown
    FileUtils.remove_entry(@tmp)
  end

  def env(extra = {})
    { 'COUNT' => @counter, 'LOG' => @log, 'JOBS_SDK_RETRY_DELAY' => '0', 'NO_COLOR' => '1' }.merge(extra)
  end

  def run_retry(extra = {}, prefix = '')
    Timeout.timeout(10) do
      Open3.capture3(env(extra), '/bin/zsh', '-f', '-c', "source #{MODULE.shellescape}\n#{prefix}\njobs_sdk_retry SDK #{@log.shellescape} #{@tool.shellescape}")
    end
  end

  def test_keeps_retrying_then_succeeds_without_polluting_machine_stdout
    out, err, status = run_retry('FAILURES' => '5')
    assert status.success?, err
    assert_equal "{\"sdk\":\"ready\"}\n", out
    assert_equal '6', File.read(@counter).strip
    assert_includes err, '第 6 次'
    assert_equal 6, File.read("#{@log}.attempts.log").scan('download ').length
  end

  def test_exit_zero_with_an_explicit_download_failure_is_retried
    File.write(@tool, <<~'SH')
      #!/bin/zsh
      attempt=0; [[ ! -f "$COUNT" ]] || attempt=$(<"$COUNT")
      (( attempt++ )); print "$attempt" > "$COUNT"
      if (( attempt < 3 )); then print 'Failed to download Dart SDK' >> "$LOG"; exit 0; fi
      print '{"sdk":"ready"}'
    SH
    out, err, status = run_retry
    assert status.success?, err
    assert_equal '3', File.read(@counter).strip
    assert_equal "{\"sdk\":\"ready\"}\n", out
  end

  def test_single_attempt_timeouts_keep_retrying
    _, err, status = run_retry('FAILURES' => '3', 'FAIL_CODE' => '124')
    assert status.success?, err
    assert_equal '4', File.read(@counter).strip
  end

  def test_explicit_local_failure_and_user_cancellation_are_not_retried
    [ ['1', 'Permission denied'], ['1', 'No space left on device'], ['1', 'The requested URL returned error: 404'], ['1', 'No available formula'], ['1', 'Failed to find package'], ['130', 'cancelled'], ['143', 'terminated'] ].each do |code, message|
      FileUtils.rm_f(@counter)
      _, _, status = run_retry('FAIL_CODE' => code, 'FAIL_TEXT' => message)
      assert_equal code.to_i, status.exitstatus
      assert_equal '1', File.read(@counter).strip
    end
  end

  def test_term_to_parent_stops_a_child_that_ignores_term
    child_file = File.join(@tmp, 'child.pid')
    code = <<~SH
      source #{MODULE.shellescape}
      stubborn() { /bin/zsh -c 'trap "" TERM; print $$ > "$1"; while true; do /bin/sleep 1; done' fixture #{child_file.shellescape}; }
      jobs_sdk_retry SDK #{@log.shellescape} stubborn
    SH
    Open3.popen3(env, '/bin/zsh', '-f', '-c', code) do |input, output, errors, process|
      input.close
      Timeout.timeout(5) { sleep 0.02 until File.exist?(child_file) }
      child = File.read(child_file).to_i
      Process.kill('TERM', process.pid)
      status = Timeout.timeout(5) { process.value }
      assert_equal 143, status.exitstatus, errors.read
      sleep 0.1
      assert_raises(Errno::ESRCH) { Process.kill(0, child) }
      assert_empty output.read
    end
  end

  def test_runner_and_packager_prepare_target_resources_before_business
    [*RUNNERS, 'JobsFlutterPackager/Scripts/PackageFlutter.zsh', 'JobsFlutterTools/Scripts/Tools/PackageFlutter.zsh'].each do |relative|
      FileUtils.rm_f(@counter)
      library = File.read(File.join(ROOT, relative)).sub(/\nmain "\$@"\s*\z/, "\n")
      body = if relative.end_with?('RunFlutterProject.zsh')
        <<~SH
          LOG_FILE=#{@log.shellescape}
          FLUTTER_BIN=#{@tool.shellescape}
          DEVICE_ID=fixture
          json_helper() { print ios; }
          run_bounded() { shift 2; "$@" >> "$LOG_FILE.precache" 2>&1; }
          prepare_target_sdk_resources
        SH
      else
        <<~SH
          FP_LOG_FILE=#{@log.shellescape}
          FP_PLATFORM=android
          FP_FLUTTER=(#{@tool.shellescape})
          prepare_target_sdk_resources() { return 99; }
          fp_prepare_target_sdk_resources
        SH
      end
      out, err, status = Timeout.timeout(10) { Open3.capture3(env, '/bin/zsh', '-f', '-c', library + "\nsetopt PIPE_FAIL\n" + body) }
      assert status.success?, "#{relative}: #{err} #{out}"
      assert_equal '3', File.read(@counter).strip
    end
  end

  def test_fvm_success_without_required_sdk_files_is_retried
    relatives = [*RUNNERS, 'JobsFlutterVersionMgr/Scripts/ManageFlutterVersion.zsh', 'JobsFlutterTools/Scripts/Tools/ManageFlutterVersion.zsh']
    relatives.each do |relative|
      FileUtils.rm_f(@counter)
      artifact = File.join(@tmp, '3.99.1/bin/flutter')
      FileUtils.rm_f(artifact)
      File.write(@tool, <<~'SH')
        #!/bin/zsh
        attempt=0; [[ ! -f "$COUNT" ]] || attempt=$(<"$COUNT")
        (( attempt++ )); print "$attempt" > "$COUNT"
        if (( attempt >= 3 )); then
          /bin/mkdir -p "${ARTIFACT:h}"
          print '#!/bin/zsh' > "$ARTIFACT"
          /bin/chmod +x "$ARTIFACT"
        fi
        exit 0
      SH
      library = File.read(File.join(ROOT, relative)).sub(/\nmain "\$@"\s*\z/, "\n")
      body = <<~SH
        setopt PIPE_FAIL
        LOG_FILE=#{@log.shellescape}
        FM_CACHE_PATH=#{@tmp.shellescape}
        FM_SELECTED=3.99.1
        FM_FVM=#{@tool.shellescape}
        fvm_bin=#{@tool.shellescape}
        version=3.99.1
        cached=#{artifact.shellescape}
        step=fm_install_sdk_once
        [[ #{relative.shellescape} != *RunFlutterProject* ]] || step=install_project_fvm_sdk_once
        jobs_sdk_retry SDK "$LOG_FILE" "$step"
      SH
      out, err, status = Timeout.timeout(12) { Open3.capture3(env('ARTIFACT' => artifact), '/bin/zsh', '-f', '-c', library + body) }
      assert status.success?, "#{relative}: #{err} #{out}"
      assert_equal '3', File.read(@counter).strip
      assert File.executable?(artifact)
    end
  end

  def test_gradle_corrupt_private_archive_is_fetched_again_without_clearing_other_cache
    tool = File.join(@tmp, 'curl')
    archive = File.join(@tmp, 'distribution.part')
    File.write(File.join(@tmp, 'unrelated-cache'), 'preserve')
    File.write(tool, <<~'SH')
      #!/bin/zsh
      attempt=0; [[ ! -f "$COUNT" ]] || attempt=$(<"$COUNT")
      (( attempt++ )); print "$attempt" > "$COUNT"
      while (( $# )); do
        if [[ "$1" == --output ]]; then target="$2"; shift 2; else shift; fi
      done
      if (( attempt < 3 )); then print bad > "$target"; else print good > "$target"; fi
    SH
    File.chmod(0o700, tool)
    source = File.join(ROOT, 'JobsFlutterTools/Scripts/Tools/DownloadProjectGradle.zsh')
    body = <<~SH
      source #{source.shellescape}
      PE_LOG_FILE=#{@log.shellescape}
      DG_CURL=#{tool.shellescape}
      DG_SHA=#{Digest::SHA256.hexdigest("good\n")}
      pe_log() { print -r -- "$*" >> "$PE_LOG_FILE"; }
      pe_run_logged() { "$@" >> "$PE_LOG_FILE" 2>&1; }
      dg_curl_download https://downloads.invalid/distribution.zip #{archive.shellescape} 60
    SH
    out, err, status = Timeout.timeout(12) { Open3.capture3(env, '/bin/zsh', '-f', '-c', body) }
    assert status.success?, err + out
    assert_equal '3', File.read(@counter).strip
    assert_equal "good\n", File.read(archive)
    assert_equal 'preserve', File.read(File.join(@tmp, 'unrelated-cache'))
    assert_equal 2, Dir.glob("#{archive}.rejected.*").length
  end

  def test_cancelled_version_query_never_opens_a_selector_or_mutates_project
    ['JobsFlutterVersionMgr/Scripts/ManageFlutterVersion.zsh', 'JobsFlutterTools/Scripts/Tools/ManageFlutterVersion.zsh'].each do |relative|
      library = File.read(File.join(ROOT, relative)).sub(/\nmain "\$@"\s*\z/, "\n")
      body = <<~'SH'
        for fn in show_script_intro_and_wait fm_initialize_runtime fm_check_project_boundaries fm_prepare_inspection_config fm_check_system_tools fm_ensure_brew fm_ensure_fzf fm_ensure_fvm fm_read_effective_context; do
          functions[$fn]='return 0'
        done
        fm_fetch_versions() { return 130; }
        fm_select_version() { print UNEXPECTED_SELECTOR; }
        fm_confirm_project_change() { print UNEXPECTED_WRITE; }
        fm_prepare_project_config() { print UNEXPECTED_WRITE; }
        fm_apply_and_verify() { print UNEXPECTED_WRITE; }
        main
      SH
      out, err, status = Timeout.timeout(5) { Open3.capture3(env, '/bin/zsh', '-f', '-c', library + body) }
      assert_equal 130, status.exitstatus, err
      refute_includes out, 'UNEXPECTED'
    end
  end

  def test_device_platform_mapping_is_limited_to_the_selected_device
    device_file = File.join(@tmp, 'devices.json')
    helper = File.join(ROOT, 'JobsFlutterTools/Scripts/Tools/FlutterRunner.jxa')
    { 'ios' => 'ios', 'android-arm64' => 'android', 'web-javascript' => 'web', 'darwin' => 'macos', 'ohos-arm64' => 'ohos' }.each do |platform, expected|
      File.write(device_file, '[{"id":"other","targetPlatform":"ios"},{"id":"selected","targetPlatform":"' + platform + '"}]')
      out, err, status = Open3.capture3('/usr/bin/osascript', '-l', 'JavaScript', helper, 'precache-platform', device_file, 'selected')
      assert status.success?, err
      assert_equal expected, out.strip
    end
  end

  def test_runner_bootstrap_retries_and_uses_a_download_sized_window
    RUNNERS.each do |relative|
      FileUtils.rm_f(@counter)
      library = File.read(File.join(ROOT, relative)).sub(/\nmain "\$@"\s*\z/, "\n")
      body = <<~SH
        PROJECT_PATH=#{@tmp.shellescape}
        LOG_FILE=#{@log.shellescape}
        prepare_project_fvm_sdk() { REPLY=#{@tool.shellescape}; }
        : > "$PROJECT_PATH/.fvmrc"
        commands[flutter]=#{@tool.shellescape}
        run_bounded() {
          print -r -- "$1" >> "$LOG_FILE.windows"
          shift 2
          "$@" > "$LOG_FILE.version" 2>&1
        }
        find_flutter
      SH
      out, err, status = Timeout.timeout(10) { Open3.capture3(env, '/bin/zsh', '-f', '-c', library + "\nsetopt PIPE_FAIL\n" + body) }
      assert status.success?, "#{relative}: #{err} #{out}"
      assert_equal '3', File.read(@counter).strip
      assert File.readlines("#{@log}.windows").all? { |line| line.to_i >= 1800 }
      FileUtils.rm_f("#{@log}.windows")
    end
  end
end
