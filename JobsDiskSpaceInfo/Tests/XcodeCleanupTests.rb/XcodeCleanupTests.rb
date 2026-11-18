#!/usr/bin/env ruby
# XcodeCleanupTests.rb | JobsDiskSpaceInfo
# Created by Jobs on 2026年11月15日，星期日.
# 只提取函数块，在临时 HOME 中验证；不运行真实 clean 或真实 simctl。
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'pty'
require 'timeout'

class XcodeCleanupTests < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)
  SCRIPT = File.join(ROOT, 'Scripts/【MacOS】清理磁盘空间.command/【MacOS】清理磁盘空间.command')
  ORIGINAL = File.expand_path('../../../JobsConfigOS/🌍JobsMacEnvVarConfigs/scripts/【MacOS】clean.command/【MacOS】clean.command', ROOT)
  BLOCK_RE = /^# BEGIN JOBS_XCODE_CLEANUP_PHASE\n.*?^# END JOBS_XCODE_CLEANUP_PHASE\n/m

  def setup
    @fixture = File.realpath(Dir.mktmpdir('JobsXcodeCleanupTests-'))
    @home = File.join(@fixture, 'home')
    @work = File.join(@fixture, 'work')
    FileUtils.mkdir_p([@home, @work, File.join(@home, '.Trash')])
    @block = File.read(SCRIPT)[BLOCK_RE]
  end

  def teardown
    FileUtils.remove_entry(@fixture)
  end

  def directory(relative)
    path = File.join(@home, relative)
    FileUtils.mkdir_p(path)
    File.write(File.join(path, 'data'), 'fixture')
    path
  end

  def run_zsh(body, environment = {})
    preamble = <<~'ZSH'
      setopt NO_NOMATCH PIPE_FAIL
      xwork="$JOBS_TEST_WORK"
      xcounter=0
      xsimctl=''
      xrecovery=''
      typeset -A xpaths=() xids=() xgroups=() xkinds=() xrefs=() xsizes=() xlabels=() xselected=()
    ZSH
    harness = File.join(@fixture, 'harness.zsh')
    File.write(harness, @block + preamble + body)
    Open3.capture3({ 'HOME' => @home, 'TMPDIR' => @fixture, 'JOBS_TEST_WORK' => @work }.merge(environment), '/bin/zsh', harness)
  end

  def test_both_inline_blocks_match_and_picker_uses_explicit_keys
    assert @block
    original = File.read(ORIGINAL)
    assert_equal @block, original[BLOCK_RE]
    assert_match(/--bind='up:up,down:down,tab:down,shift-tab:up,enter:toggle,space:accept-non-empty/, @block)
  end

  # 共用相同展示环境，核对独立脚本实际打印完整自述而非仅保留相同函数名。
  def complete_intro(script)
    source = File.read(script)
    raise 'missing main' if script == SCRIPT && !source.sub!(/^main "\$@"\s*\z/, '')
    definitions = File.join(@fixture, 'intro-definitions.zsh')
    File.write(definitions, source)
    harness = <<~'ZSH'
      JOBS_MAC_ENV_SOURCE_MODE=1
      source "$1"
      LOG_FILE="$JOBS_TEST_WORK/intro.log"
      jobs_clean_show_intro
    ZSH
    Open3.capture3({
      'HOME' => @home, 'TMPDIR' => @fixture, 'NO_COLOR' => '1', 'TERM' => 'dumb',
      'JOBS_TEST_WORK' => @work
    }, '/bin/zsh', '-c', harness, '--', definitions)
  end

  def test_complete_intro_is_identical_and_read_only_for_both_mac_entries
    outputs = [SCRIPT, ORIGINAL].map do |script|
      out, err, status = complete_intro(script)
      assert status.success?, "#{script}\n#{out}#{err}"
      %w[功能： 说明： Spotlight LaunchServices Homebrew Runtime].each do |content|
        assert_includes out, content, script
      end
      assert_includes out, 'Xcode 最终范围回车确认', script
      assert_includes out, '不自动提权', script
      assert_includes out, '日志', script
      refute File.exist?(File.join(@work, 'intro.log')), '展示自述不得提前建立业务日志'
      out
    end
    assert_equal outputs.first, outputs.last
  end

  # 保留两入口真实自述及读取，只替换已确认后的准备和清理动作。
  def run_intro_entrypoint(script, answer, extra_environment = {})
    source = File.read(script)
    raise 'missing main' if script == SCRIPT && !source.sub!(/^main "\$@"\s*\z/, '')
    definitions = File.join(@fixture, 'intro-entrypoint-definitions.zsh')
    File.write(definitions, source)
    harness = <<~'ZSH'
      JOBS_MAC_ENV_SOURCE_MODE=1
      source "$1"
      LOG_FILE="$JOBS_TEST_WORK/intro.log"
      clear() { return 0; }
      jobs_clean_xcode_stage() { return 0; }
      jobs_clean_prepare_runtime() { print INTRO_TEST_PREPARED; }
      clean() { print INTRO_TEST_CLEANED; }
      main
    ZSH
    transcript = +''
    result = nil
    environment = {
      'HOME' => @home, 'TMPDIR' => @fixture, 'NO_COLOR' => '1', 'TERM' => 'dumb',
      'JOBS_TEST_WORK' => @work
    }
    PTY.spawn(environment.merge(extra_environment), '/bin/zsh', '-c', harness, '--', definitions) do |reader, writer, pid|
      writer.write(answer.nil? ? "\u0004" : answer + "\n")
      writer.flush
      begin
        Timeout.timeout(5) { loop { transcript << reader.readpartial(8192) } }
      rescue EOFError, Errno::EIO
        # 真实确认结束后仅由命令替身输出执行标记。
      rescue Timeout::Error
        Process.kill('TERM', pid) rescue nil
        flunk '完整自述确认验证超时'
      ensure
        _, result = Process.wait2(pid)
      end
    end
    [transcript.force_encoding(Encoding::UTF_8), result]
  end

  def test_both_entrypoints_show_complete_intro_before_their_own_confirmation
    [[SCRIPT, ''], [ORIGINAL, '']].each do |script, answer|
      transcript, result = run_intro_entrypoint(script, answer)
      assert transcript.valid_encoding?, '自述输出必须保持 UTF-8'
      assert result.success?, "#{script}\n#{transcript}"
      assert_includes transcript, '功能：', script
      assert_includes transcript, '说明：', script
      assert_includes transcript, '不自动提权', script
      assert_equal 1, transcript.scan('INTRO_TEST_PREPARED').length
      assert_equal 1, transcript.scan('INTRO_TEST_CLEANED').length
      assert_operator transcript.index('说明：'), :<, transcript.index('INTRO_TEST_PREPARED')
    end
  end

  def test_nonempty_or_eof_confirmation_cancels_regular_cleanup_in_both_entries
    [SCRIPT, ORIGINAL].each do |script|
      ['YES', 'CANCEL', ' ', nil].each do |answer|
        transcript, result = run_intro_entrypoint(script, answer)
        refute result.success?, transcript
        assert_includes transcript, '功能：'
        assert_includes transcript, '说明：'
        refute_includes transcript, 'INTRO_TEST_PREPARED'
        refute_includes transcript, 'INTRO_TEST_CLEANED'
      end
    end
  end

  def test_list_parent_preserves_return_and_cancel_without_accepting_nonempty_input
    [["\e[D", 20], ["\e", 130], ['YES', 130], [' ', 130], ['', 0], [nil, 130]].each do |answer, expected|
      transcript, result = run_intro_entrypoint(ORIGINAL, answer, 'JOBS_LIST_PARENT_MENU' => 'list')
      assert_equal expected, result.exitstatus, transcript
      assert_equal expected.zero?, transcript.include?('INTRO_TEST_PREPARED'), transcript
      assert_equal expected.zero?, transcript.include?('INTRO_TEST_CLEANED'), transcript
    end
  end

  # 加载真实入口与阶段编排，只把实际清理和确认依赖替换为可核对记录。
  def run_entrypoint(script, entrypoint, overrides = '', environment = {}, stdin_data = '')
    source = File.read(script)
    if script == SCRIPT
      raise 'missing main' unless source.sub!(/^main "\$@"\s*\z/, '')
    end
    source = source.gsub('/usr/bin/xcrun --find simctl', 'false')
    source = source.gsub('/usr/bin/pgrep -x Xcode', 'jobs_test_xcode_busy')
                   .gsub('/usr/bin/pgrep -x xcodebuild', 'jobs_test_xcode_busy')
    definitions = File.join(@fixture, 'entrypoint-definitions.zsh')
    File.write(definitions, source)
    harness = <<~'ZSH'
      JOBS_MAC_ENV_SOURCE_MODE=1
      source "$1"
      LOG_FILE="$JOBS_TEST_WORK/flow.log"
      : > "$LOG_FILE"
      functions -c jobs_clean_xcode_stage jobs_test_actual_xcode_stage
      functions -c clean jobs_test_actual_clean
      jobs_test_xcode_busy() { return 1; }
      jobs_clean_xcode_stage() {
        print -r -- xcode >> "$JOBS_TEST_WORK/calls"
        return "$JOBS_TEST_XCODE_CODE"
      }
      show_script_intro_and_wait() {
        print -r -- intro >> "$JOBS_TEST_WORK/calls"
        return "$JOBS_TEST_INTRO_CODE"
      }
      jobs_clean_prepare_runtime() {
        print -r -- prepare >> "$JOBS_TEST_WORK/calls"
        return "$JOBS_TEST_PREPARE_CODE"
      }
      clean() {
        print -r -- clean >> "$JOBS_TEST_WORK/calls"
        return "$JOBS_TEST_REGULAR_CODE"
      }
    ZSH
    environment = {
      'HOME' => @home, 'TMPDIR' => @fixture, 'NO_COLOR' => '1', 'TERM' => 'dumb',
      'JOBS_TEST_WORK' => @work, 'JOBS_TEST_XCODE_CODE' => '0',
      'JOBS_TEST_INTRO_CODE' => '0', 'JOBS_TEST_PREPARE_CODE' => '0',
      'JOBS_TEST_REGULAR_CODE' => '0'
    }.merge(environment)
    Open3.capture3(environment, '/bin/zsh', '-c', harness + overrides + "\n#{entrypoint}\n", '--', definitions, stdin_data: stdin_data)
  end

  # 两种独立入口和终端 source 入口共用同一组行为断言。
  def entrypoint_cases
    [[SCRIPT, 'main'], [ORIGINAL, 'main'], [ORIGINAL, 'jobs_clean_main']]
  end

  # 每次场景保留准确顺序，确保清理阶段只执行一次。
  def flow_calls
    path = File.join(@work, 'calls')
    File.exist?(path) ? File.readlines(path, chomp: true) : []
  end

  def test_xcode_failure_continues_regular_cleanup_and_keeps_final_failure
    entrypoint_cases.each do |script, entrypoint|
      [0, 1, 23].each do |xcode_code|
        FileUtils.rm_f(File.join(@work, 'calls'))
        out, err, status = run_entrypoint(script, entrypoint, '', 'JOBS_TEST_XCODE_CODE' => xcode_code.to_s)
        assert_equal xcode_code.zero?, status.success?, "#{script}:#{entrypoint} (#{xcode_code})\n#{out}#{err}"
        assert_equal %w[xcode intro prepare clean], flow_calls
      end
    end
  end

  def test_cancelled_xcode_stage_never_reaches_regular_confirmation_or_cleanup
    entrypoint_cases.each do |script, entrypoint|
      [129, 130, 143].each do |xcode_code|
        FileUtils.rm_f(File.join(@work, 'calls'))
        out, err, status = run_entrypoint(script, entrypoint, '', 'JOBS_TEST_XCODE_CODE' => xcode_code.to_s)
        assert_equal xcode_code, status.exitstatus, "#{script}:#{entrypoint}\n#{out}#{err}"
        assert_equal ['xcode'], flow_calls
      end
    end
  end

  def test_regular_confirmation_and_preparation_failures_stop_before_cleanup
    entrypoint_cases.each do |script, entrypoint|
      [['JOBS_TEST_INTRO_CODE', %w[xcode intro]], ['JOBS_TEST_PREPARE_CODE', %w[xcode intro prepare]]].each do |variable, expected|
        FileUtils.rm_f(File.join(@work, 'calls'))
        out, err, status = run_entrypoint(script, entrypoint, '', variable => '130')
        assert_equal 130, status.exitstatus, "#{script}:#{entrypoint}\n#{out}#{err}"
        assert_equal expected, flow_calls
      end
    end
  end

  def test_regular_failure_and_cancel_are_not_hidden_by_xcode_status
    entrypoint_cases.each do |script, entrypoint|
      [0, 1].each do |xcode_code|
        [1, 129, 130, 143].each do |regular_code|
          FileUtils.rm_f(File.join(@work, 'calls'))
          out, err, status = run_entrypoint(script, entrypoint, '', {
            'JOBS_TEST_XCODE_CODE' => xcode_code.to_s, 'JOBS_TEST_REGULAR_CODE' => regular_code.to_s
          })
          refute status.success?, "#{script}:#{entrypoint}\n#{out}#{err}"
          assert_equal regular_code, status.exitstatus, out + err if [129, 130, 143].include?(regular_code)
          assert_equal %w[xcode intro prepare clean], flow_calls
        end
      end
    end
  end

  def test_repeated_source_entry_resets_previous_xcode_failure
    out, err, status = run_entrypoint(ORIGINAL, 'jobs_clean_main', <<~'ZSH')
      JOBS_TEST_XCODE_CODE=1
      jobs_clean_main
      first_code=$?
      (( first_code != 0 )) || exit 80
      JOBS_TEST_XCODE_CODE=0
    ZSH
    assert status.success?, out + err
    assert_equal %w[xcode intro prepare clean xcode intro prepare clean], flow_calls
  end

  # 保留真实阶段和 builtin read，仅替换候选扫描、进程查询与删除动作。
  def selected_stage_overrides
    <<~'ZSH'
      functions -c jobs_test_actual_xcode_stage jobs_clean_xcode_stage
      fzf() { return 0; }
      jobs_xcode_interactive() { return 0; }
      jobs_xcode_scan() {
        print -r -- scan >> "$JOBS_TEST_WORK/calls"
        xpaths[1]="$HOME/Library/Developer/Xcode/DerivedData/fixture"
        xgroups[1]=DerivedData
        xsizes[1]=1
        xlabels[1]=fixture
        xkinds[1]=directory
      }
      jobs_xcode_pick_group() { xselected[1]=1; return 0; }
      jobs_xcode_execute_path() {
        print -r -- xcode-delete >> "$JOBS_TEST_WORK/calls"
        return 0
      }
    ZSH
  end

  def test_final_return_executes_xcode_and_nonempty_input_skips_only_xcode
    entrypoint_cases.each do |script, entrypoint|
      ['', 'skip', 'YES', ' '].each do |answer|
        FileUtils.rm_f(File.join(@work, 'calls'))
        out, err, status = run_entrypoint(script, entrypoint, selected_stage_overrides, {}, "\n#{answer}\n")
        assert status.success?, "#{script}:#{entrypoint} #{answer.inspect}\n#{out}#{err}"
        expected = answer.empty? ? %w[scan xcode-delete intro prepare clean] : %w[scan intro prepare clean]
        assert_equal expected, flow_calls
      end
    end
  end

  def test_final_eof_cancels_whole_run_without_any_cleanup
    entrypoint_cases.each do |script, entrypoint|
      FileUtils.rm_f(File.join(@work, 'calls'))
      out, err, status = run_entrypoint(script, entrypoint, selected_stage_overrides, {}, "\n")
      assert_equal 130, status.exitstatus, "#{script}:#{entrypoint}\n#{out}#{err}"
      assert_equal ['scan'], flow_calls
    end
  end

  def test_active_xcode_guard_still_preserves_candidates_and_starts_regular_stage
    entrypoint_cases.each do |script, entrypoint|
      FileUtils.rm_f(File.join(@work, 'calls'))
      overrides = selected_stage_overrides + "\njobs_test_xcode_busy() { return 0; }\n"
      out, err, status = run_entrypoint(script, entrypoint, overrides, {}, "\n\n")
      refute status.success?, "#{script}:#{entrypoint}\n#{out}#{err}"
      assert_equal %w[scan intro prepare clean], flow_calls
      assert_includes out + err, 'Xcode 或 xcodebuild 仍在运行'
    end
  end

  def test_initial_stage_skip_does_not_scan_and_still_starts_regular_stage
    entrypoint_cases.each do |script, entrypoint|
      FileUtils.rm_f(File.join(@work, 'calls'))
      out, err, status = run_entrypoint(script, entrypoint, selected_stage_overrides, {}, "skip\n")
      assert status.success?, "#{script}:#{entrypoint}\n#{out}#{err}"
      assert_equal %w[intro prepare clean], flow_calls
    end
  end

  def test_successful_regular_cleanup_keeps_xcode_failure_visible_without_clearing_screen
    entrypoint_cases.each do |script, entrypoint|
      FileUtils.rm_f(File.join(@work, 'calls'))
      overrides = <<~'ZSH'
        functions -c jobs_test_actual_clean clean
        show_script_intro_and_wait() { JOBS_CLEAN_CONFIRMED=1; return 0; }
        for step in jobs_disk_clean_history jobs_clean_move_indexed_build_apps_to_trash jobs_clean_orphaned_simulators jobs_clean_unregister_non_macos_development_apps jobs_clean_refresh_application_lists jobs_clean_homebrew_cleanup jobs_clean_user_caches; do
          functions[$step]='print -r -- "${funcstack[1]}" >> "$JOBS_TEST_WORK/calls"; return 0'
        done
      ZSH
      out, err, status = run_entrypoint(script, entrypoint, overrides, 'JOBS_TEST_XCODE_CODE' => '1')
      refute status.success?, "#{script}:#{entrypoint}\n#{out}#{err}"
      assert_equal 9, flow_calls.length
      assert_equal %w[xcode prepare], flow_calls.first(2)
      refute_includes out + err, "\e[2J"
      refute_includes out + err, 'ClearScrollback'
      assert_includes File.read(File.join(@work, 'flow.log')), 'Xcode'
    end
  end

  def test_regular_terminal_intro_keeps_prior_xcode_failure_on_screen
    [0, 1].each do |xcode_code|
      transcript = +''
      result = nil
      harness = <<~'ZSH'
        JOBS_MAC_ENV_SOURCE_MODE=1
        source "$1"
        JOBS_CLEAN_XCODE_RESULT="$JOBS_TEST_XCODE_CODE"
        clear() { print CLEAR_CALLED; return 0; }
        jobs_list_intro_read() { return 0; }
        print XCODE_ERROR_SENTINEL
        show_script_intro_and_wait
        exit $?
      ZSH
      environment = {
        'HOME' => @home, 'TMPDIR' => @fixture, 'NO_COLOR' => '1', 'TERM' => 'dumb',
        'JOBS_TEST_XCODE_CODE' => xcode_code.to_s
      }
      PTY.spawn(environment, '/bin/zsh', '-c', harness, '--', ORIGINAL) do |reader, _writer, pid|
        begin
          Timeout.timeout(5) { loop { transcript << reader.readpartial(8192) } }
        rescue EOFError, Errno::EIO
          # 隔离终端在真实自述完成后关闭。
        rescue Timeout::Error
          Process.kill('TERM', pid) rescue nil
          flunk '常规自述验证超时'
        ensure
          _, result = Process.wait2(pid)
        end
      end
      assert result.success?, transcript
      assert_includes transcript, 'XCODE_ERROR_SENTINEL'
      assert_equal xcode_code.zero?, transcript.include?('CLEAR_CALLED'), transcript
    end
  end

  def test_skip_and_eof_never_reach_scan_or_write
    [ ['skip', 0], ['eof', 130] ].each do |mode, expected|
      out, err, status = run_zsh(<<~'ZSH', 'JOBS_TEST_MODE' => mode)
        jobs_xcode_interactive() { return 0; }
        jobs_xcode_read() {
          [[ "$JOBS_TEST_MODE" != eof ]] || return 1
          REPLY=skip
        }
        jobs_xcode_scan() { print scan > "$JOBS_TEST_WORK/forbidden"; return 0; }
        jobs_clean_xcode_stage
        exit $?
      ZSH
      assert_equal expected, status.exitstatus, out + err
      refute File.exist?(File.join(@work, 'forbidden'))
      assert_empty Dir.glob(File.join(@fixture, 'JobsXcodeCleanup.*'))
    end
  end

  def test_exact_six_roots_without_unrelated_caches_or_runtime
    directory('Library/Developer/Xcode/iOS DeviceSupport/18.0')
    directory('Library/Developer/Xcode/DerivedData/Project-abc')
    directory('Library/Developer/Xcode/Archives/2026-01-01/App.xcarchive')
    directory('Library/Developer/CoreSimulator/Caches/dyld/arm64/runtime-hash')
    directory('Library/Caches/com.apple.dt.Xcode')
    directory('Library/Developer/CoreSimulator/Profiles/Runtimes/iOS.simruntime')
    out, err, status = run_zsh(<<~'ZSH')
      jobs_xcode_scan || exit $?
      (( xcounter == 4 )) || exit 80
      for index in ${(on)${(k)xpaths}}; do print -r -- "${xgroups[$index]}|${xpaths[$index]}"; done
    ZSH
    assert status.success?, out + err
    %w[Device\ Support DerivedData Archives Caches].each { |name| assert_includes out, name }
    refute_includes out, 'Library/Caches'
    refute_includes out, '.simruntime'
  end

  def test_parent_symlink_and_nested_change_are_preserved
    target = directory('Library/Developer/Xcode/DerivedData/Project-abc')
    outside = File.join(@fixture, 'outside')
    FileUtils.mkdir_p(outside)
    File.symlink(outside, File.join(@home, 'link'))
    out, err, status = run_zsh(<<~'ZSH', 'JOBS_TEST_TARGET' => target)
      jobs_xcode_safe_path "$HOME/link/folder" && exit 81
      jobs_xcode_add DerivedData directory "$JOBS_TEST_TARGET" || exit $?
      print changed > "$JOBS_TEST_TARGET/data"
      jobs_xcode_execute_path 1 && exit 82
      [[ -d "$JOBS_TEST_TARGET" ]] || exit 83
    ZSH
    assert status.success?, out + err
    assert_equal "changed\n", File.read(File.join(target, 'data'))
  end

  def test_selected_directory_is_deleted_and_archives_are_recoverable
    derived = directory('Library/Developer/Xcode/DerivedData/Project-abc')
    archive = directory('Library/Developer/Xcode/Archives/2026-01-01/App.xcarchive')
    out, err, status = run_zsh(<<~'ZSH', 'JOBS_TEST_DERIVED' => derived, 'JOBS_TEST_ARCHIVE' => archive)
      jobs_xcode_add DerivedData directory "$JOBS_TEST_DERIVED" || exit $?
      jobs_xcode_add Archives archive "$JOBS_TEST_ARCHIVE" || exit $?
      jobs_xcode_execute_path 1 || exit $?
      jobs_xcode_execute_path 2 || exit $?
      [[ -f "$xrecovery/2-App.xcarchive/data" ]] || exit 84
    ZSH
    assert status.success?, out + err
    refute File.exist?(derived)
    refute File.exist?(archive)
    assert_equal 1, Dir.glob(File.join(@home, '.Trash/JobsXcodeClean-Archives.*/2-App.xcarchive/data')).size
  end

  def test_unwritable_or_linked_archive_recovery_does_not_delete_source
    archive = directory('Library/Developer/Xcode/Archives/2026-01-01/App.xcarchive')
    FileUtils.remove_entry(File.join(@home, '.Trash'))
    File.symlink(@work, File.join(@home, '.Trash'))
    out, err, status = run_zsh(<<~'ZSH', 'JOBS_TEST_ARCHIVE' => archive)
      jobs_xcode_add Archives archive "$JOBS_TEST_ARCHIVE" || exit $?
      jobs_xcode_execute_path 1 && exit 85
      [[ -f "$JOBS_TEST_ARCHIVE/data" ]] || exit 86
    ZSH
    assert status.success?, out + err
    assert File.exist?(File.join(archive, 'data'))
  end

  def test_change_after_staging_is_restored_without_deleting_new_data
    target = directory('Library/Developer/Xcode/DerivedData/Project-abc')
    out, err, status = run_zsh(<<~'ZSH', 'JOBS_TEST_TARGET' => target)
      jobs_xcode_add DerivedData directory "$JOBS_TEST_TARGET" || exit $?
      functions[jobs_test_manifest]="${functions[jobs_xcode_manifest]}"
      jobs_xcode_manifest() {
        [[ "$1" != */payload ]] || print late-change > "$1/data"
        jobs_test_manifest "$@"
      }
      jobs_xcode_execute_path 1 && exit 87
      [[ -f "$JOBS_TEST_TARGET/data" ]] || exit 88
    ZSH
    assert status.success?, out + err
    assert_equal "late-change\n", File.read(File.join(target, 'data'))
  end

  def test_simulator_shutdown_and_delete_are_limited_to_selected_uuid
    uuid = '11111111-2222-3333-4444-555555555555'
    path = directory("Library/Developer/CoreSimulator/Devices/#{uuid}")
    out, err, status = run_zsh(<<~'ZSH', 'JOBS_TEST_TARGET' => path, 'JOBS_TEST_UUID' => uuid)
      jobs_xcode_add Simulators simulator "$JOBS_TEST_TARGET" "$JOBS_TEST_UUID" fixture || exit $?
      JOBS_TEST_DEVICE_STATE=Booted
      jobs_xcode_simctl() {
        local set_path="$1" action="$2"
        shift 2
        case "$action" in
          list) print '{}';;
          shutdown)
            [[ "$1" == "$JOBS_TEST_UUID" && $# == 1 ]] || return 90
            JOBS_TEST_DEVICE_STATE=Shutdown
            print -r -- "shutdown:$1" >> "$JOBS_TEST_WORK/calls";;
          delete)
            [[ "$1" == "$JOBS_TEST_UUID" && $# == 1 && "$JOBS_TEST_DEVICE_STATE" == Shutdown ]] || return 91
            JOBS_TEST_DEVICE_STATE=Deleted
            print -r -- "delete:$1" >> "$JOBS_TEST_WORK/calls";;
          *) return 92;;
        esac
      }
      jobs_xcode_device_rows() {
        [[ "$JOBS_TEST_DEVICE_STATE" == Deleted ]] || print -r -- "$JOBS_TEST_UUID"$'\t'"$JOBS_TEST_DEVICE_STATE"$'\tfixture'
      }
      jobs_xcode_execute_simulator 1 || exit $?
    ZSH
    assert status.success?, out + err
    assert_equal ["shutdown:#{uuid}", "delete:#{uuid}"], File.readlines(File.join(@work, 'calls'), chomp: true)
  end

  def test_missing_orphan_is_filtered_to_selected_uuid_and_recreated_directory_is_preserved
    set_path = File.join(@home, 'Library/Developer/CoreSimulator/Devices')
    FileUtils.mkdir_p(set_path)
    uuid = '11111111-2222-3333-4444-555555555555'
    other = 'AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE'
    out, err, status = run_zsh(<<~'ZSH', 'JOBS_TEST_SET' => set_path, 'JOBS_TEST_UUID' => uuid, 'JOBS_TEST_OTHER' => other)
      jobs_xcode_add_missing_device Simulators "$JOBS_TEST_SET" "$JOBS_TEST_UUID" fixture || exit $?
      jobs_clean_simulator_missing() { return 0; }
      jobs_clean_simctl() { return 0; }
      jobs_clean_simulator_rows() {
        print -r -- "$JOBS_TEST_UUID"$'\tShutdown'
        print -r -- "$JOBS_TEST_OTHER"$'\tShutdown'
      }
      functions[jobs_xcode_device_rows]="${functions[jobs_clean_simulator_rows]}"
      jobs_clean_orphaned_simulators() {
        jobs_clean_simulator_rows > "$JOBS_TEST_WORK/orphan-filtered"
        [[ "$JOBS_CLEAN_CONFIRMED" == 1 ]] || return 93
      }
      jobs_xcode_execute_orphan 1 || exit $?
      /bin/mkdir "$JOBS_TEST_SET/$JOBS_TEST_UUID" || exit $?
      jobs_xcode_execute_orphan 1 && exit 94
      [[ -d "$JOBS_TEST_SET/$JOBS_TEST_UUID" ]] || exit 95
    ZSH
    assert status.success?, out + err
    assert_equal ["#{uuid}\tShutdown"], File.readlines(File.join(@work, 'orphan-filtered'), chomp: true)
    refute_includes File.read(File.join(@work, 'orphan-filtered')), other
  end

  def test_device_parser_accepts_other_platforms_but_rejects_foreign_data_paths
    uuid = '11111111-2222-3333-4444-555555555555'
    set_path = File.join(@home, 'Library/Developer/CoreSimulator/Devices')
    payload = { devices: { 'com.apple.CoreSimulator.SimRuntime.watchOS-27-0' => [
      { udid: uuid, name: 'Apple Watch', state: 'Shutdown', dataPath: "#{set_path}/#{uuid}/data" }
    ] } }
    require 'json'
    json_path = File.join(@work, 'device.json')
    File.write(json_path, JSON.generate(payload))
    out, err, status = run_zsh('jobs_xcode_device_rows "$JOBS_TEST_JSON" "$JOBS_TEST_SET"', 'JOBS_TEST_JSON' => json_path, 'JOBS_TEST_SET' => set_path)
    assert status.success?, out + err
    assert_includes out, uuid
    payload[:devices].values.first.first[:dataPath] = '/external/data'
    File.write(json_path, JSON.generate(payload))
    _, _, status = run_zsh('jobs_xcode_device_rows "$JOBS_TEST_JSON" "$JOBS_TEST_SET"', 'JOBS_TEST_JSON' => json_path, 'JOBS_TEST_SET' => set_path)
    refute status.success?
  end

  def test_skipping_one_group_does_not_select_it
    target = directory('Library/Developer/Xcode/DerivedData/Project-abc')
    picker = File.join(@fixture, 'pick-skip')
    File.write(picker, "#!/bin/zsh\nprint -r -- $'SKIP\\t跳过当前组'\n")
    FileUtils.chmod(0700, picker)
    out, err, status = run_zsh(<<~'ZSH', 'JOBS_TEST_TARGET' => target, 'JOBS_TEST_PICKER' => picker)
      jobs_xcode_add DerivedData directory "$JOBS_TEST_TARGET" || exit $?
      xfzf="$JOBS_TEST_PICKER"
      jobs_xcode_pick_group DerivedData || exit $?
      (( ${#xselected} == 0 )) || exit 99
    ZSH
    assert status.success?, out + err
    assert File.exist?(File.join(target, 'data'))
  end

  def test_managed_paths_are_protected_from_legacy_broad_cleaning
    out, err, status = run_zsh(<<~'ZSH')
      jobs_xcode_managed_path "$HOME/Library/Developer/Xcode/DerivedData/project/Build/Products/Debug-iphonesimulator/App.app" || exit 96
      jobs_xcode_managed_path "$HOME/Library/Developer/CoreSimulator/Devices/UUID/data/Containers/Bundle/Application/ID/App.app" || exit 97
      jobs_xcode_managed_path "$HOME/Documents/project/build/Debug-iphoneos/App.app" && exit 98
      exit 0
    ZSH
    assert status.success?, out + err
  end

  def test_fzf_default_all_and_environment_are_isolated_and_final_skip_deletes_nothing
    target = directory('Library/Developer/Xcode/DerivedData/Project-abc')
    bin = File.join(@fixture, 'bin')
    FileUtils.mkdir_p(bin)
    picker = File.join(bin, 'fzf')
    File.write(picker, <<~'ZSH')
      #!/bin/zsh
      [[ "$1" != --version ]] || { print 0.60; exit 0; }
      [[ -z "$FZF_DEFAULT_OPTS" && -z "$FZF_DEFAULT_OPTS_FILE" ]] || exit 91
      IFS= read -r first || exit 92
      [[ "$first" == ALL$'\t'* ]] || exit 93
      print -r -- "$first"
    ZSH
    FileUtils.chmod(0700, picker)
    out, err, status = run_zsh(<<~'ZSH', 'PATH' => bin + ':' + ENV.fetch('PATH'), 'FZF_DEFAULT_OPTS' => '--filter=unsafe', 'FZF_DEFAULT_OPTS_FILE' => '/does/not/exist')
      jobs_xcode_interactive() { return 0; }
      JOBS_TEST_READ_COUNT=0
      jobs_xcode_read() {
        (( JOBS_TEST_READ_COUNT += 1 ))
        if (( JOBS_TEST_READ_COUNT == 1 )); then REPLY=''; else REPLY=cancel; fi
      }
      jobs_clean_xcode_stage
      exit $?
    ZSH
    assert_equal 0, status.exitstatus, out + err
    assert File.exist?(File.join(target, 'data'))
    assert_includes out, 'DerivedData'
  end

  def test_real_fzf_tab_moves_enter_selects_and_space_confirms
    fzf = ENV.fetch('PATH').split(File::PATH_SEPARATOR).map { |dir| File.join(dir, 'fzf') }.find { |path| File.executable?(path) && File.file?(path) }
    skip 'fzf 未安装；其它测试仍验证隔离与默认行契约' unless fzf
    first = directory('Library/Developer/Xcode/DerivedData/Project-first')
    second = directory('Library/Developer/Xcode/DerivedData/Project-second')
    harness = File.join(@fixture, 'real-fzf.zsh')
    File.write(harness, @block + <<~'ZSH')
      stty rows 25 columns 110
      xwork="$JOBS_TEST_WORK"
      xcounter=0
      typeset -A xpaths=() xids=() xgroups=() xkinds=() xrefs=() xsizes=() xlabels=() xselected=()
      xfzf="$JOBS_TEST_FZF"
      jobs_xcode_add DerivedData directory "$JOBS_TEST_FIRST" || exit $?
      jobs_xcode_add DerivedData directory "$JOBS_TEST_SECOND" || exit $?
      jobs_xcode_pick_group DerivedData || exit $?
      typeset -a selected_ids=(${(on)${(k)xselected}})
      print -r -- "RESULT:${#xselected}:${(j:,:)selected_ids}"
    ZSH
    environment = {
      'HOME' => @home, 'TMPDIR' => @fixture, 'TERM' => 'xterm-256color',
      'JOBS_TEST_WORK' => @work, 'JOBS_TEST_FZF' => fzf,
      'JOBS_TEST_FIRST' => first, 'JOBS_TEST_SECOND' => second,
      'FZF_DEFAULT_OPTS' => '--filter=unsafe', 'FZF_DEFAULT_OPTS_FILE' => '/does/not/exist'
    }
    {
      ' ' => [0, 'RESULT:2:1,2'],
      "\t " => [0, 'RESULT:1:1'],
      "\t\r " => [0, 'RESULT:1:1'],
      "\t\r\t " => [0, 'RESULT:1:1'],
      "\t\r\r " => [0, 'RESULT:1:1'],
      "\t\r\t\r " => [0, 'RESULT:2:1,2'],
      "\t\t\t " => [0, 'RESULT:0:'],
      "\e" => [130, nil]
    }.each do |keys, expected|
      output = +''
      result = nil
      PTY.spawn(environment, '/bin/zsh', harness) do |reader, writer, pid|
        begin
          Timeout.timeout(8) do
            sent_keys = false
            loop do
              output << reader.readpartial(8192)
              # 等真实候选完整绘制后发键，避免初始化期间吞掉 Tab 而误选 ALL。
              next if sent_keys || !output.include?('Project-second') || !output.include?('4/4 (0)')
              writer.write(keys)
              writer.flush
              sent_keys = true
            end
          end
        rescue Errno::EIO, EOFError
          # PTY closes when the isolated picker exits.
        rescue Timeout::Error
          Process.kill('TERM', pid) rescue nil
          flunk 'fzf 按键验证超时'
        ensure
          _, result = Process.wait2(pid) rescue nil
        end
      end
      assert_equal expected[0], result.exitstatus, output
      assert_includes output, expected[1] if expected[1]
    end
    assert File.exist?(File.join(first, 'data'))
    assert File.exist?(File.join(second, 'data'))
  end
end
