# frozen_string_literal: true
# Jobs：隔离 HOME、命令替身与临时文件验证门禁和边界，不运行真实 clean。
require 'minitest/autorun'
require 'open3'
require 'tmpdir'
require 'fileutils'
require 'pty'
require 'timeout'

class DiskCleanupTests < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)
  SCRIPT = ENV.fetch('JOBS_CLEAN_TEST_SCRIPT', File.join(ROOT, 'Scripts/【MacOS】清理磁盘空间.command/【MacOS】清理磁盘空间.command'))

  def fixture
    Dir.mktmpdir('jobs-disk-clean-fixture-') do |directory|
      directory = File.realpath(directory)
      home = File.join(directory, '用户 home')
      temp = File.join(directory, '临时 tmp')
      FileUtils.mkdir_p([home, temp, File.join(home, '.Trash')])
      source = File.read(SCRIPT)
      raise 'missing main' unless source.sub!(/^(?:main|initialize_script_module) "\$@"\s*\z/, '')
      definitions = File.join(directory, 'definitions.zsh')
      File.write(definitions, source)
      yield directory, home, temp, definitions
    end
  end

  def run_fixture(home, temp, definitions, code)
    stub = <<~'ZSH'
      source "$1"
      JOBS_CLEAN_CONFIRMED=1
      jobs_clean_cache_select_candidates() { /usr/bin/awk -F '\t' '$1 ~ /^[0-9]+$/ { print $1 }' "$1"; }
      jobs_clean_cache_confirm_selected() { return 0; }
      LOG_FILE="$TMPDIR/fixture.log"
      : > "$LOG_FILE"
      log() { print -r -- "$1" >> "$LOG_FILE"; }
    ZSH
    Open3.capture3({ 'HOME' => home, 'TMPDIR' => temp, 'NO_COLOR' => '1', 'PLAIN_OUTPUT' => '1' }, '/bin/zsh', '-c', stub + code, '--', definitions)
  end

  # 保留真实初始化，只在私有 HOME 和临时目录中创建本轮日志与锁。
  def run_runtime_fixture(home, temp, definitions, code)
    Open3.capture3({ 'HOME' => home, 'TMPDIR' => temp, 'NO_COLOR' => '1', 'PLAIN_OUTPUT' => '1' },
                   '/bin/zsh', '-c', "source \"$1\"\n" + code, '--', definitions)
  end

  def test_runtime_without_confirmation_creates_no_log_or_lock
    fixture do |_directory, home, temp, definitions|
      output, errors, status = run_runtime_fixture(home, temp, definitions, 'jobs_clean_prepare_runtime')
      assert_equal 1, status.exitstatus, output + errors
      assert_empty Dir.children(temp)
    end
  end

  def test_runtime_logs_are_private_unique_and_preserve_literal_files_and_links
    [:file, :link].each do |existing_kind|
      fixture do |directory, home, temp, definitions|
        target = File.join(directory, 'old-log-target')
        literal = File.join(temp, 'JobsDiskSpaceCleanup.XXXXXXXX.log')
        File.write(target, 'old-log-sentinel')
        existing_kind == :link ? File.symlink(target, literal) : File.write(literal, 'old-log-sentinel')
        File.write(File.join(temp, 'JobsDiskSpaceCleanup.XXXXXXXX'), 'template-sentinel')
        paths = 2.times.map do |index|
          output, errors, status = run_runtime_fixture(home, temp, definitions, <<~ZSH)
            umask 000
            JOBS_CLEAN_CONFIRMED=1
            jobs_clean_prepare_runtime || exit $?
            print -r -- 'run-#{index}' >> "$LOG_FILE"
            print -r -- "JOBS_TEST_LOG=$LOG_FILE"
          ZSH
          assert status.success?, output + errors
          path = output.lines.find { |line| line.start_with?('JOBS_TEST_LOG=') }.to_s.chomp.delete_prefix('JOBS_TEST_LOG=')
          assert File.file?(path), output + errors
          assert_equal 0o600, File.stat(path).mode & 0o777
          assert_equal "run-#{index}\n", File.read(path)
          refute File.exist?(File.join(temp, "JobsDiskSpaceCleanup-#{Process.uid}.lock"))
          path
        end
        assert_equal 2, paths.uniq.length
        assert_equal 'old-log-sentinel', File.read(target)
        assert_equal 'old-log-sentinel', File.read(literal)
        assert_equal(existing_kind == :link, File.symlink?(literal))
        assert_equal 'template-sentinel', File.read(File.join(temp, 'JobsDiskSpaceCleanup.XXXXXXXX'))
      end
    end
  end

  def test_runtime_concurrent_attempts_create_independent_private_logs
    fixture do |_directory, home, temp, definitions|
      environment = { 'HOME' => home, 'TMPDIR' => temp, 'NO_COLOR' => '1', 'PLAIN_OUTPUT' => '1' }
      holder = <<~'ZSH'
        source "$1"
        JOBS_CLEAN_CONFIRMED=1
        jobs_clean_prepare_runtime || exit $?
        print -r -- "JOBS_TEST_READY=$LOG_FILE"
        builtin read -r runtime_release || exit 9
        print -r -- 'first-run-sentinel' >> "$LOG_FILE"
      ZSH
      Open3.popen3(environment, '/bin/zsh', '-c', holder, '--', definitions) do |input, output, errors, waiter|
        begin
          ready = Timeout.timeout(5) do
            loop do
              line = output.gets
              raise '初始化未到达就绪状态' unless line
              break line if line.start_with?('JOBS_TEST_READY=')
            end
          end
          first_log = ready.chomp.delete_prefix('JOBS_TEST_READY=')
          second_output, second_errors, second_status = run_runtime_fixture(home, temp, definitions, <<~'ZSH')
            JOBS_CLEAN_CONFIRMED=1
            jobs_clean_prepare_runtime || :
            [[ -n "$LOG_FILE" && -f "$LOG_FILE" ]] || exit 1
            print -r -- 'second-run-sentinel' >> "$LOG_FILE"
          ZSH
          assert second_status.success?, second_output + second_errors
          logs = Dir.glob(File.join(temp, 'JobsDiskSpaceCleanup.*'))
          assert_equal 2, logs.length
          assert_equal 2, logs.uniq.length
          logs.each { |path| assert_equal 0o600, File.stat(path).mode & 0o777 }
          assert_empty File.read(first_log)
          second_log = (logs - [first_log]).fetch(0)
          assert_equal "second-run-sentinel\n", File.read(second_log)
          input.puts 'release'
          input.close
          assert waiter.value.success?, output.read + errors.read
          assert_equal "first-run-sentinel\n", File.read(first_log)
          assert_equal "second-run-sentinel\n", File.read(second_log)
        ensure
          input.close unless input.closed?
          Process.kill('TERM', waiter.pid) if waiter.alive?
          waiter.value
        end
      end
    end
  end

  def test_runtime_log_creation_failure_stops_before_regular_cleanup
    fixture do |_directory, home, temp, definitions|
      missing_temp = File.join(temp, 'missing temporary directory')
      output, errors, status = run_runtime_fixture(home, missing_temp, definitions, <<~'ZSH')
        jobs_clean_xcode_stage() { return 0; }
        show_script_intro_and_wait() { JOBS_CLEAN_CONFIRMED=1; }
        clean() { print -r -- 'unexpected-clean' > "$HOME/clean-called"; }
        jobs_clean_run_stages
        runtime_code=$?
        print -r -- "JOBS_TEST_LOG=$LOG_FILE"
        exit "$runtime_code"
      ZSH
      assert_equal 1, status.exitstatus, output + errors
      assert_includes errors, '无法在临时目录创建本轮日志，未执行常规清理'
      assert_includes errors, missing_temp
      assert_includes output, "JOBS_TEST_LOG=\n"
      refute File.exist?(File.join(home, 'clean-called'))
      refute File.exist?(missing_temp)
      assert_empty Dir.children(temp)
    end
  end

  def run_retry_fixture(home, temp, definitions, input, code)
    transcript = +''
    result = nil
    stub = <<~'ZSH'
      source "$1"
      JOBS_CLEAN_CONFIRMED=1
      jobs_clean_cache_select_candidates() { /usr/bin/awk -F '\t' '$1 ~ /^[0-9]+$/ { print $1 }' "$1"; }
      jobs_clean_cache_confirm_selected() { return 0; }
      LOG_FILE="$TMPDIR/retry.log"
      : > "$LOG_FILE"
      log() { print -r -- "$1" >> "$LOG_FILE"; }
      functions -c jobs_clean_user_caches fixture_original_clean_user_caches
      for step in jobs_disk_clean_history jobs_clean_move_indexed_build_apps_to_trash jobs_clean_orphaned_simulators jobs_clean_unregister_non_macos_development_apps jobs_clean_refresh_application_lists jobs_clean_homebrew_cleanup jobs_clean_user_caches; do
        functions[$step]='print -r -- "${funcstack[1]}" >> "$TMPDIR/calls"; return 0'
      done
      jobs_clean_xcode_stage() { print unexpected-xcode; return 99; }
    ZSH
    PTY.spawn({ 'HOME' => home, 'TMPDIR' => temp, 'NO_COLOR' => '1', 'TERM' => 'dumb' }, '/bin/zsh', '-c', stub + code, '--', definitions) do |reader, writer, pid|
      writer.write(input)
      writer.flush
      Timeout.timeout(5) do
        begin
          loop { transcript << reader.readpartial(4096) }
        rescue EOFError, Errno::EIO
          # 子进程退出后 PTY 会关闭。
        end
      end
      _, result = Process.wait2(pid)
    end
    [transcript, result]
  end

  def test_return_retries_only_failed_steps_until_the_queue_is_empty
    fixture do |_directory, home, temp, definitions|
      transcript, status = run_retry_fixture(home, temp, definitions, "\n\n", <<~'ZSH')
        local_brew_calls=0
        local_cache_calls=0
        jobs_clean_homebrew_cleanup() {
          print -r -- "${funcstack[1]}" >> "$TMPDIR/calls"
          (( local_brew_calls += 1 ))
          (( local_brew_calls >= 2 ))
        }
        jobs_clean_user_caches() {
          print -r -- "${funcstack[1]}" >> "$TMPDIR/calls"
          (( local_cache_calls += 1 ))
          (( local_cache_calls >= 3 ))
        }
        clean
      ZSH
      assert status.success?, transcript
      calls = File.readlines(File.join(temp, 'calls'), chomp: true).each_with_object(Hash.new(0)) { |name, counts| counts[name] += 1 }
      assert_equal 2, calls.delete('jobs_clean_homebrew_cleanup')
      assert_equal 3, calls.delete('jobs_clean_user_caches')
      assert_equal [1], calls.values.uniq
      assert_equal 5, calls.length
      log = File.read(File.join(temp, 'retry.log'))
      assert_match(/第 3 轮.*1 个步骤/, log)
      assert_includes log, '退出码 1'
      refute_includes transcript, 'unexpected-xcode'
    end
  end

  def test_nonempty_answer_and_eof_keep_failure_without_retry
    ["停止\n", " \n", "\x04"].each do |input|
      fixture do |_directory, home, temp, definitions|
        transcript, status = run_retry_fixture(home, temp, definitions, input, <<~'ZSH')
          jobs_clean_user_caches() { print cache >> "$TMPDIR/calls"; return 7; }
          clean
        ZSH
        assert_equal(input == "\x04" ? 130 : 1, status.exitstatus, transcript)
        assert_equal 1, File.readlines(File.join(temp, 'calls')).count { |line| line.chomp == 'cache' }
        refute_match(/第 2 轮/, File.read(File.join(temp, 'retry.log')))
      end
    end
  end

  def test_noninteractive_failure_does_not_treat_piped_newline_as_confirmation
    fixture do |_directory, home, temp, definitions|
      output, errors, status = run_fixture(home, temp, definitions, <<~'ZSH')
        for step in jobs_disk_clean_history jobs_clean_move_indexed_build_apps_to_trash jobs_clean_orphaned_simulators jobs_clean_unregister_non_macos_development_apps jobs_clean_refresh_application_lists jobs_clean_homebrew_cleanup; do
          functions[$step]='return 0'
        done
        jobs_clean_user_caches() { print cache >> "$TMPDIR/calls"; return 1; }
        clean <<< ''
      ZSH
      assert_equal 130, status.exitstatus, output + errors
      assert_equal 1, File.readlines(File.join(temp, 'calls')).length
      assert_match(/无交互/, File.read(File.join(temp, 'fixture.log')))
    end
  end

  def test_cache_retry_keeps_new_items_and_recreated_successful_paths
    fixture do |_directory, home, temp, definitions|
      cache = File.join(home, 'Library/Caches')
      FileUtils.mkdir_p(cache)
      File.write(File.join(cache, 'succeeded'), 'original')
      File.write(File.join(cache, 'blocked'), 'original blocked')
      File.write(definitions, File.read(definitions).sub('jobs_clean_cache_remove_snapshot "$item" "$work/snapshot"', 'jobs_test_remove_cache "$item"'))
      transcript, status = run_retry_fixture(home, temp, definitions, "\n", <<~'ZSH')
        functions -c fixture_original_clean_user_caches jobs_clean_user_caches
        blocked_attempts=0
        jobs_test_remove_cache() {
          if [[ "${1:t}" == blocked ]]; then
            (( blocked_attempts += 1 ))
            (( blocked_attempts > 1 )) || return 1
          fi
          /bin/rm -rf -- "$1"
        }
        functions -c jobs_clean_confirm_retry fixture_original_confirm_retry
        jobs_clean_confirm_retry() {
          fixture_original_confirm_retry || return $?
          print -n recreated > "$HOME/Library/Caches/succeeded"
          print -n new > "$HOME/Library/Caches/new"
        }
        clean
      ZSH
      assert status.success?, transcript
      refute File.exist?(File.join(cache, 'blocked'))
      assert_equal 'recreated', File.read(File.join(cache, 'succeeded'))
      assert_equal 'new', File.read(File.join(cache, 'new'))
    end
  end

  def test_cache_retry_rejects_replaced_failed_candidate
    fixture do |_directory, home, temp, definitions|
      cache = File.join(home, 'Library/Caches')
      FileUtils.mkdir_p(cache)
      File.write(File.join(cache, 'blocked'), 'original blocked')
      File.write(definitions, File.read(definitions).sub('jobs_clean_cache_remove_snapshot "$item" "$work/snapshot"', 'jobs_test_remove_cache "$item"'))
      transcript, status = run_retry_fixture(home, temp, definitions, "\nstop\n", <<~'ZSH')
        functions -c fixture_original_clean_user_caches jobs_clean_user_caches
        jobs_test_remove_cache() { return 1; }
        functions -c jobs_clean_confirm_retry fixture_original_confirm_retry
        jobs_clean_confirm_retry() {
          fixture_original_confirm_retry || return $?
          /bin/mv "$HOME/Library/Caches/blocked" "$TMPDIR/original-blocked"
          print -n replacement > "$HOME/Library/Caches/blocked"
        }
        clean
      ZSH
      assert_equal 1, status.exitstatus, transcript
      assert_equal 'replacement', File.read(File.join(cache, 'blocked'))
      assert_equal 'original blocked', File.read(File.join(temp, 'original-blocked'))
    end
  end

  def test_retrying_app_changes_refreshes_the_application_list_again
    fixture do |_directory, home, temp, definitions|
      transcript, status = run_retry_fixture(home, temp, definitions, "\n", <<~'ZSH')
        move_attempts=0
        jobs_clean_move_indexed_build_apps_to_trash() {
          print move >> "$TMPDIR/calls"
          (( move_attempts += 1 ))
          JOBS_CLEAN_APPLICATION_INDEX_CHANGED=1
          (( move_attempts > 1 ))
        }
        jobs_clean_refresh_application_lists() {
          print refresh >> "$TMPDIR/calls"
          JOBS_CLEAN_APPLICATION_INDEX_CHANGED=0
          return 0
        }
        clean
      ZSH
      assert status.success?, transcript
      calls = File.readlines(File.join(temp, 'calls'), chomp: true)
      assert_equal 2, calls.count('move')
      assert_equal 2, calls.count('refresh')
      assert_equal %w[move refresh], calls.last(2)
    end
  end

  def test_failed_initial_cache_enumeration_never_expands_on_retry
    fixture do |_directory, home, temp, definitions|
      cache = File.join(home, 'Library/Caches')
      FileUtils.mkdir_p(cache)
      File.write(File.join(cache, 'original'), 'keep original')
      source = File.read(definitions).sub('/usr/bin/find "$cache_dir" -mindepth 1 -maxdepth 1 -print0', 'jobs_test_find_cache "$cache_dir"')
      File.write(definitions, source)
      transcript, status = run_retry_fixture(home, temp, definitions, "\nstop\n", <<~'ZSH')
        functions -c fixture_original_clean_user_caches jobs_clean_user_caches
        jobs_test_find_cache() {
          print find >> "$TMPDIR/find-calls"
          print -rn -- "$1/original"$'\0'
          return 1
        }
        functions -c jobs_clean_confirm_retry fixture_original_confirm_retry
        jobs_clean_confirm_retry() {
          fixture_original_confirm_retry || return $?
          print -n new > "$HOME/Library/Caches/new"
        }
        clean
      ZSH
      assert_equal 1, status.exitstatus, transcript
      assert_equal 1, File.readlines(File.join(temp, 'find-calls')).length
      assert_equal 'keep original', File.read(File.join(cache, 'original'))
      assert_equal 'new', File.read(File.join(cache, 'new'))
    end
  end

  def test_cancelled_retry_step_preserves_signal_code_without_another_prompt
    [129, 130, 143].each do |cancel_code|
      fixture do |_directory, home, temp, definitions|
        code = <<~ZSH
          cache_attempts=0
          jobs_clean_user_caches() {
            print cache >> "$TMPDIR/calls"
            (( cache_attempts += 1 ))
            (( cache_attempts > 1 )) && return #{cancel_code}
            return 1
          }
          clean
        ZSH
        transcript, status = run_retry_fixture(home, temp, definitions, "\n", code)
        assert_equal cancel_code, status.exitstatus, transcript
        assert_equal 2, File.readlines(File.join(temp, 'calls')).count { |line| line.chomp == 'cache' }
        refute_match(/第 3 轮/, File.read(File.join(temp, 'retry.log')))
      end
    end
  end

  def test_successful_run_does_not_offer_retry
    fixture do |_directory, home, temp, definitions|
      transcript, status = run_retry_fixture(home, temp, definitions, "\x04", 'clean')
      assert status.success?, transcript
      assert_equal 7, File.readlines(File.join(temp, 'calls')).length
      refute_match(/失败步骤[？?]/, transcript)
    end
  end

  def test_logged_command_shows_failure_cause_and_preserves_shell_state_and_exit_code
    fixture do |_directory, home, temp, definitions|
      output, errors, status = run_fixture(home, temp, definitions, <<~'ZSH')
        attempt_count=0
        typeset -A pending_fixture=([original]=keep)
        jobs_test_failure() {
          (( attempt_count += 1 ))
          pending_fixture[failed]=retained
          print -u2 -r -- 'Permission denied: fixture-cache'
          return 23
        }
        code=0
        jobs_clean_run_logged jobs_test_failure || code=$?
        [[ "$attempt_count" == 1 && "${pending_fixture[failed]}" == retained && "${pending_fixture[original]}" == keep ]] || exit 88
        exit "$code"
      ZSH
      assert_equal 23, status.exitstatus, output + errors
      assert_equal 1, (output + errors).scan('Permission denied: fixture-cache').length
      assert_equal 1, File.read(File.join(temp, 'fixture.log')).scan('Permission denied: fixture-cache').length
    end
  end

  def test_logged_command_preserves_cancellation_codes
    [129, 130, 143].each do |cancel_code|
      fixture do |_directory, home, temp, definitions|
        code = <<~ZSH
          jobs_test_cancel() { print -u2 -r -- 'cancelled-command-#{cancel_code}'; return #{cancel_code}; }
          jobs_clean_run_logged jobs_test_cancel
        ZSH
        output, errors, status = run_fixture(home, temp, definitions, code)
        assert_equal cancel_code, status.exitstatus, output + errors
        assert_includes output + errors, "cancelled-command-#{cancel_code}"
        assert_includes File.read(File.join(temp, 'fixture.log')), "cancelled-command-#{cancel_code}"
      end
    end
  end

  def test_logged_external_command_preserves_arguments_and_failure
    fixture do |_directory, home, temp, definitions|
      output, errors, status = run_fixture(home, temp, definitions, <<~'ZSH')
        jobs_clean_run_logged /bin/zsh -c 'print -u2 -r -- "$1"; exit 23' -- 'Permission denied: fixture path with spaces'
      ZSH
      assert_equal 23, status.exitstatus, output + errors
      assert_equal 1, (output + errors).scan('Permission denied: fixture path with spaces').length
      assert_equal 1, File.read(File.join(temp, 'fixture.log')).scan('Permission denied: fixture path with spaces').length
    end
  end

  def test_logged_command_success_does_not_replay_old_log_or_report_an_error
    fixture do |_directory, home, temp, definitions|
      output, errors, status = run_fixture(home, temp, definitions, <<~'ZSH')
        print -r -- 'old-log-sentinel' >> "$LOG_FILE"
        jobs_test_success() { print -rn -- 'successful-command-without-newline'; return 0; }
        jobs_clean_run_logged jobs_test_success
      ZSH
      assert status.success?, output + errors
      assert_includes output + errors, 'successful-command-without-newline'
      refute_includes output + errors, 'old-log-sentinel'
      refute_match(/失败|ERROR|Permission denied/, output + errors)
      log = File.read(File.join(temp, 'fixture.log'))
      assert_includes log, 'old-log-sentinel'
      assert_equal 1, log.scan('successful-command-without-newline').length
      refute_match(/失败|ERROR|Permission denied/, log)
    end
  end

  def test_logged_command_does_not_replace_command_failure_with_logging_failure
    [0, 23, 130].each do |command_code|
      fixture do |_directory, home, temp, definitions|
        code = <<~ZSH
          jobs_prompt_tee() { /bin/cat >/dev/null; return 9; }
          jobs_test_command() { print -u2 -r -- 'command-output'; return #{command_code}; }
          jobs_clean_run_logged jobs_test_command
        ZSH
        output, errors, status = run_fixture(home, temp, definitions, code)
        assert_equal(command_code.zero? ? 9 : command_code, status.exitstatus, output + errors)
      end
    end
  end

  def test_logged_retry_appends_each_current_failure_reason_once
    fixture do |_directory, home, temp, definitions|
      transcript, status = run_retry_fixture(home, temp, definitions, "\n\n", <<~'ZSH')
        print -r -- 'old-log-sentinel' >> "$LOG_FILE"
        cache_attempts=0
        jobs_test_cache_attempt() {
          (( cache_attempts += 1 ))
          case "$cache_attempts" in
            1) print -u2 -r -- 'Permission denied: retry-attempt-one'; return 23 ;;
            2) print -u2 -r -- 'Resource busy: retry-attempt-two'; return 24 ;;
            *) print -r -- 'retry-attempt-success'; return 0 ;;
          esac
        }
        jobs_clean_user_caches() { jobs_clean_run_logged jobs_test_cache_attempt; }
        clean
      ZSH
      assert status.success?, transcript
      log = File.read(File.join(temp, 'retry.log'))
      %w[retry-attempt-one retry-attempt-two retry-attempt-success].each do |marker|
        assert_equal 1, transcript.scan(marker).length, transcript
        assert_equal 1, log.scan(marker).length, log
      end
      refute_includes transcript, 'old-log-sentinel'
      assert_equal 1, log.scan('old-log-sentinel').length
      refute_includes transcript, 'ClearScrollback'
      refute_includes transcript, "\e[2J"
    end
  end

  def test_cache_delete_failure_cause_is_displayed_and_logged
    fixture do |_directory, home, temp, definitions|
      cache = File.join(home, 'Library/Caches')
      FileUtils.mkdir_p(cache)
      File.write(File.join(cache, 'blocked'), 'keep blocked')
      File.write(definitions, File.read(definitions).sub('jobs_clean_cache_remove_snapshot "$item" "$work/snapshot"', 'jobs_test_remove_cache "$item"'))
      transcript, status = run_retry_fixture(home, temp, definitions, "stop\n", <<~'ZSH')
        functions -c fixture_original_clean_user_caches jobs_clean_user_caches
        jobs_test_remove_cache() { print -u2 -r -- 'Permission denied: blocked-cache-delete'; return 13; }
        clean
      ZSH
      assert_equal 1, status.exitstatus, transcript
      assert_equal 'keep blocked', File.read(File.join(cache, 'blocked'))
      assert_equal 1, transcript.scan('Permission denied: blocked-cache-delete').length, transcript
      assert_equal 1, File.read(File.join(temp, 'retry.log')).scan('Permission denied: blocked-cache-delete').length
    end
  end

  def test_logged_stderr_keeps_machine_stdout_separate
    fixture do |_directory, home, temp, definitions|
      output, errors, status = run_fixture(home, temp, definitions, <<~'ZSH')
        jobs_test_machine_output() {
          printf '%s\0' '{"devices":[]}'
          print -u2 -r -- 'Permission denied: machine-command'
          return 23
        }
        jobs_clean_run_stderr_logged jobs_test_machine_output > "$TMPDIR/machine-snapshot"
      ZSH
      assert_equal 23, status.exitstatus, output + errors
      assert_equal "{\"devices\":[]}\0", File.binread(File.join(temp, 'machine-snapshot'))
      assert_equal 1, errors.scan('Permission denied: machine-command').length
      refute_includes output, 'Permission denied: machine-command'
      log = File.read(File.join(temp, 'fixture.log'))
      assert_equal 1, log.scan('Permission denied: machine-command').length
      refute_includes log, '{"devices":[]}'
    end
  end

  def test_same_log_redirection_records_each_cause_once_as_plain_text
    fixture do |_directory, home, temp, definitions|
      code = <<~'ZSH'
        source "$1"
        LOG_FILE="$TMPDIR/shared-action.log"
        : > "$LOG_FILE"
        jobs_test_all_output() {
          printf '\033[31mPermission denied: same-file-all\033[0m'
          return 23
        }
        jobs_test_stderr_output() {
          printf '%s' 'machine-kept'
          printf '\033[33mResource busy: same-file-stderr\033[0m' >&2
          return 130
        }
        command_code=0
        jobs_clean_run_logged jobs_test_all_output >> "$LOG_FILE" 2>&1 || command_code=$?
        (( command_code == 23 )) || exit 88
        /bin/cp "$LOG_FILE" "$TMPDIR/after-all"
        printf '\n' >> "$LOG_FILE"
        command_code=0
        jobs_clean_run_stderr_logged jobs_test_stderr_output > "$TMPDIR/machine-snapshot" 2>> "$LOG_FILE" || command_code=$?
        (( command_code == 130 )) || exit 89
        /bin/cp "$LOG_FILE" "$TMPDIR/after-stderr"
        printf '\n' >> "$LOG_FILE"
        log $'\033[35msame-file-log\033[0m' >> "$LOG_FILE" 2>&1
      ZSH
      output, errors, status = Open3.capture3({ 'HOME' => home, 'TMPDIR' => temp, 'NO_COLOR' => '1', 'PLAIN_OUTPUT' => '1' }, '/bin/zsh', '-c', code, '--', definitions)
      assert status.success?, output + errors
      assert_empty output + errors
      assert_equal 'Permission denied: same-file-all', File.binread(File.join(temp, 'after-all'))
      assert_equal "Permission denied: same-file-all\nResource busy: same-file-stderr", File.binread(File.join(temp, 'after-stderr'))
      assert_equal 'machine-kept', File.binread(File.join(temp, 'machine-snapshot'))
      log = File.binread(File.join(temp, 'shared-action.log'))
      assert_equal "Permission denied: same-file-all\nResource busy: same-file-stderr\nsame-file-log\n", log
      %w[same-file-all same-file-stderr same-file-log].each { |marker| assert_equal 1, log.scan(marker).length }
      refute_includes log, "\e"
      refute_includes log, "\x01"
    end
  end

  def test_log_delta_shows_only_current_action_without_appending_again
    fixture do |_directory, home, temp, definitions|
      output, errors, status = run_fixture(home, temp, definitions, <<~'ZSH')
        action_log="$TMPDIR/action.log"
        print -r -- 'old-action-sentinel' > "$action_log"
        action_start="$(/usr/bin/stat -f '%z' "$action_log")" || exit 88
        print -r -- 'Permission denied: current-xcode-action' >> "$action_log"
        jobs_xcode_show_log_delta "$action_log" "$action_start" || exit $?
        action_end="$(/usr/bin/stat -f '%z' "$action_log")" || exit 88
        jobs_xcode_show_log_delta "$action_log" "$action_end"
      ZSH
      assert status.success?, output + errors
      refute_includes output + errors, 'old-action-sentinel'
      assert_equal 1, (output + errors).scan('Permission denied: current-xcode-action').length
      assert_equal "old-action-sentinel\nPermission denied: current-xcode-action\n", File.read(File.join(temp, 'action.log'))
      assert_empty File.read(File.join(temp, 'fixture.log'))
    end
  end

  def test_xcode_failed_and_cancelled_actions_show_only_their_current_diagnostics
    fixture do |_directory, home, temp, definitions|
      source = File.read(definitions)
      source = source.gsub('/usr/bin/xcrun --find simctl', 'false')
      source = source.gsub('/usr/bin/pgrep -x Xcode', 'false').gsub('/usr/bin/pgrep -x xcodebuild', 'false')
      File.write(definitions, source)
      output, errors, status = run_fixture(home, temp, definitions, <<~'ZSH')
        fzf() { return 0; }
        jobs_xcode_interactive() { return 0; }
        jobs_xcode_read() { REPLY=''; }
        jobs_xcode_scan() {
          print -r -- 'old-xcode-log-sentinel' > "$xwork/action.log"
          for index in 1 2; do
            xpaths[$index]="$HOME/Library/Developer/Xcode/DerivedData/fixture-$index"
            xgroups[$index]=DerivedData
            xsizes[$index]=1
            xlabels[$index]="fixture-$index"
            xkinds[$index]=directory
          done
        }
        jobs_xcode_pick_group() { xselected[1]=1; xselected[2]=1; return 0; }
        jobs_xcode_execute_path() {
          print -u2 -r -- "Permission denied: xcode-action-$1"
          [[ "$1" == 1 ]] && return 13
          return 130
        }
        jobs_clean_xcode_stage
      ZSH
      assert_equal 130, status.exitstatus, output + errors
      log_paths = Dir.glob(File.join(temp, 'JobsXcodeCleanup.*/action.log'))
      assert_equal 1, log_paths.length
      log = File.read(log_paths.first)
      %w[xcode-action-1 xcode-action-2].each do |marker|
        assert_equal 1, (output + errors).scan(marker).length, output + errors
        assert_equal 1, log.scan(marker).length, log
      end
      refute_includes output + errors, 'old-xcode-log-sentinel'
      assert_equal 1, log.scan('old-xcode-log-sentinel').length
    end
  end

  def test_help_and_noninteractive_never_delete_cache_or_history
    fixture do |_directory, home, temp, _definitions|
      cache = File.join(home, 'Library/Caches')
      FileUtils.mkdir_p(cache)
      File.write(File.join(cache, 'sentinel'), 'keep')
      File.write(File.join(home, '.zsh_history'), 'keep history')
      environment = { 'HOME' => home, 'TMPDIR' => temp, 'NO_COLOR' => '1' }
      output, status = Open3.capture2e(environment, '/bin/zsh', SCRIPT, '--help')
      assert status.success?, output
      _, status = Open3.capture2e(environment, '/bin/zsh', SCRIPT, stdin_data: "YES\n")
      refute status.success?
      assert_equal 'keep', File.read(File.join(cache, 'sentinel'))
      assert_equal 'keep history', File.read(File.join(home, '.zsh_history'))
    end
  end

  def test_history_and_cache_links_never_follow_external_targets
    fixture do |directory, home, temp, definitions|
      external = File.join(directory, 'external')
      cache = File.join(home, 'Library/Caches')
      FileUtils.mkdir_p([external, cache])
      File.write(File.join(external, 'history'), 'external history')
      File.write(File.join(external, 'cache'), 'external cache')
      File.symlink(File.join(external, 'history'), File.join(home, '.zsh_history'))
      File.symlink(external, File.join(cache, 'linked'))
      File.write(File.join(cache, '.hidden'), 'cache')
      File.write(File.join(cache, "quote '\n$(touch escaped)"), 'cache')
      output, errors, status = run_fixture(home, temp, definitions, <<~'ZSH')
        jobs_disk_clean_history && exit 81
        jobs_clean_user_caches || exit $?
        [[ -d "$HOME/Library/Caches" && ! -e "$HOME/Library/Caches/.hidden" ]] || exit 82
      ZSH
      assert status.success?, output + errors
      assert_equal 'external history', File.read(File.join(external, 'history'))
      assert_equal 'external cache', File.read(File.join(external, 'cache'))
      assert_equal ['linked'], Dir.children(cache)
      refute File.exist?(File.join(directory, 'escaped'))
    end
  end

  def test_xcode_managed_roots_are_preserved_by_legacy_cache_cleanup
    fixture do |_directory, home, temp, definitions|
      cache = File.join(home, 'Library/Caches')
      FileUtils.mkdir_p(cache)
      protected_roots = %w[DeviceSupport CoreSimulator/Caches/dyld Xcode/DerivedData Xcode/Archives Xcode/UserData/Previews]
      protected_roots.each { |name| FileUtils.mkdir_p(File.join(home, 'Library/Developer', name)); File.write(File.join(home, 'Library/Developer', name, 'keep'), 'keep') }
      File.write(File.join(cache, 'ordinary'), 'remove')
      output, errors, status = run_fixture(home, temp, definitions, 'jobs_clean_user_caches')
      assert status.success?, output + errors
      protected_roots.each { |name| assert_equal 'keep', File.read(File.join(home, 'Library/Developer', name, 'keep')) }
      refute File.exist?(File.join(cache, 'ordinary'))
    end
  end

  def test_linked_spotlight_parent_and_outside_home_apps_are_not_moved
    fixture do |directory, home, temp, definitions|
      external = File.join(directory, 'outside/Build/Products/Debug-iphonesimulator/Fake.app')
      FileUtils.mkdir_p(external)
      File.symlink(File.join(directory, 'outside'), File.join(home, 'linked'))
      linked = File.join(home, 'linked/Build/Products/Debug-iphonesimulator/Fake.app')
      regular = File.join(home, 'build/Products/Debug-iphoneos/Owned.app')
      FileUtils.mkdir_p(regular)
      File.write(File.join(temp, 'candidates'), [linked, external, regular].join("\0") + "\0")
      output, errors, status = run_fixture(home, temp, definitions, <<~'ZSH')
        mdfind() { /bin/cat "$TMPDIR/candidates"; }
        LAUNCH_SERVICES_REGISTER=/nonexistent
        jobs_clean_move_indexed_build_apps_to_trash || exit $?
      ZSH
      assert status.success?, output + errors
      assert File.directory?(external)
      refute File.exist?(regular)
      assert_equal 1, Dir.glob(File.join(home, '.Trash/JobsDiskSpaceCleanup-DevelopmentApps.*/**/Owned.app')).length
    end
  end

  def test_cancelled_legacy_step_stops_remaining_pipeline
    fixture do |_directory, home, temp, definitions|
      output, errors, status = run_fixture(home, temp, definitions, <<~'ZSH')
        jobs_disk_clean_history() { return 0; }
        jobs_clean_move_indexed_build_apps_to_trash() { return 0; }
        jobs_clean_orphaned_simulators() { return 130; }
        jobs_clean_unregister_non_macos_development_apps() { print bypassed; return 0; }
        clean
      ZSH
      assert_equal 130, status.exitstatus, output + errors
      refute_includes output, 'bypassed'
    end
  end

  def test_legacy_spotlight_keeps_xcode_managed_build_products
    fixture do |_directory, home, temp, definitions|
      managed = File.join(home, 'Library/Developer/Xcode/DerivedData/Example/Build/Products/Debug-iphonesimulator/Keep.app')
      FileUtils.mkdir_p(managed)
      File.write(File.join(temp, 'candidates'), managed + "\0")
      output, errors, status = run_fixture(home, temp, definitions, <<~'ZSH')
        mdfind() { /bin/cat "$TMPDIR/candidates"; }
        LAUNCH_SERVICES_REGISTER=/nonexistent
        jobs_clean_move_indexed_build_apps_to_trash
      ZSH
      assert status.success?, output + errors
      assert File.directory?(managed), 'Xcode 跳过／未选项目不得在后续旧清理中移走'
      assert_empty Dir.children(File.join(home, '.Trash'))
    end
  end

  def test_cache_root_symbolic_link_is_preserved
    fixture do |directory, home, temp, definitions|
      external = File.join(directory, 'external')
      FileUtils.mkdir_p([external, File.join(home, 'Library')])
      File.write(File.join(external, 'keep'), 'keep')
      File.symlink(external, File.join(home, 'Library/Caches'))
      output, errors, status = run_fixture(home, temp, definitions, 'jobs_clean_user_caches')
      refute status.success?, output + errors
      assert_equal 'keep', File.read(File.join(external, 'keep'))
    end
  end

  def test_terminal_requires_empty_enter_for_legacy_cleanup
    fixture do |_directory, home, temp, definitions|
      %w[YES yes CANCEL].push(' ', '', nil).each do |answer|
        transcript = +''
        code = <<~'ZSH'
          source "$1"
          jobs_clean_xcode_stage() { return 0; }
          jobs_clean_prepare_runtime() { print PREPARED; }
          clean() { print CLEANED; }
          main
        ZSH
        result = nil
        PTY.spawn({ 'HOME' => home, 'TMPDIR' => temp, 'NO_COLOR' => '1', 'TERM' => 'dumb' }, '/bin/zsh', '-c', code, '--', definitions) do |reader, writer, pid|
          writer.write(answer.nil? ? "\u0004" : answer + "\n")
          writer.flush
          Timeout.timeout(5) do
            begin
              loop { transcript << reader.readpartial(4096) }
            rescue EOFError, Errno::EIO
              # 子进程退出后 PTY 会关闭。
            end
          end
          _, result = Process.wait2(pid)
        end
        assert_equal(answer == '' ? 0 : 130, result.exitstatus, transcript)
        assert_equal(answer == '', transcript.include?('PREPARED'), transcript)
        assert_equal(answer == '', transcript.include?('CLEANED'), transcript)
      end
    end
  end

  def test_cache_directory_replaced_after_snapshot_keeps_new_contents
    fixture do |_directory, home, temp, definitions|
      cache = File.join(home, 'Library/Caches')
      FileUtils.mkdir_p(cache)
      File.write(File.join(cache, 'same-name'), 'original')
      output, errors, status = run_fixture(home, temp, definitions, <<~'ZSH')
        functions[original_reliable_path]="${functions[jobs_disk_clean_reliable_path]}"
        path_checks=0
        jobs_disk_clean_reliable_path() {
          (( path_checks += 1 ))
          if (( path_checks == 2 )); then
            /bin/mv "$HOME/Library/Caches" "$HOME/Library/Caches.original"
            /bin/mkdir "$HOME/Library/Caches"
            print -n -r -- replacement > "$HOME/Library/Caches/same-name"
          fi
          original_reliable_path "$@"
        }
        jobs_clean_user_caches
      ZSH
      refute status.success?, output + errors
      assert_equal 'replacement', File.read(File.join(cache, 'same-name'))
      assert_equal 'original', File.read(File.join(home, 'Library/Caches.original/same-name'))
    end
  end

  def test_history_parent_replaced_with_link_keeps_external_history
    fixture do |directory, home, temp, definitions|
      sessions = File.join(home, '.zsh_sessions')
      external = File.join(directory, 'external-history')
      FileUtils.mkdir_p([sessions, external])
      File.write(File.join(sessions, 'one.history'), 'original')
      File.write(File.join(external, 'one.history'), 'external')
      File.write(File.join(temp, 'external-path'), external)
      output, errors, status = run_fixture(home, temp, definitions, <<~'ZSH')
        functions[original_reliable_path]="${functions[jobs_disk_clean_reliable_path]}"
        history_checks=0
        jobs_disk_clean_reliable_path() {
          if [[ "$1" == "$HOME/.zsh_sessions/one.history" ]]; then
            (( history_checks += 1 ))
            if (( history_checks == 2 )); then
              /bin/mv "$HOME/.zsh_sessions" "$HOME/.zsh_sessions.original"
              /bin/ln -s "$(<"$TMPDIR/external-path")" "$HOME/.zsh_sessions"
            fi
          fi
          original_reliable_path "$@"
        }
        jobs_disk_clean_history
      ZSH
      refute status.success?, output + errors
      assert_equal 'external', File.read(File.join(external, 'one.history'))
      assert_equal 'original', File.read(File.join(home, '.zsh_sessions.original/one.history'))
    end
  end
end
