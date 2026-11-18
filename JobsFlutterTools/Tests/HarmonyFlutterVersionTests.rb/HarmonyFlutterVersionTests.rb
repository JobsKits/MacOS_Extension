# frozen_string_literal: true
# 真实 zsh / JXA 隔离回归；Git、FVM、Homebrew、SDK 都是临时假命令，不安装真实工具。

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
require 'json'
require 'minitest/autorun'
require 'open3'
require 'pty'
require 'tmpdir'
require 'shellwords'

require_relative '../../../Tests/SourceLayoutHelper.rb/SourceLayoutHelper'

class HarmonyFlutterVersionTests < Minitest::Test
  SCRIPT = File.expand_path('../Scripts/Tools/【MacOS】ManageHarmonyFlutterVersion.zsh/【MacOS】ManageHarmonyFlutterVersion.zsh', File.dirname(__dir__))
  SHA = 'b' * 40
  TAG = '3.41.10-ohos-1.0.1'
  REPO = 'https://gitcode.com/CPF-Flutter/flutter_flutter.git'

  def setup
    @root = File.realpath(Dir.mktmpdir('jobs-harmony-sdk-'))
    @project = File.join(@root, "项目 空格 ' $(touch SHOULD_NOT_EXIST)")
    @bin = File.join(@root, 'bin')
    @run = File.join(@root, 'run')
    @cache = File.join(@root, 'Library/Caches/JobsFlutter/fvm/harmony')
    @trace = File.join(@root, 'trace')
    FileUtils.mkdir_p([@project, @bin, @run])
    @script = File.join(@root, 'ManageHarmonyFlutterVersion.fixture.zsh')
    fixture = File.read(SCRIPT).sub('FH_TOOLS="$(jobs_layout_directory "${(%):-%x}")"', "FH_TOOLS=#{JobsSourceLayout.directory(SCRIPT).shellescape}")
    fixture = fixture.sub(/^main "\$@"\s*\z/, "jobs_flutter_route_prepare() { return 0; }\nfh_verify_project_constraints() { print VERIFIED_CONSTRAINTS >> \"$FAKE_TRACE\"; return ${FAKE_CONSTRAINT_EXIT:-0}; }\nmain \"$@\"\n")
    File.write(@script, fixture)
    File.write(File.join(@project, 'pubspec.yaml'), "name: example\ndependencies:\n  flutter:\n    sdk: flutter\n")
    @environment = {
      'HOME' => @root, 'TMPDIR' => @run + '/', 'PATH' => "#{@bin}:/usr/bin:/bin",
      'NO_COLOR' => '1', 'TERM' => 'dumb', 'FAKE_ROOT' => @root, 'FAKE_BIN' => @bin,
      'FAKE_PROJECT' => @project, 'FAKE_TRACE' => @trace, 'FAKE_SHA' => SHA, 'FAKE_REPO' => REPO
    }
    write_mock('git', <<~'ZSH')
      print -r -- "git|${(j: :)@}" >> "$FAKE_TRACE"
      while [[ "$1" == -c ]]; do shift 2; done
      if [[ "$1" == ls-remote ]]; then
        [[ "${FAKE_OFFLINE:-0}" != 1 ]] || exit 23
        print -- "${FAKE_SHA}\trefs/tags/3.41.10-ohos-1.0.1"
        print -- 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\trefs/tags/3.47.7+ohos-0.0.1-pre'
        print -- 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\trefs/tags/3.35.7+ohos-1.0.5'
        print -- 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\trefs/tags/evil;touch injected'
        exit 0
      fi
      if [[ "$1" == init ]]; then
        /bin/mkdir -p "$2/.git"
        exit 0
      fi
      if [[ "$1" == clone ]]; then
        [[ "${FAKE_CLONE_FAIL:-0}" != 1 ]] || exit 41
        local target="${@[-1]}"
        /bin/mkdir -p "$target/.git" "$target/bin"
        print -r -- "$FAKE_SHA" > "$target/.commit"
        /bin/cp "$FAKE_BIN/.flutter-template" "$target/bin/flutter"
        /bin/chmod +x "$target/bin/flutter"
        exit 0
      fi
      if [[ "$1" == -C ]]; then
        local target="$2"; shift 2
        while [[ "$1" == -c ]]; do shift 2; done
        case "$1" in
          fetch)
            [[ "${FAKE_CLONE_FAIL:-0}" != 1 ]] || { print -u2 'Permission denied: fixture download target'; exit 41; }
            /bin/mkdir -p "$target/bin"
            print -r -- "$FAKE_SHA" > "$target/.commit"
            /bin/cp "$FAKE_BIN/.flutter-template" "$target/bin/flutter"
            /bin/chmod +x "$target/bin/flutter"
            exit 0 ;;
          checkout) exit 0 ;;
          rev-parse) /bin/cat "$target/.commit" ;;
          remote) print -r -- "${FAKE_WRONG_SOURCE:-$FAKE_REPO}" ;;
          status) [[ "${FAKE_DIRTY:-0}" != 1 ]] || print -r -- ' M packages/flutter/lib/widget.dart' ;;
          *) exit 3 ;;
        esac
        exit 0
      fi
      exit 4
    ZSH
    write_mock('.flutter-template', <<~'ZSH')
      print -r -- "sdk|${(j: :)@}" >> "$FAKE_TRACE"
      if [[ "$1" == --version ]]; then
        [[ "${FAKE_SDK_FAIL:-0}" != 1 ]] || { print -u2 'Bad CPU type in executable'; exit 42; }
        print -r -- 'Flutter OH fixture'
      elif [[ "$1" == build && "$2" == -h ]]; then
        [[ "${FAKE_NO_HAP:-0}" == 1 ]] || print -r -- 'hap'
      else
        exit 5
      fi
    ZSH
    write_mock('fvm', <<~'ZSH')
      print -r -- "fvm|${(j: :)@}" >> "$FAKE_TRACE"
      case "$1" in
        --version) print -r -- '4.0.0' ;;
        use)
          if [[ "$2" == --help ]]; then print -r -- '--skip-pub-get --skip-setup'; exit 0; fi
          [[ "$PWD" != "$FAKE_PROJECT" ]] || exit 80
          /bin/mkdir -p .fvm/versions .vscode
          /bin/ln -sfn "$FVM_CACHE_PATH/versions/${2}" .fvm/flutter_sdk
          /bin/ln -sfn "$FVM_CACHE_PATH/versions/${2}" ".fvm/versions/$2"
          print -r -- "{\"flutter\":\"$2\"}" > .fvmrc
          print -r -- 'shadow IDE only' > .vscode/settings.json
          print -r -- 'shadow ignore only' > .gitignore
          if [[ "${FAKE_CONCURRENT:-0}" == 1 ]]; then
            print -r -- '{"flutter":"external-new-value"}' > "$FAKE_PROJECT/.fvmrc"
          fi
          [[ "${FAKE_USE_FAIL:-0}" != 1 ]] || exit 43
          [[ "${FAKE_WRONG_LINK:-0}" != 1 ]] || /bin/ln -sfn /tmp .fvm/flutter_sdk
          ;;
        *) exit 6 ;;
      esac
    ZSH
    JobsSourceLayout.copy(File.join(@bin, 'fvm'), File.join(@bin, '.fvm-template'))
    write_mock('brew', <<~'ZSH')
      print -r -- "brew|${(j: :)@}" >> "$FAKE_TRACE"
      case "$1" in
        --prefix) print -r -- "$FAKE_ROOT" ;;
        install)
          /bin/cp "$FAKE_BIN/.fvm-template" "$FAKE_BIN/fvm"
          /bin/chmod +x "$FAKE_BIN/fvm"
          ;;
        *) exit 7 ;;
      esac
    ZSH
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def test_check_is_local_read_only_and_never_calls_tools
    write_original_binding
    before = tree(@project)
    output, status = invoke('--check', input: '')
    assert status.success?, output
    assert_includes output, '当前绑定：3.35.7'
    assert_includes output, '本机没有带来源记录'
    assert_equal before, tree(@project)
    assert_empty Dir.children(@run)
    refute File.exist?(@trace)
  end

  def test_intro_cancel_and_eof_do_not_query_or_install
    ["cancel\n", ''].each do |input|
      output, status = invoke(input: input)
      refute status.success?, output
      refute File.exist?(@trace)
      assert_empty Dir.children(@run)
    end
  end

  def test_final_cancel_never_runs_fvm_brew_or_changes_project
    before = tree(@project)
    output, status = invoke(input: "\n\nNO\n")
    assert_equal 130, status.exitstatus, output
    assert_equal before, tree(@project)
    assert_includes trace, 'git|'
    refute_match(/fvm\||brew\||git\|clone/, trace)
    refute_includes output, 'evil;touch'
  end

  def test_success_from_no_fvm_project_uses_custom_cache_and_preserves_ide
    FileUtils.mkdir_p(File.join(@project, '.vscode'))
    File.write(File.join(@project, '.vscode/settings.json'), '{"fontSize":15}')
    File.write(File.join(@project, '.gitignore'), "build/\n")
    output, status = invoke
    assert status.success?, output
    config = JSON.parse(File.read(File.join(@project, '.fvmrc')))
    assert_equal "custom_jobs_ohos_#{SHA}", config['flutter']
    assert_equal @cache, config['cachePath']
    assert_equal REPO, config['flutterUrl']
    assert_equal "build/\n", File.read(File.join(@project, '.gitignore'))
    assert_equal '{"fontSize":15}', File.read(File.join(@project, '.vscode/settings.json'))
    assert_equal sdk_path, File.realpath(File.join(@project, '.fvm/flutter_sdk'))
    assert_equal sdk_path, File.realpath(File.join(@project, ".fvm/versions/custom_jobs_ohos_#{SHA}"))
    assert_equal TAG, JSON.parse(File.read(File.join(sdk_path, '.jobs-harmony-source.json')))['tag']
    assert_includes trace, '--skip-setup --skip-pub-get'
    refute_match(/fvm\|global|fvm\|fork|pub get|\.zshrc|\.zprofile/, trace)
    refute File.exist?(File.join(@project, '.jobs-harmony-fvm.lock'))
    refute File.exist?(File.join(@project, 'SHOULD_NOT_EXIST'))
  end

  def test_chained_run_chooses_latest_stable_without_reading_another_confirmation
    output, status = invoke('--prepare-for-run', input: '')
    assert status.success?, output
    assert_includes output, "自动选择清单内最新正式版本：#{TAG}"
    assert_equal "custom_jobs_ohos_#{SHA}", JSON.parse(File.read(File.join(@project, '.fvmrc')))['flutter']
    assert_equal sdk_path, File.realpath(File.join(@project, '.fvm/flutter_sdk'))
    refute_includes output, '输入 YES 确认'
    refute_match(/fvm\|global|pub get/, trace)
  end

  def test_chained_run_failed_download_preserves_original_binding
    write_original_binding
    before = tree(@project)
    output, status = invoke('--prepare-for-run', input: '', environment: {'FAKE_CLONE_FAIL' => '1'})
    refute status.success?, output
    assert_equal before, tree(@project)
    refute_match(/^fvm\|use custom_jobs_ohos_/, trace)
  end

  def test_chained_run_incompatible_candidate_cannot_publish_binding
    write_original_binding
    before = tree(@project)
    output, status = invoke('--prepare-for-run', input: '', environment: {'FAKE_CONSTRAINT_EXIT' => '65'})
    assert_equal 65, status.exitstatus, output
    assert_equal before, tree(@project)
    assert_includes trace, 'VERIFIED_CONSTRAINTS'
    refute_match(/^fvm\|use custom_jobs_ohos_/, trace)
  end

  def test_real_dart_constraint_parser_rejects_low_versions_and_unparseable_data
    sdk, dart, config = local_constraints_sdk
    validator = File.join(@root, 'constraints.dart')
    File.write(validator, File.read(SCRIPT).match(/<<'DART'\n(.*?)\nDART/m)[1])
    specification = File.join(@root, 'constraints-pubspec.yaml')
    metadata = File.join(@root, 'sdk-version.json')
    cases = [
      ["environment:\n  sdk: '>=3.10.0 <4.0.0'\n  flutter: '>=3.38.0'\n", {'frameworkVersion' => '3.41.10+ohos-1.0.1', 'dartSdkVersion' => '3.11.0'}, 0],
      ["environment:\n  sdk: '>=3.13.0 <4.0.0'\n", {'dartSdkVersion' => '3.11.0'}, 65],
      ["environment:\n  flutter: '>=3.47.0'\n", {'frameworkVersion' => '3.41.10'}, 65],
      ["environment:\n  sdk: '^3.11.0'\n  flutter: '^3.41.0'\n", {'frameworkVersion' => '3.41.10', 'dartSdkVersion' => '3.11.0'}, 0],
      ["environment:\n  sdk: 'not a constraint'\n", {'dartSdkVersion' => '3.11.0'}, 66],
      ["environment:\n  sdk: '>=3.10.0'\n", {}, 66],
      ["environment: 17\n", {}, 66]
    ]
    cases.each do |yaml, version, expected|
      File.write(specification, yaml)
      File.write(metadata, JSON.generate(version))
      output, result = Open3.capture2e(dart, "--packages=#{config}", validator, specification, metadata)
      assert_equal expected, result.exitstatus, output
    end
    File.write(specification, "environment:\n  sdk: '>=3.0.0 <4.0.0'\n")
    JobsSourceLayout.copy(File.join(sdk, 'bin/cache/flutter.version.json'), metadata)
    head, git_result = Open3.capture2('/usr/bin/git', '-C', sdk, 'rev-parse', 'HEAD')
    assert git_result.success?
    output, result = Open3.capture2e(dart, "--packages=#{config}", validator, specification, metadata, head.strip)
    assert_equal 0, result.exitstatus, output
    output, result = Open3.capture2e(dart, "--packages=#{config}", validator, specification, metadata, '0' * 40)
    assert_equal 66, result.exitstatus, output
  end

  def test_verify_current_sdk_is_local_and_does_not_bind_or_query_remote
    sdk, = local_constraints_sdk
    File.open(File.join(@project, 'pubspec.yaml'), 'a') { |file| file.puts "environment:\n  sdk: '>=3.0.0 <4.0.0'" }
    before = tree(@project)
    output, result = Open3.capture2e(@environment, '/bin/zsh', SCRIPT, '--project', @project, '--verify-sdk', sdk, stdin_data: '')
    assert result.success?, output
    assert_includes output, '已满足当前 pubspec'
    assert_equal before, tree(@project)
    assert_empty trace
  end

  def test_single_acquisition_attempt_has_a_real_timeout
    library = File.read(SCRIPT).sub(/^main "\$@"\s*\z/, '')
    output, result = Open3.capture2e(@environment, '/bin/zsh', '-f', '-c', library + "\nfh_run_bounded 1 /bin/sleep 30\n")
    assert_equal 124, result.exitstatus, output
  end

  def test_success_preserves_unknown_config_and_existing_preferences
    write_original_binding
    output, status = invoke
    assert status.success?, output
    config = JSON.parse(File.read(File.join(@project, '.fvmrc')))
    assert_equal true, config['updateVscodeSettings']
    assert_equal({ 'custom' => ['keep'] }, config['extra'])
    assert_equal 'original metadata', File.read(File.join(@project, '.fvm/note'))
  end

  def test_missing_fvm_install_is_after_explicit_confirmation
    FileUtils.rm(File.join(@bin, 'fvm'))
    output, status = invoke(input: "\n\nNO\n")
    refute status.success?, output
    refute_match(/brew\|install/, trace)
    output, status = invoke
    assert status.success?, output
    assert_includes trace, 'brew|install btwld/fvm/fvm'
    assert_operator output.index('来源地址：https://github.com/btwld/homebrew-fvm'), :<, output.index('✔ 项目已绑定')
  end

  def test_clone_and_sdk_failures_leave_original_binding_byte_identical
    write_original_binding
    before = tree(@project)
    %w[FAKE_CLONE_FAIL FAKE_SDK_FAIL].each do |flag|
      output, status = invoke(environment: { flag => '1' })
      refute status.success?, output
      assert_equal before, tree(@project)
      refute File.exist?(File.join(@project, '.jobs-harmony-fvm.lock'))
    end
  end

  def test_fvm_failure_or_wrong_link_only_changes_shadow
    write_original_binding
    before = tree(@project)
    %w[FAKE_USE_FAIL FAKE_WRONG_LINK].each do |flag|
      output, status = invoke(environment: { flag => '1' })
      refute status.success?, output
      assert_equal before, tree(@project)
    end
  end

  def test_concurrent_project_edit_is_preserved_and_publish_is_cancelled
    write_original_binding
    original_link = File.readlink(File.join(@project, '.fvm/flutter_sdk'))
    output, status = invoke(environment: { 'FAKE_CONCURRENT' => '1' })
    refute status.success?, output
    assert_includes output, '准备期间项目绑定已被修改'
    assert_equal 'external-new-value', JSON.parse(File.read(File.join(@project, '.fvmrc')))['flutter']
    assert_equal original_link, File.readlink(File.join(@project, '.fvm/flutter_sdk'))
  end

  def test_existing_project_lock_stops_without_fvm_or_download
    FileUtils.mkdir(File.join(@project, '.jobs-harmony-fvm.lock'))
    output, status = invoke
    refute status.success?, output
    assert_includes output, '操作锁'
    refute_match(/fvm\||brew\||git\|clone/, trace)
    assert File.directory?(File.join(@project, '.jobs-harmony-fvm.lock'))
  end

  def test_cache_symlink_is_rejected_before_download
    FileUtils.mkdir_p(File.join(@root, 'elsewhere'))
    File.symlink(File.join(@root, 'elsewhere'), File.join(@root, 'Library'))
    output, status = invoke('--check', input: '')
    assert status.success?, output
    refute File.exist?(@trace)
    assert_empty Dir.children(File.join(@root, 'elsewhere'))
    output, status = invoke
    refute status.success?, output
    assert_includes output, '缓存路径不是普通目录'
    refute_includes trace, 'git|clone'
    assert_empty Dir.children(File.join(@root, 'elsewhere'))
  end

  def test_offline_uses_recorded_local_cache_and_rejects_wrong_source
    create_cached_sdk
    output, status = invoke(environment: { 'FAKE_OFFLINE' => '1' })
    assert status.success?, output
    assert_includes output, '仅提供带来源记录的本机缓存'
    refute_includes trace, 'git|clone'
    output, status = invoke(environment: { 'FAKE_OFFLINE' => '1', 'FAKE_WRONG_SOURCE' => 'https://example.invalid/fork.git' })
    refute status.success?, output
    assert_includes output, '缓存来源 / commit / 源码状态不符'
  end

  def test_parser_reuses_menu_detector_for_flow_yaml_and_rejects_comment_only
    File.write(File.join(@project, 'pubspec.yaml'), "name: sample\ndependencies: {flutter: {sdk: flutter}}\n")
    output, status = invoke('--check', input: '')
    assert status.success?, output
    File.write(File.join(@project, 'pubspec.yaml'), "name: sample\n# dependencies:\n#   flutter:\n#     sdk: flutter\n")
    output, status = invoke('--check', input: '')
    refute status.success?, output
    refute File.exist?(@trace)
  end

  def test_symlinked_project_config_and_real_sdk_directory_are_preserved
    external = File.join(@root, 'external.json')
    File.write(external, '{}')
    File.symlink(external, File.join(@project, '.fvmrc'))
    output, status = invoke('--check', input: '')
    refute status.success?, output
    assert_equal '{}', File.read(external)
    FileUtils.rm(File.join(@project, '.fvmrc'))
    FileUtils.mkdir_p(File.join(@project, '.fvm/flutter_sdk'))
    output, status = invoke('--check', input: '')
    refute status.success?, output
    assert_includes output, '真实目录'
  end

  def test_fzf_selects_first_row_and_escape_cancels_without_tools
    write_mock('fzf', <<~'ZSH')
      print -r -- 'fzf|select' >> "$FAKE_TRACE"
      [[ "${FAKE_FZF_CANCEL:-0}" != 1 ]] || exit 130
      /usr/bin/head -n 1
    ZSH
    output, status = invoke_tty("\nYES\n")
    assert status.success?, output
    assert_includes trace, 'fzf|select'
    assert_includes output, "✔ 项目已绑定 Flutter OH #{TAG}"
    FileUtils.rm(@trace)
    output, status = invoke_tty("\n", 'FAKE_FZF_CANCEL' => '1')
    assert_equal 130, status.exitstatus, output
    refute_match(/fvm\||brew\||git\|clone/, trace)
  end

  def test_failed_publish_restores_original_file_identity
    write_original_binding
    identity = File.stat(File.join(@project, '.fvmrc')).ino
    original = File.read(File.join(@project, '.fvmrc'))
    output, status = invoke_recovery(false)
    assert_equal 27, status.exitstatus, output
    assert_equal original, File.read(File.join(@project, '.fvmrc'))
    assert_equal identity, File.stat(File.join(@project, '.fvmrc')).ino
    assert_includes output, '原项目绑定已恢复'
  end

  def test_rollback_conflict_preserves_external_file_and_backup
    write_original_binding
    output, status = invoke_recovery(true)
    refute status.success?, output
    assert_includes output, '恢复发现并发修改'
    assert_equal "external after publish\n", File.read(File.join(@project, '.fvmrc'))
    assert File.file?(File.join(@root, 'recovery/displaced/.fvmrc'))
  end

  def test_control_character_path_is_rejected_without_changes
    bad = File.join(@root, "bad\nproject")
    FileUtils.mkdir(bad)
    output, status = Open3.capture2e(@environment, '/bin/zsh', SCRIPT, '--project', bad, '--check')
    refute status.success?, output
    assert_includes output, '路径含控制字符'
    refute File.exist?(@trace)
  end

  private

  def local_constraints_sdk
    flutter = ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).map { |path| File.join(path, 'flutter') }.find { |path| File.executable?(path) }
    sdk = flutter && File.dirname(File.dirname(File.realpath(flutter)))
    dart = sdk && File.join(sdk, 'bin/cache/dart-sdk/bin/dart')
    config = sdk && File.join(sdk, 'packages/flutter_tools/.dart_tool/package_config.json')
    skip '未找到可离线运行的本机 Flutter Dart / package_config' unless dart && File.executable?(dart) && File.file?(config)
    [sdk, dart, config]
  end

  def invoke(*arguments, input: "\n\nYES\n", environment: {})
    Open3.capture2e(@environment.merge(environment), '/bin/zsh', @script, '--project', @project, *arguments, stdin_data: input)
  end

  def invoke_tty(input, environment = {})
    output = +''
    status = nil
    PTY.spawn(@environment.merge(environment), '/bin/zsh', @script, '--project', @project) do |reader, writer, pid|
      writer.write(input)
      writer.flush
      begin
        loop { output << reader.readpartial(4096) }
      rescue Errno::EIO, EOFError
        # macOS PTY 在子进程退出时返回 EIO。
      end
      Process.wait(pid)
      status = $CHILD_STATUS || $?
    end
    [output.force_encoding(Encoding::UTF_8), status]
  end

  def invoke_recovery(concurrent)
    source = File.read(SCRIPT).sub(/^main "\$@"\s*\z/, '')
    source += <<~'ZSH'
      FH_PROJECT="$FAKE_PROJECT"
      FH_RUN="$FAKE_ROOT/recovery"
      /bin/mkdir -p "$FH_RUN/before" "$FH_RUN/displaced" "$FH_RUN/produced"
      FH_LOG="$FH_RUN/action.log"
      /bin/cp "$FH_PROJECT/.fvmrc" "$FH_RUN/before/.fvmrc"
      /bin/mv "$FH_PROJECT/.fvmrc" "$FH_RUN/displaced/.fvmrc"
      print -r -- 'produced by this run' > "$FH_PROJECT/.fvmrc"
      FH_EXPECTED_CONFIG="$(fh_data fingerprint "$FH_PROJECT/.fvmrc")"
      FH_CHANGED=(.fvmrc)
      FH_MUTATED=1
      [[ "$FAKE_ROLLBACK_CONCURRENT" != 1 ]] || print -r -- 'external after publish' > "$FH_PROJECT/.fvmrc"
      fh_finish 27
    ZSH
    Open3.capture2e(@environment.merge('FAKE_ROLLBACK_CONCURRENT' => concurrent ? '1' : '0'), '/bin/zsh', '-c', JobsSourceLayout.shell(source))
  end

  def write_mock(name, body)
    path = File.join(@bin, name)
    File.write(path, "#!/bin/zsh\n#{body}")
    FileUtils.chmod(0o755, path)
  end

  def trace
    File.exist?(@trace) ? File.read(@trace) : ''
  end

  def sdk_path
    File.join(@cache, "versions/custom_jobs_ohos_#{SHA}")
  end

  def create_cached_sdk
    FileUtils.mkdir_p([File.join(sdk_path, '.git'), File.join(sdk_path, 'bin')])
    File.write(File.join(sdk_path, '.commit'), SHA)
    JobsSourceLayout.copy(File.join(@bin, '.flutter-template'), File.join(sdk_path, 'bin/flutter'))
    File.write(File.join(sdk_path, '.jobs-harmony-source.json'), JSON.generate({ tag: TAG, commit: SHA, repo: REPO }))
  end

  def write_original_binding
    old_sdk = File.join(@root, 'old sdk')
    FileUtils.mkdir_p([old_sdk, File.join(@project, '.fvm')])
    File.symlink(old_sdk, File.join(@project, '.fvm/flutter_sdk'))
    File.write(File.join(@project, '.fvm/note'), 'original metadata')
    File.write(File.join(@project, '.fvmrc'), JSON.generate({ flutter: '3.35.7', updateVscodeSettings: true, extra: { custom: ['keep'] } }))
  end

  def tree(root)
    Dir.glob(File.join(root, '**', '*'), File::FNM_DOTMATCH).reject { |p| %w[. ..].include?(File.basename(p)) }.sort.map do |path|
      [path.delete_prefix(root), File.symlink?(path) ? [:link, File.readlink(path)] : File.file?(path) ? [:file, File.binread(path)] : [:directory]]
    end
  end
end
