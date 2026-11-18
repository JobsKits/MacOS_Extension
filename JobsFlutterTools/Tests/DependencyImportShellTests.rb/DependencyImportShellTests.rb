# Created by Jobs on 2026年10月28日，星期三。
# 在临时目录验证拖入路径、快照识别、确认门禁及失败码，不操作真实项目。
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
require 'open3'
require 'tmpdir'
require 'shellwords'

require_relative '../../../Tests/SourceLayoutHelper.rb/SourceLayoutHelper'

class DependencyImportShellTests < Minitest::Test
  TOOLS = File.expand_path(ENV.fetch('JOBS_TEST_TOOLS_DIR', '../Scripts/Tools'), File.dirname(__dir__))
  SCRIPT = JobsSourceLayout.file(File.join(TOOLS, '【MacOS】ImportFlutterDependencies.zsh/【MacOS】ImportFlutterDependencies.zsh'))

  def run_functions(code, *arguments, input: '')
    Dir.mktmpdir('jobs-dependency-import-shell-') do |directory|
      fixture = File.join(directory, 'fixture.zsh')
      source = File.read(SCRIPT).sub(/^main "\$@"\s*\z/, '')
      File.write(fixture, source + "\nLOG_FILE=/dev/null\n" + code)
      Open3.capture2e({ 'NO_COLOR' => '1' }, '/bin/zsh', '-f', fixture, *arguments, stdin_data: input)
    end
  end

  def test_paths_are_single_data_values
    [
      ['/tmp/中文 文件夹', '/tmp/中文 文件夹'],
      ['/tmp/中文\\ 文件夹 ', '/tmp/中文 文件夹'],
      ["'/tmp/中文 文件夹' ", '/tmp/中文 文件夹'],
      ['"/tmp/中文 文件夹"', '/tmp/中文 文件夹'],
      ['~/Desktop/依赖', JobsSourceLayout.file(File.join(Dir.home, 'Desktop/依赖'))],
      ['/tmp/$(touch marker);`id`', '/tmp/$(touch marker);`id`']
    ].each do |raw, expected|
      output, result = run_functions('normalize_path_input "$1"; print -r -- "$REPLY"', raw)
      assert result.success?, output
      assert_equal expected, output.strip
    end
    output, result = run_functions('normalize_path_input "$1"', "'/tmp/one' '/tmp/two'")
    refute result.success?, output
    assert_includes output, '一次只接受一个目录'
  end

  def test_existing_paths_accept_pasted_boundary_whitespace_and_preserve_real_names
    Dir.mktmpdir('jobs-import-unicode-') do |directory|
      plain = File.join(directory, 'snapshot')
      spaced = File.join(directory, "依赖 目录")
      trailing = plain + ' '
      [plain, spaced, trailing].each { |path| Dir.mkdir(path) }
      [
        [plain + ' ', plain],
        [plain + "\u00a0", plain],
        ["\u202f#{plain}\u202f", plain],
        ["'#{spaced}'\u00a0", spaced],
        ["\"#{spaced}\"\u202f", spaced],
        [spaced + "\u00a0", spaced],
        [spaced + ' ', spaced],
        [trailing, trailing],
        [Shellwords.escape(trailing) + "\u00a0", trailing],
        [Shellwords.escape(trailing) + "\u00a0 ", trailing]
      ].each do |raw, expected|
        # plain+空格也是实际存在的目录，必须优先保留它的真实文件名。
        expected = trailing if raw == plain + ' '
        output, result = run_functions('normalize_path_input "$1"; print -r -- "$REPLY"', raw)
        assert result.success?, output
        assert_equal expected, output.delete_suffix("\n")
      end
    end
  end

  def test_intro_cancels_before_business
    ['', "no\n", " \n"].each do |input|
      output, result = run_functions('show_script_intro_and_wait; print unexpected-business', input: input)
      assert result.success?, output
      assert_includes output, '导入 Flutter 第三方依赖'
      refute_includes output, 'unexpected-business'
      refute_includes output, "\e["
    end
  end

  def test_bad_snapshot_reprompts_and_quoted_drag_is_accepted
    Dir.mktmpdir('中文 项目 ') do |project|
      File.write(File.join(project, 'pubspec.yaml'), "name: fixture\n")
      snapshot = File.join(project, '依赖 快照')
      Dir.mkdir(snapshot)
      Dir.mkdir(File.join(snapshot, 'packages'))
      File.write(File.join(snapshot, 'manifest.json'), '{}')
      output, result = run_functions(<<~'ZSH', project, input: "/tmp/not-an-export\n'#{snapshot}' \n")
        read_project_and_source "$1"
        print -r -- "PROJECT=$PROJECT_PATH"
        print -r -- "SOURCE=$SOURCE_PATH"
      ZSH
      assert result.success?, output
      assert_includes output, '不是依赖导出目录'
      assert_includes output, "PROJECT=#{File.realpath(project)}"
      assert_includes output, "SOURCE=#{File.realpath(snapshot)}"
    end
  end

  def test_empty_dependency_input_reprompts_until_a_directory_is_supplied
    Dir.mktmpdir('jobs-import-empty-') do |project|
      File.write(File.join(project, 'pubspec.yaml'), "name: fixture\n")
      snapshot = File.join(project, '依赖 快照')
      Dir.mkdir(snapshot)
      Dir.mkdir(File.join(snapshot, 'packages'))
      File.write(File.join(snapshot, 'manifest.json'), '{}')
      output, result = run_functions(<<~'ZSH', project, input: "\n\u00a0\n\u202f\n'#{snapshot}'\n")
        read_project_and_source "$1"
        print -r -- "SOURCE=$SOURCE_PATH"
      ZSH
      assert result.success?, output
      assert_equal 3, output.scan('尚未输入依赖目录').length, output
      assert_includes output, "SOURCE=#{File.realpath(snapshot)}"
    end
  end

  def test_empty_dependency_input_followed_by_eof_exits_without_business
    Dir.mktmpdir('jobs-import-eof-') do |project|
      File.write(File.join(project, 'pubspec.yaml'), "name: fixture\n")
      output, result = run_functions('read_project_and_source "$1"; print unexpected-business', project, input: "\n\n")
      assert result.success?, output
      assert_equal 2, output.scan('尚未输入依赖目录').length, output
      refute_includes output, 'unexpected-business'
    end
  end

  def test_symlink_snapshot_and_eof_do_not_continue
    Dir.mktmpdir('jobs-import-link-') do |directory|
      project = File.join(directory, 'project')
      snapshot = File.join(directory, 'snapshot')
      Dir.mkdir(project)
      Dir.mkdir(snapshot)
      Dir.mkdir(File.join(snapshot, 'packages'))
      File.write(File.join(snapshot, 'manifest.json'), '{}')
      File.write(File.join(project, 'pubspec.yaml'), "name: fixture\n")
      link = File.join(directory, 'link')
      File.symlink(snapshot, link)
      output, result = run_functions('read_project_and_source "$1"; print unexpected-business', project, input: "#{link}\n\n")
      assert result.success?, output
      assert_includes output, '不是依赖导出目录'
      refute_includes output, 'unexpected-business'
    end
  end

  def test_validation_failure_preserves_exit_and_never_confirms
    Dir.mktmpdir('jobs-import-engine-') do |engine_directory|
      File.write(File.join(engine_directory, 'ImportFlutterDependencies.dart'), 'print invalid-snapshot; exit 23')
      output, result = run_functions(<<~'ZSH', engine_directory)
        setopt PIPE_FAIL
        DART_EXECUTABLE=/bin/zsh
        SCRIPT_DIR="$1"
        validate_import
        print unexpected-confirmation
      ZSH
      assert_equal 23, result.exitstatus, output
      assert_includes output, 'invalid-snapshot'
      refute_includes output, 'unexpected-confirmation'
    end
  end

  def test_only_exact_yes_writes_and_failed_import_is_not_success
    ['', "\n", "yes\n", "NO\n"].each do |input|
      output, result = run_functions('DART_EXECUTABLE=/usr/bin/false; confirm_and_import', input: input)
      assert result.success?, output
      refute_includes output, '导入完成'
    end
    output, result = run_functions(<<~'ZSH', input: "YES\n")
      setopt PIPE_FAIL
      DART_EXECUTABLE=/usr/bin/false
      confirm_and_import
    ZSH
    refute result.success?, output
    assert_includes output, '导入未完成'
    refute_includes output, '✔ 导入完成'
  end
end
