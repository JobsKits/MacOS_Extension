# frozen_string_literal: true
# Created by Jobs on 2026年10月28日，星期三。
# 在私有项目与假 SDK 中跑真实分发入口；不安装工具、不联网、不改 Finder 登记。
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

require 'fileutils'
require 'minitest/autorun'
require 'open3'
require 'pty'
require 'timeout'
require 'tmpdir'
require 'json'

require_relative '../../../Tests/SourceLayoutHelper.rb/SourceLayoutHelper'

class PubGetSdkPreparationTests < Minitest::Test
  TOOLS = File.expand_path(ENV.fetch('JOBS_TEST_TOOLS_DIR', '../Scripts/Tools'), File.dirname(__dir__))

  def setup
    @root = File.realpath(Dir.mktmpdir('jobs-pub-get-sdk-'))
    @project = File.join(@root, "项目 空格 ' $(touch NEVER) ; literal")
    @tools = File.join(@root, 'tools')
    @trace = File.join(@root, 'trace')
    @sdk = File.join(@root, 'prepared-sdk')
    @bin = File.join(@root, 'bin')
    FileUtils.mkdir_p([File.join(@project, 'lib'), @tools, @bin, File.join(@root, 'tmp')])
    File.write(File.join(@project, 'pubspec.yaml'), "name: fixture\ndependencies:\n  flutter:\n    sdk: flutter\n")
    %w[DispatchFlutterTools.zsh InspectFlutterProject.zsh].each do |name|
      JobsSourceLayout.copy(JobsSourceLayout.file(File.join(TOOLS, name)), @tools)
    end
    @env = {
      'HOME' => @root, 'TMPDIR' => File.join(@root, 'tmp') + '/',
      'PATH' => "#{@bin}:/usr/bin:/bin", 'NO_COLOR' => '1', 'TERM' => 'dumb',
      'JOBS_TEST_ROOT' => @root, 'JOBS_TEST_TRACE' => @trace,
      'JOBS_TEST_SDK' => @sdk, 'SOURCETREE' => nil, 'SOURCE_TREE' => nil
    }
    write_executable(File.join(@bin, 'flutter'), 'print global-flutter >> "$JOBS_TEST_TRACE"; exit 99')
    write_executable(File.join(@bin, 'dart'), 'print global-dart >> "$JOBS_TEST_TRACE"; exit 99')
    write_sdk(@sdk)
    write_manager
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def test_unbound_project_prepares_sdk_then_checks_health_before_pub_get
    output, result = dispatch
    assert result.success?, output
    assert_equal ['manager', 'flutter|--version --machine', 'dart|--version', 'flutter|pub get'], trace
    assert_equal ['--project', @project, '1'], File.binread(File.join(@root, 'manager-arguments')).force_encoding('UTF-8').split("\0")
    assert_includes output, '继续拉取'
    assert_safe_paths
  end

  def test_healthy_pinned_sdk_is_reused_without_manager_or_global_sdk
    bind_sdk
    output, result = dispatch
    assert result.success?, output
    assert_equal ['flutter|--version --machine', 'dart|--version', 'flutter|pub get'], trace
    refute File.exist?(File.join(@root, 'manager-arguments'))
    assert_safe_paths
  end

  def test_legacy_fvm_config_with_healthy_sdk_is_reused
    bind_sdk(legacy: true)
    output, result = dispatch
    assert result.success?, output
    assert_equal ['flutter|--version --machine', 'dart|--version', 'flutter|pub get'], trace
  end

  def test_explicit_system_sdk_record_wins_over_old_fvm_and_global_flutter
    bind_sdk
    File.delete(File.join(@project, '.fvm/flutter_sdk'))
    write_environment
    output, result = dispatch
    assert result.success?, output
    assert_equal ['flutter|--version --machine', 'dart|--version', 'flutter|pub get'], trace
    refute File.exist?(File.join(@root, 'manager-arguments'))
  end

  def test_system_sdk_record_check_is_read_only_and_needs_no_jdk
    write_environment
    output, result = inspect_check
    assert result.success?, output
    assert_includes output, '计划：flutter pub get'
    assert_empty trace
    assert_empty Dir.children(File.join(@root, 'tmp'))
  end

  def test_broken_explicit_sdk_does_not_switch_to_fvm
    write_environment
    output, result = dispatch(env: { 'JOBS_TEST_INITIAL_FLUTTER_CODE' => '41' })
    assert_equal 41, result.exitstatus, output
    assert_equal ['flutter|--version --machine'], trace
    assert_includes output, '未拉取依赖或切换到 FVM'
  end

  def test_foreign_or_malformed_or_linked_environment_stops_before_sdk
    write_environment(platform: 'Windows')
    output, result = inspect_check
    refute result.success?, output
    File.write(File.join(@project, '.jobs/flutter-environment.json'), '{bad json')
    output, result = inspect_check
    refute result.success?, output
    File.delete(File.join(@project, '.jobs/flutter-environment.json'))
    File.symlink(File.join(@root, 'missing'), File.join(@project, '.jobs/flutter-environment.json'))
    output, result = inspect_check
    refute result.success?, output
    assert_empty trace
  end

  def test_declaration_with_broken_link_enters_sdk_preparation
    FileUtils.mkdir_p(File.join(@project, '.fvm'))
    File.write(File.join(@project, '.fvmrc'), '{"flutter":"3.29.3"}')
    File.symlink(File.join(@root, 'missing-sdk'), File.join(@project, '.fvm/flutter_sdk'))
    output, result = dispatch
    assert result.success?, output
    assert_equal ['manager', 'flutter|--version --machine', 'dart|--version', 'flutter|pub get'], trace
  end

  def test_executable_but_broken_flutter_is_repaired_once
    bind_sdk
    output, result = dispatch(env: { 'JOBS_TEST_INITIAL_FLUTTER_CODE' => '41' })
    assert result.success?, output
    assert_equal ['flutter|--version --machine', 'manager', 'flutter|--version --machine', 'dart|--version', 'flutter|pub get'], trace
  end

  def test_executable_but_broken_dart_is_repaired_once
    bind_sdk
    output, result = dispatch(env: { 'JOBS_TEST_INITIAL_DART_CODE' => '42' })
    assert result.success?, output
    assert_equal ['flutter|--version --machine', 'dart|--version', 'manager', 'flutter|--version --machine', 'dart|--version', 'flutter|pub get'], trace
  end

  def test_missing_actual_dart_runtime_is_not_hidden_by_bin_dart_shim
    bind_sdk
    File.delete(File.join(@sdk, 'bin/cache/dart-sdk/bin/dart'))
    write_executable(File.join(@sdk, 'bin/dart'), 'print unexpected-dart-shim >> "$JOBS_TEST_TRACE"')
    output, result = dispatch(env: { 'JOBS_TEST_MANAGER_MODE' => 'noop' })
    refute result.success?, output
    assert_equal ['flutter|--version --machine', 'manager', 'flutter|--version --machine'], trace
    assert_includes output, '复检失败'
  end

  def test_manager_failure_preserves_exit_code_and_stops_dependency_pull
    output, result = dispatch(env: { 'JOBS_TEST_MANAGER_CODE' => '37' })
    assert_equal 37, result.exitstatus, output
    assert_equal ['manager'], trace
    assert_includes output, '未拉取依赖'
  end

  def test_manager_cancellation_stops_even_if_an_sdk_has_become_healthy
    output, result = dispatch(env: { 'JOBS_TEST_MANAGER_MODE' => 'cancel-after-prepare' })
    assert_equal 130, result.exitstatus, output
    assert_equal ['manager'], trace
    assert File.executable?(File.join(@project, '.fvm/flutter_sdk/bin/flutter'))
    assert_includes output, '未拉取依赖'
  end

  def test_manager_success_without_binding_fails_recheck_without_retry
    output, result = dispatch(env: { 'JOBS_TEST_MANAGER_MODE' => 'noop' })
    refute result.success?, output
    assert_equal ['manager'], trace
    assert_includes output, '复检失败'
  end

  def test_manager_success_with_broken_flutter_fails_recheck_without_retry
    output, result = dispatch(env: { 'JOBS_TEST_POST_FLUTTER_CODE' => '43' })
    assert_equal 43, result.exitstatus, output
    assert_equal ['manager', 'flutter|--version --machine'], trace
    assert_includes output, '复检失败'
  end

  def test_manager_success_with_broken_dart_fails_recheck_without_retry
    output, result = dispatch(env: { 'JOBS_TEST_POST_DART_CODE' => '44' })
    assert_equal 44, result.exitstatus, output
    assert_equal ['manager', 'flutter|--version --machine', 'dart|--version'], trace
    assert_includes output, '复检失败'
  end

  def test_pub_get_failure_is_not_masked_or_retried
    bind_sdk
    output, result = dispatch(env: { 'JOBS_TEST_PUB_GET_CODE' => '45' })
    assert_equal 45, result.exitstatus, output
    assert_equal ['flutter|--version --machine', 'dart|--version', 'flutter|pub get'], trace
    assert_includes output, 'flutter pub get 失败'
  end

  def test_parent_sdk_and_global_sdk_cannot_replace_target_binding
    File.write(File.join(@root, '.fvmrc'), '{"flutter":"3.29.3"}')
    FileUtils.mkdir_p(File.join(@root, '.fvm'))
    File.symlink(@sdk, File.join(@root, '.fvm/flutter_sdk'))
    output, result = dispatch(env: { 'JOBS_TEST_MANAGER_MODE' => 'noop' })
    refute result.success?, output
    assert_equal ['manager'], trace
    assert_safe_paths
  end

  def test_non_tty_refuses_before_sdk_manager_or_log_writes
    output, result = Open3.capture2e(@env, '/bin/zsh', '-f', File.join(@tools, 'DispatchFlutterTools.zsh'), 'pub-get', @project)
    refute result.success?, output
    assert_empty trace
    assert_empty Dir.children(File.join(@root, 'tmp'))
    refute File.exist?(File.join(@project, '.fvmrc'))
  end

  def test_confirmation_eof_stops_before_sdk_preparation
    output, result = invoke_tty(File.join(@tools, 'DispatchFlutterTools.zsh'), 'pub-get', @project, input: "\u0004")
    refute result.success?, output
    assert_empty trace
    assert_empty Dir.children(File.join(@root, 'tmp'))
  end

  def test_read_only_check_with_missing_sdk_never_starts_preparation
    output, result = inspect_check
    refute result.success?, output
    assert_empty trace
    assert_empty Dir.children(File.join(@root, 'tmp'))
    assert_includes output, '只读'
  end

  def test_read_only_check_does_not_invoke_even_a_broken_executable_sdk
    bind_sdk
    output, result = inspect_check('JOBS_TEST_INITIAL_FLUTTER_CODE' => '41')
    assert result.success?, output
    assert_empty trace
    assert_empty Dir.children(File.join(@root, 'tmp'))
    assert_includes output, '计划：flutter pub get'
  end

  def test_other_actions_still_stop_at_existing_fvm_gate
    output, result = Open3.capture2e(@env, '/bin/zsh', '-f', File.join(@tools, 'DispatchFlutterTools.zsh'), 'codegen', @project)
    refute result.success?, output
    assert_empty trace
    assert_includes output, '尚未通过 FVM 绑定 SDK'
  end

  def test_real_manager_cancellation_paths_distinguish_standalone_and_chained_calls
    source = File.read(JobsSourceLayout.file(File.join(TOOLS, '【MacOS】ManageFlutterVersion.zsh/【MacOS】ManageFlutterVersion.zsh'))).sub(/^main "\$@"\s*\z/, '')
    cancellation_script = File.join(@root, 'manager-cancellation.zsh')
    write_executable(File.join(@bin, 'cancel-fzf'), 'exit 130')
    File.write(cancellation_script, source + <<~'ZSH')
      LOG_FILE="$JOBS_TEST_ROOT/manager-cancel.log"
      FM_RUN_DIR="$JOBS_TEST_ROOT/tmp"
      FM_PROJECT="$JOBS_TEST_ROOT"
      FM_FZF="$JOBS_TEST_ROOT/bin/cancel-fzf"
      case "$1" in
        dependency) fm_confirm_dependency fixture ;;
        channel) FM_ONLINE=1; fm_select_version ;;
        version)
          FM_ONLINE=0
          print -r -- $'3.29.3\tfixture' > "$FM_RUN_DIR/cached.tsv"
          fm_select_version
          ;;
        final) fm_confirm_project_change ;;
      esac
      print unexpected-business
    ZSH
    %w[dependency channel version final].each do |stage|
      { '0' => 0, '1' => 130 }.each do |chained, expected|
        output, result = Open3.capture2e(@env.merge('JOBS_FLUTTER_VERSION_CHAINED' => chained), '/bin/zsh', '-f', cancellation_script, stage, stdin_data: "cancel\n")
        assert_equal expected, result.exitstatus, "#{stage}, chained=#{chained}\n#{output}"
        assert_includes output, '已取消'
        refute_includes output, 'unexpected-business'
      end
    end
  end

  private

  def write_executable(path, body)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "#!/bin/zsh\n#{body}\n")
    FileUtils.chmod(0o755, path)
  end

  def write_sdk(directory)
    write_executable(File.join(directory, 'bin/flutter'), <<~'ZSH')
      print -r -- "flutter|${(j: :)@}" >> "$JOBS_TEST_TRACE"
      if [[ "$1" == --version ]]; then
        if [[ -f "$JOBS_TEST_ROOT/manager-ready" ]]; then
          result="${JOBS_TEST_POST_FLUTTER_CODE:-0}"
        else
          result="${JOBS_TEST_INITIAL_FLUTTER_CODE:-0}"
        fi
        (( result == 0 )) || { print -u2 "Bad CPU type in executable"; exit "$result"; }
        print -r -- '{"frameworkVersion":"3.29.3","dartSdkVersion":"3.7.2"}'
      elif [[ "$1" == pub && "$2" == get ]]; then
        exit "${JOBS_TEST_PUB_GET_CODE:-0}"
      else
        exit 98
      fi
    ZSH
    write_executable(File.join(directory, 'bin/cache/dart-sdk/bin/dart'), <<~'ZSH')
      print -r -- "dart|${(j: :)@}" >> "$JOBS_TEST_TRACE"
      if [[ -f "$JOBS_TEST_ROOT/manager-ready" ]]; then
        result="${JOBS_TEST_POST_DART_CODE:-0}"
      else
        result="${JOBS_TEST_INITIAL_DART_CODE:-0}"
      fi
      (( result == 0 )) || exit "$result"
      print -r -- 'Dart SDK version: 3.7.2'
    ZSH
  end

  def write_manager
    File.write(File.join(@tools, 'ManageFlutterVersion.zsh'), <<~'ZSH')
      #!/bin/zsh
      print -r -- manager >> "$JOBS_TEST_TRACE"
      printf '%s\0' "$@" "$JOBS_FLUTTER_VERSION_CHAINED" > "$JOBS_TEST_ROOT/manager-arguments"
      [[ "$#" == 2 && "$1" == --project && -d "$2" ]] || exit 96
      [[ "${JOBS_TEST_MANAGER_CODE:-0}" == 0 ]] || exit "$JOBS_TEST_MANAGER_CODE"
      [[ "${JOBS_TEST_MANAGER_MODE:-prepare}" != noop ]] || exit 0
      /bin/mkdir -p "$2/.fvm"
      [[ ! -L "$2/.fvm/flutter_sdk" ]] || /bin/rm -f "$2/.fvm/flutter_sdk"
      [[ -d "$2/.fvm/flutter_sdk" ]] || /bin/ln -s "$JOBS_TEST_SDK" "$2/.fvm/flutter_sdk"
      print -r -- '{"flutter":"3.29.3"}' > "$2/.fvmrc"
      /usr/bin/touch "$JOBS_TEST_ROOT/manager-ready"
      [[ "${JOBS_TEST_MANAGER_MODE:-prepare}" != cancel-after-prepare ]] || exit 130
    ZSH
  end

  def bind_sdk(legacy: false)
    FileUtils.mkdir_p(File.join(@project, '.fvm'))
    if legacy
      File.write(File.join(@project, '.fvm/fvm_config.json'), '{"flutterSdkVersion":"3.29.3"}')
    else
      File.write(File.join(@project, '.fvmrc'), '{"flutter":"3.29.3"}')
    end
    File.symlink(@sdk, File.join(@project, '.fvm/flutter_sdk'))
  end

  def write_environment(platform: 'MacOS')
    FileUtils.mkdir_p(File.join(@project, '.jobs'))
    File.write(File.join(@project, '.jobs/flutter-environment.json'), JSON.generate(
      Platform: platform, FlutterMode: 'system', FlutterPath: File.join(@sdk, 'bin/flutter'), JavaMode: 'none', JavaHome: ''
    ))
  end

  def trace
    File.exist?(@trace) ? File.readlines(@trace, chomp: true) : []
  end

  def assert_safe_paths
    refute File.exist?(File.join(@project, 'NEVER'))
    refute File.exist?(File.join(@root, 'NEVER'))
    refute trace.any? { |line| line.start_with?('global-') }
  end

  def dispatch(env: {})
    invoke_tty(File.join(@tools, 'DispatchFlutterTools.zsh'), 'pub-get', @project, env: env)
  end

  def inspect_check(env = {})
    Open3.capture2e(@env.merge(env), '/bin/zsh', '-f', File.join(@tools, 'InspectFlutterProject.zsh'), '--check', @project, 'pub-get')
  end

  def invoke_tty(*arguments, env: {}, input: "\n")
    output = +''
    process_status = nil
    PTY.spawn(@env.merge(env), '/bin/zsh', '-f', *arguments) do |reader, writer, pid|
      begin
        Timeout.timeout(15) do
          writer.write(input)
          writer.flush
          begin
            loop { output << reader.readpartial(4096) }
          rescue Errno::EIO, EOFError
            # Darwin 在 PTY 子进程退出后以 EIO 表示流结束。
          end
          _, process_status = Process.wait2(pid)
        end
      rescue Timeout::Error
        Process.kill('TERM', pid) rescue Errno::ESRCH
        Process.wait(pid) rescue Errno::ECHILD
        flunk "交互夹具超时：#{output.force_encoding('UTF-8')}"
      end
    end
    [output.force_encoding('UTF-8'), process_status]
  end
end
