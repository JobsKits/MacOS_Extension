# Created by Jobs. Isolated SDK acquisition, no real network or tool installation.
# JOBS_TERMINAL_STYLE_GUARD_V1_BEGIN
if $PROGRAM_NAME == __FILE__
  # 直接运行时由 fork 父进程保护配色；子进程继续原文件，不重放 Ruby 参数和预载模块。
  def jobs_terminal_style_bootstrap_v1
    return unless $PROGRAM_NAME == __FILE__
    plain = lambda do
      ENV.update('PLAIN_OUTPUT' => '1', 'NO_COLOR' => '1', 'FORCE_COLOR' => '0',
                 'CLICOLOR' => '0', 'ANSI_COLORS_DISABLED' => '1', 'npm_config_color' => 'false')
    end
    notify = lambda do |message|
      encoding = $stderr.external_encoding || Encoding::UTF_8
      $stderr.write((message + "\n").encode(encoding, invalid: :replace, undef: :replace))
    end
    return unless $stdin.tty? && $stdout.tty?
    return if ENV.key?('NO_COLOR') || ENV['PLAIN_OUTPUT'] == '1' ||
              ENV['IS_SOURCETREE_RUNTIME'] == '1' ||
              ENV.keys.any? { |key| key.match?(/\A(?:SOURCETREE|SOURCE_TREE)/i) }
    return if ['', 'dumb'].include?(ENV.fetch('TERM', ''))
    if File::ALT_SEPARATOR == '\\' || !Process.respond_to?(:fork) ||
       Thread.list.length > 1 || ENV['TMUX'] || ENV['STY']
      plain.call
      return
    end
    tty_name = IO.popen(['tty'], err: File::NULL, &:read).strip
    groups = IO.popen(['ps', '-o', 'pgid=', '-o', 'tpgid=', '-p', Process.pid.to_s], err: File::NULL, &:read).split
    unless tty_name.match?(%r{\A/dev/[A-Za-z0-9_./-]+\z}) && groups.length == 2 &&
           groups.all? { |group| group.match?(/\A\d+\z/) } && groups[0].to_i > 0 && groups[0] == groups[1]
      plain.call
      return
    end
    owner = ENV['JOBS_TERMINAL_STYLE_OWNER']
    if ENV['JOBS_TERMINAL_STYLE_TTY'] == tty_name && owner && owner.match?(/\A\d+\z/)
      begin
        Process.kill(0, owner.to_i)
        return
      rescue Errno::ESRCH, Errno::EPERM
      end
    end
    require 'io/console'
    require 'tmpdir'
    if Thread.list.length > 1
      plain.call
      return
    end
    tty = File.open('/dev/tty', 'r+')
    tty.binmode
    tty.sync = true
    keys = ['10', '11', '12'] + (0..15).map { |index| "4;#{index}" }
    palette = %w[000000 ff5f56 5fd787 ffd75f 5fafff d787ff 5fd7ff eeeeee
                 9e9e9e ff8787 87ffaf ffff87 87bfff ffafff afffff ffffff]
    targets = { '10' => 'ffffff', '11' => '000000', '12' => 'ffffff' }
    palette.each_with_index { |color, index| targets["4;#{index}"] = color }
    query = lambda do |key|
      tty.write("\e]#{key};?\a")
      bytes = ''.b
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 0.3
      loop do
        remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        return nil if remaining <= 0 || !IO.select([tty], nil, nil, remaining)
        piece = tty.read_nonblock(256, exception: false)
        next if piece == :wait_readable
        return nil unless piece && !piece.empty?
        bytes << piece
        return nil if bytes.bytesize > 256 || !bytes.start_with?("\e".b)
        break if bytes.end_with?("\a".b) || bytes.end_with?("\e\\".b)
      end
      match = bytes.match(/\A\e\]#{Regexp.escape(key)};rgb:([0-9a-fA-F]{1,4})\/([0-9a-fA-F]{1,4})\/([0-9a-fA-F]{1,4})(?:\a|\e\\)\z/n)
      return nil unless match
      components = match.captures.map { |hex| (hex.to_i(16) * 65535.0 / (16**hex.length - 1)).round }
      { raw: bytes, rgb: components }
    rescue IOError, SystemCallError
      nil
    end
    snapshot = lambda do
      values = {}
      tty.raw(min: 0, time: 0, intr: true) do
        keys.each do |key|
          value = query.call(key)
          return nil unless value
          values[key] = value
        end
      end
      values
    rescue IOError, SystemCallError, ArgumentError
      nil
    end
    original = snapshot.call
    unless original
      notify.call('终端不支持完整配色保存，或启动时收到其它输入；保留原配色并使用纯文本。')
      tty.close
      plain.call
      return
    end
    directory = Dir.mktmpdir('jobs-terminal-style-')
    recovery = File.join(directory, 'restore.sh')
    original_bytes = keys.map { |key| original.fetch(key).fetch(:raw) }.join
    recovery_source = "#!/bin/sh\n" \
      "[ -t 0 ] && [ \"$(tty)\" = '#{tty_name}' ] || { printf '请在原终端运行恢复入口。\\n' >&2; exit 1; }\n" \
      "printf '本操作会覆盖此终端当前配色。确认恢复脚本启动前的配色，请输入 YES：' >&2\n" \
      "IFS= read -r jobs_restore_choice\n[ \"$jobs_restore_choice\" = YES ] || exit 1\n" \
      "printf '%s\\033[0m' '#{original_bytes}' > /dev/tty\n"
    File.open(recovery, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
      file.binmode
      file.write(recovery_source.b)
    end
    notify.call("本次终端临时使用黑底白字；强退后恢复入口：sh \"#{recovery}\"")
    changed = false
    applied = nil
    # 比较仍生效的本轮颜色，只恢复未被用户另行修改的项。
    cleanup = lambda do
      current = applied && snapshot.call
      unless current
        notify.call("终端配色未能安全自动恢复；确认覆盖当前配色后可运行：sh \"#{recovery}\"")
        return false
      end
      conflicts = []
      restore_bytes = ''.b
      keys.each do |key|
        if current.fetch(key).fetch(:rgb) == applied.fetch(key).fetch(:rgb)
          restore_bytes << original.fetch(key).fetch(:raw)
        else
          conflicts << key
        end
      end
      tty.write(restore_bytes + "\e[0m".b)
      if conflicts.empty?
        File.unlink(recovery)
        Dir.rmdir(directory)
        true
      else
        notify.call("检测到运行期间的配色变更，已保留这些项：#{conflicts.join(' ')}")
        notify.call("确认要覆盖后续改色时才使用恢复入口：sh \"#{recovery}\"")
        false
      end
    rescue IOError, SystemCallError
      notify.call("终端配色未能安全自动恢复；确认覆盖当前配色后可运行：sh \"#{recovery}\"")
      false
    end
    child_pid = nil
    guardian = false
    interrupted = nil
    previous_signals = {}
    %w[INT TERM HUP].each do |name|
      previous_signals[name] = Signal.trap(name) do
        interrupted = name
        if child_pid && name != 'INT'
          begin
            Process.kill(name, child_pid)
          rescue Errno::ESRCH
          end
        end
      end
    end
    begin
      changed = true
      tty.write(targets.map { |key, color| "\e]#{key};##{color}\a" }.join + "\e[0m")
      applied = snapshot.call
      unless applied
        notify.call('无法核实本次临时配色，已停止启动业务。')
        raise SystemExit, 1
      end
      desired = targets.all? do |key, hex|
        rgb = hex.scan(/../).map { |component| component.to_i(16) * 257 }
        applied.fetch(key).fetch(:rgb).zip(rgb).all? { |actual, expected| (actual - expected).abs <= 255 }
      end
      unless desired
        notify.call('终端未接受本次配色，恢复后使用纯文本。')
        restored = cleanup.call
        changed = false
        raise SystemExit, 1 unless restored
        plain.call
        return
      end
      if interrupted
        raise SystemExit, 128 + Signal.list.fetch(interrupted)
      end
      if Thread.list.length > 1
        restored = cleanup.call
        changed = false
        raise SystemExit, 1 unless restored
        plain.call
        return
      end
      $stdout.flush
      $stderr.flush
      begin
        child_pid = Process.fork
      rescue NotImplementedError, SystemCallError
        restored = cleanup.call
        changed = false
        raise SystemExit, 1 unless restored
        plain.call
        return
      end
      unless child_pid
        changed = false
        ENV['JOBS_TERMINAL_STYLE_TTY'] = tty_name
        ENV['JOBS_TERMINAL_STYLE_OWNER'] = Process.ppid.to_s
        raise SystemExit, 128 + Signal.list.fetch(interrupted) if interrupted
        return
      end
      guardian = true
      result = nil
      loop do
        begin
          _, result = Process.wait2(child_pid)
          break
        rescue Interrupt, Errno::EINTR
        end
      end
      status_code = result.exitstatus || 128 + result.termsig
      %w[INT TERM HUP].each { |name| Signal.trap(name, 'IGNORE') }
      restored = cleanup.call
      changed = false
      status_code = 1 if !restored && status_code.zero?
      tty.close
      Process.exit!(status_code)
    ensure
      if changed
        %w[INT TERM HUP].each { |name| Signal.trap(name, 'IGNORE') }
        cleanup.call
      end
      previous_signals.each { |name, handler| Signal.trap(name, handler) } unless guardian
      tty.close unless tty.closed?
    end
  rescue IOError, SystemCallError, LoadError => error
    if guardian
      notify.call("终端保护监督进程异常：#{error.message}")
      Process.exit!(1)
    end
    raise SystemExit, 1 if changed
    notify.call("终端保护不可用，使用纯文本：#{error.message}")
    plain.call
  end
  jobs_terminal_style_bootstrap_v1

end
# JOBS_TERMINAL_STYLE_GUARD_V1_END

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'shellwords'
require 'timeout'
require 'digest'

require_relative '../../../Tests/SourceLayoutHelper.rb/SourceLayoutHelper'

class SdkAcquisitionRetryTests < Minitest::Test
  ROOT = File.expand_path('../../..', __dir__)
  MODULE = JobsSourceLayout.file(File.join(ROOT, 'JobsFlutterTools/Scripts/Tools/【MacOS】SDK获取重试.zsh/【MacOS】SDK获取重试.zsh'))
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
      library = File.read(JobsSourceLayout.file(File.join(ROOT, relative))).sub(/\nmain "\$@"\s*\z/, "\n")
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
      library = File.read(JobsSourceLayout.file(File.join(ROOT, relative))).sub(/\nmain "\$@"\s*\z/, "\n")
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
    source = JobsSourceLayout.file(File.join(ROOT, 'JobsFlutterTools/Scripts/Tools/【MacOS】DownloadProjectGradle.zsh/【MacOS】DownloadProjectGradle.zsh'))
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
      library = File.read(JobsSourceLayout.file(File.join(ROOT, relative))).sub(/\nmain "\$@"\s*\z/, "\n")
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
    helper = JobsSourceLayout.file(File.join(ROOT, 'JobsFlutterTools/Scripts/Tools/FlutterRunner.jxa/FlutterRunner.jxa'))
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
      library = File.read(JobsSourceLayout.file(File.join(ROOT, relative))).sub(/\nmain "\$@"\s*\z/, "\n")
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
