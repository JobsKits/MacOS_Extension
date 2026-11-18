# frozen_string_literal: true
# Jobs：仅在临时 Git 夹具中验证回退范围与确认门禁。
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
require 'pty'
require 'timeout'

require_relative '../../../Tests/SourceLayoutHelper.rb/SourceLayoutHelper'

class GitRollbackCommandTests < Minitest::Test
  SCRIPT = File.expand_path('../Scripts/【MacOS】RollbackGitRepository.zsh/【MacOS】RollbackGitRepository.zsh', File.dirname(__dir__))

  def setup
    @root = Dir.mktmpdir('JobsGitRollback-')
    @repo = File.join(@root, '中文 空格 $() `id`')
    @library = File.join(@root, 'library.zsh')
    File.write(@library, File.read(SCRIPT).sub(/^main "\$@"\s*\z/, ''))
    git('init', '-q', @repo, directory: @root)
    git('config', 'user.name', 'Jobs Test')
    git('config', 'user.email', 'jobs-test@example.invalid')
    File.write(File.join(@repo, 'file'), 'base')
    git('add', 'file')
    git('commit', '-qm', 'base')
    @branch = git('branch', '--show-current').strip
    @base = git('rev-parse', 'HEAD').strip
    File.write(File.join(@repo, 'file'), 'next')
    git('commit', '-qam', 'next')
    @head = git('rev-parse', 'HEAD').strip
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def git(*args, directory: @repo)
    output, status = Open3.capture2e('git', '-C', directory, *args)
    raise output unless status.success?
    output
  end

  def shell(body, *arguments, env: {})
    prelude = 'source "$1"; setopt ERR_EXIT PIPE_FAIL; isolate_git_context; LOG_FILE="$3"; LOG_READY=1; PLAIN_OUTPUT=1; resolve_repository "$2"; '
    Open3.capture2e(env, '/bin/zsh', '-c', prelude + body, 'test', @library, @repo, File.join(@root, 'test.log'), *arguments)
  end

  def test_soft_preserves_index_and_worktree
    File.write(File.join(@repo, 'staged'), 'staged')
    git('add', 'staged')
    File.write(File.join(@repo, 'file'), 'dirty')
    index = File.binread(File.join(@repo, '.git/index'))
    output, status = shell('RESET_TARGET="$4"; reset_soft_to_target history', @base)
    assert status.success?, output
    assert_equal @base, git('rev-parse', 'HEAD').strip
    assert_equal index, File.binread(File.join(@repo, '.git/index'))
    assert_equal 'dirty', File.read(File.join(@repo, 'file'))
    assert_equal 'staged', File.read(File.join(@repo, 'staged'))
  end

  def test_non_ancestor_soft_target_is_refused
    git('checkout', '--orphan', 'other')
    git('commit', '-qm', 'unrelated')
    unrelated = git('rev-parse', 'HEAD').strip
    git('checkout', '-q', @branch)
    output, status = shell('RESET_TARGET="$4"; reset_soft_to_target unrelated', unrelated)
    refute status.success?, output
    assert_equal @head, git('rev-parse', 'HEAD').strip
  end

  def test_context_change_stops_reset
    output, status = shell('git -C "$REPO_ROOT" update-ref HEAD "$4"; RESET_TARGET="$4"; reset_soft_to_target changed', @base)
    refute status.success?, output
    assert_includes output, 'HEAD 已变化'
    assert_equal 'next', File.read(File.join(@repo, 'file'))
  end

  def test_hard_without_tty_is_refused
    File.write(File.join(@repo, 'file'), 'dirty')
    output, status = shell('confirm_and_reset_hard "$4" base', @base)
    refute status.success?, output
    assert_equal @head, git('rev-parse', 'HEAD').strip
    assert_equal 'dirty', File.read(File.join(@repo, 'file'))
  end

  def hard_in_terminal(answer)
    body = 'source "$1"; setopt ERR_EXIT PIPE_FAIL; isolate_git_context; LOG_FILE="$3"; LOG_READY=1; PLAIN_OUTPUT=1; resolve_repository "$2"; confirm_and_reset_hard "$4" base'
    output = +''
    child_status = nil
    PTY.spawn('/bin/zsh', '-c', body, 'test', @library, @repo, File.join(@root, 'hard.log'), @base) do |reader, writer, pid|
      Timeout.timeout(10) do
        sent = false
        begin
          loop do
            output << reader.readpartial(4096)
            if !sent && output.b.include?('输入 YES 执行'.b)
              writer.write("#{answer}\n")
              writer.flush
              sent = true
            end
          end
        rescue EOFError, Errno::EIO
          # PTY closes when child exits.
        end
        _, child_status = Process.wait2(pid)
      end
    end
    [output, child_status]
  end

  def test_hard_empty_confirmation_cancels
    File.write(File.join(@repo, 'file'), 'dirty')
    output, status = hard_in_terminal('')
    assert status.success?, output
    assert_equal @head, git('rev-parse', 'HEAD').strip
    assert_equal 'dirty', File.read(File.join(@repo, 'file'))
  end

  def test_hard_yes_applies_only_selected_worktree
    nested = File.join(@repo, 'nested')
    git('init', '-q', nested)
    File.write(File.join(nested, 'keep'), 'nested content')
    File.write(File.join(@repo, 'untracked'), 'untracked')
    File.write(File.join(@repo, 'file'), 'dirty')
    output, status = hard_in_terminal('YES')
    assert status.success?, output
    assert_equal @base, git('rev-parse', 'HEAD').strip
    assert_equal 'base', File.read(File.join(@repo, 'file'))
    assert_equal 'untracked', File.read(File.join(@repo, 'untracked'))
    assert_equal 'nested content', File.read(File.join(nested, 'keep'))
  end

  def test_selection_return_and_failure_never_reset
    bin = File.join(@root, 'bin')
    Dir.mkdir(bin)
    fzf = File.join(bin, 'fzf')
    File.write(fzf, "#!/bin/zsh\n[[ \"$1\" == --version ]] && { print 0.60; exit 0; }\nprint -r -- left\nexit 1\n")
    File.chmod(0o700, fzf)
    # A real TTY is necessary; the fake selector reports explicit Left even with no match.
    command = 'source "$1"; PATH="$2:$PATH"; choose_entry target 1 one two; result=$?; [[ $result == 10 ]]'
    output = +''
    status = nil
    PTY.spawn('/bin/zsh', '-c', JobsSourceLayout.shell(command), 'test', @library, bin) do |reader, _writer, pid|
      begin
        output << reader.read until reader.eof?
      rescue EOFError, Errno::EIO
      end
      _, status = Process.wait2(pid)
    end
    assert status.success?, output
    assert_equal @head, git('rev-parse', 'HEAD').strip
  end

  def test_individual_manager_forwards_only_rollback_feature
    feature = File.join(@root, 'MacOS@Extension', 'JobsGitRollback')
    aggregate = File.join(@root, 'MacOS@Extension', 'JobsProjectTools', 'Scripts')
    FileUtils.mkdir_p([feature, aggregate])
    entry = File.join(feature, 'Scripts/ManageExtension.zsh')
    original = File.expand_path('../Scripts/【MacOS】ManageExtension.zsh/【MacOS】ManageExtension.zsh', File.dirname(__dir__))
    FileUtils.mkdir_p(File.dirname(entry))
    JobsSourceLayout.copy(original, entry)
    target = File.join(aggregate, 'ManageProjectTools.zsh')
    FileUtils.mkdir_p(File.dirname(target))
    File.write(target, "print -r -- \"${(j:|:)@}\"\nexit 7\n")
    %w[install uninstall].each do |operation|
      output, status = Open3.capture2e('/bin/zsh', entry, '--action', operation, '--non-interactive')
      assert_includes output, "#{operation}|git-rollback"
      assert_equal 7, status.exitstatus
    end
  end
end
