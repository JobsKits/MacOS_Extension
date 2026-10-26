# frozen_string_literal: true
# Jobs：仅在临时 Git 夹具中验证回退范围与确认门禁。
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'pty'
require 'timeout'

class GitRollbackCommandTests < Minitest::Test
  SCRIPT = File.expand_path('../Scripts/RollbackGitRepository.zsh', __dir__)

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
    PTY.spawn('/bin/zsh', '-c', command, 'test', @library, bin) do |reader, _writer, pid|
      begin
        output << reader.read until reader.eof?
      rescue EOFError, Errno::EIO
      end
      _, status = Process.wait2(pid)
    end
    assert status.success?, output
    assert_equal @head, git('rev-parse', 'HEAD').strip
  end

  def test_individual_installers_forward_only_rollback_feature
    feature = File.join(@root, 'MacOS@Extension', 'JobsGitRollback')
    aggregate = File.join(@root, 'MacOS@Extension', 'JobsProjectTools')
    FileUtils.mkdir_p([feature, aggregate])
    %w[安装 卸载].each do |mode|
      entry = File.join(feature, "【MacOS】#{mode}Git提交回退Finder扩展.command")
      original = File.expand_path("../【MacOS】#{mode}Git提交回退Finder扩展.command", __dir__)
      FileUtils.cp(original, entry)
      target = File.join(aggregate, "【MacOS】#{mode}项目工具Finder扩展.command")
      File.write(target, "print -r -- \"$1\"\nexit 7\n")
      output, status = Open3.capture2e('/bin/zsh', entry)
      assert_equal "git-rollback\n", output
      assert_equal 7, status.exitstatus
    end
  end
end
