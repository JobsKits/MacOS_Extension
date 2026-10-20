# frozen_string_literal: true
# 临时裸远端与真实 Git/zsh 回归，不访问业务仓库或网络。

require 'fileutils'
require 'minitest/autorun'
require 'open3'
require 'pty'
require 'shellwords'
require 'timeout'
require 'tmpdir'

class GitPullCommandTests < Minitest::Test
  SCRIPT = File.expand_path('../Scripts/PullGitRepository.zsh', __dir__)

  def setup
    @root = File.realpath(Dir.mktmpdir('jobs-git-pull-'))
    @env = { 'GIT_CONFIG_NOSYSTEM' => '1', 'GIT_CONFIG_GLOBAL' => File.join(@root, 'global'),
             'GIT_AUTHOR_NAME' => 'Fixture', 'GIT_AUTHOR_EMAIL' => 'fixture@example.invalid',
             'GIT_COMMITTER_NAME' => 'Fixture', 'GIT_COMMITTER_EMAIL' => 'fixture@example.invalid',
             'NO_COLOR' => '1', 'TERM' => 'dumb' }
    @remote = File.join(@root, 'upstream.git')
    @source = File.join(@root, 'source')
    @repo = File.join(@root, "项目 空格 ' $(touch ESCAPED)")
    git(@root, 'init', '--bare', @remote)
    git(@root, 'init', '-b', 'main', @source)
    File.write(File.join(@source, 'shared.txt'), "base\n")
    File.write(File.join(@source, 'other.txt'), "base\n")
    git(@source, 'add', '.')
    git(@source, 'commit', '-m', 'base')
    git(@source, 'remote', 'add', 'origin', @remote)
    git(@source, 'push', '-u', 'origin', 'main')
    git(@root, 'clone', '-b', 'main', @remote, @repo)
    @original = git(@repo, 'rev-parse', 'HEAD').strip
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def git(dir, *args)
    out, err, status = Open3.capture3(@env, 'git', '-C', dir, *args)
    raise "git #{args.inspect}: #{out}#{err}" unless status.success?
    out
  end

  def remote_change(file = 'shared.txt', contents = "remote\n")
    File.write(File.join(@source, file), contents)
    git(@source, 'add', '.')
    git(@source, 'commit', '-m', 'remote')
    git(@source, 'push', 'origin', 'main')
    git(@source, 'rev-parse', 'HEAD').strip
  end

  def invoke(lines, target = @repo, env: {}, &on_output)
    output = +''
    pid = nil
    Timeout.timeout(25) do
      PTY.spawn(@env.merge(env), '/bin/zsh', SCRIPT, target) do |reader, writer, child|
        pid = child
        writer.write(lines)
        begin
          loop do
            output << reader.readpartial(4096)
            on_output&.call(output.dup.force_encoding('UTF-8').scrub, writer)
          end
        rescue EOFError, Errno::EIO
          # macOS PTY 在 slave 关闭时返回 EIO。
        end
        Process.wait(child)
      end
    end
    [output.force_encoding('UTF-8'), $?.exitstatus]
  rescue Timeout::Error
    Process.kill('TERM', pid) if pid
    raise "脚本等待超时：#{output}"
  end

  def dirty
    File.write(File.join(@repo, 'shared.txt'), "staged\n")
    git(@repo, 'add', 'shared.txt')
    File.write(File.join(@repo, 'shared.txt'), "local working\n")
    File.write(File.join(@repo, '未跟踪 [x].txt'), "untracked\n")
  end

  def snapshot
    [git(@repo, 'rev-parse', 'HEAD'), git(@repo, 'diff', '--cached', '--binary'),
     git(@repo, 'diff', '--binary'), git(@repo, 'status', '--porcelain'),
     File.exist?(File.join(@repo, '未跟踪 [x].txt')) ? File.binread(File.join(@repo, '未跟踪 [x].txt')) : nil]
  end

  def failing_git_probe(command, required_argument = nil)
    directory = File.join(@root, 'git-probe-shim')
    FileUtils.mkdir_p(directory)
    real_git = Open3.capture2(@env, '/usr/bin/which', 'git').first.strip
    calls = File.join(@root, 'git-probe-calls')
    shim = File.join(directory, 'git')
    File.write(shim, <<~ZSH)
      #!/bin/zsh
      print -rl -- "$@" >> #{Shellwords.escape(calls)}
      typeset command_seen=0 argument_seen=#{required_argument ? 0 : 1}
      for item in "$@"; do
          [[ "$item" == #{Shellwords.escape(command)} ]] && command_seen=1
          [[ "$item" == #{Shellwords.escape(required_argument || '')} ]] && argument_seen=1
      done
      if (( command_seen && argument_seen )); then
          print -u2 -r -- 'fixture-probe-failed:#{command}'
          exit 128
      fi
      exec #{Shellwords.escape(real_git)} "$@"
    ZSH
    File.chmod(0o700, shim)
    [{ 'PATH' => "#{directory}:#{ENV.fetch('PATH')}" }, calls]
  end

  def assert_failed_probe_preserved_state(command, required_argument = nil)
    dirty
    before = snapshot
    remote_change
    env, calls = failing_git_probe(command, required_argument)
    out, status = invoke("\n\n", env: env)
    assert_equal 1, status, out
    assert_includes out, "fixture-probe-failed:#{command}"
    assert_equal before, snapshot
    assert_empty git(@repo, 'for-each-ref', 'refs/jobs-git-pull')
    arguments = File.readlines(calls, chomp: true)
    %w[fetch stash merge reset].each { |mutation| refute_includes arguments, mutation }
  end

  def test_non_git_folder_is_a_noop
    folder = File.join(@root, 'plain')
    FileUtils.mkdir_p(folder)
    out, status = invoke('', folder)
    assert_equal 0, status
    assert_empty out
    assert_empty Dir.children(folder)
  end

  def test_clean_fast_forward
    target = remote_change
    out, status = invoke("\n")
    assert_equal 0, status, out
    assert_equal target, git(@repo, 'rev-parse', 'HEAD').strip
    assert_empty git(@repo, 'status', '--porcelain')
    refute File.exist?(File.join(@repo, 'ESCAPED'))
  end

  def test_dirty_non_conflicting_changes_keep_index_and_untracked
    File.write(File.join(@repo, 'other.txt'), "staged\n")
    git(@repo, 'add', 'other.txt')
    File.write(File.join(@repo, 'other.txt'), "working\n")
    File.write(File.join(@repo, '未跟踪 [x].txt'), "untracked\n")
    before = snapshot
    target = remote_change
    out, status = invoke("\n\n")
    assert_equal 0, status, out
    assert_equal target, git(@repo, 'rev-parse', 'HEAD').strip
    assert_equal before[1..-1], snapshot[1..-1]
  end

  def test_cancel_dirty_does_not_fetch_or_change_files
    dirty
    before = snapshot
    remote_change
    out, status = invoke("\nx\n")
    assert_equal 0, status, out
    assert_equal before, snapshot
    assert_empty git(@repo, 'for-each-ref', 'refs/jobs-git-pull')
  end

  def test_conflict_option_one_restores_exact_original_and_existing_stash
    File.write(File.join(@repo, 'other.txt'), "older stash\n")
    git(@repo, 'stash', 'push', '-m', 'existing')
    existing = git(@repo, 'rev-parse', 'refs/stash').strip
    dirty
    before = snapshot
    remote_change
    out, status = invoke("\n\n1\n")
    assert_equal 0, status, out
    assert_equal before, snapshot
    assert_includes git(@repo, 'stash', 'list', '--format=%H'), existing
  end

  def test_conflict_option_two_requires_yes_and_updates_after_discard
    dirty
    target = remote_change
    out, status = invoke("\n\n2\nYES\n")
    assert_equal 0, status, out
    assert_equal target, git(@repo, 'rev-parse', 'HEAD').strip
    assert_empty git(@repo, 'status', '--porcelain')
    refute File.exist?(File.join(@repo, '未跟踪 [x].txt'))
    assert_match(/snapshot/, git(@repo, 'for-each-ref', 'refs/jobs-git-pull'))
  end

  def test_discard_retry_fetches_remote_commits_created_during_confirmation
    dirty
    first_target = remote_change
    latest = nil
    out, status = invoke("\n\n2\n") do |output, writer|
      next if latest || !output.include?('输入 YES 确认：')
      latest = remote_change('late-remote.txt', "remote advanced while confirming\n")
      writer.write("YES\n")
    end
    refute_nil latest, out
    refute_equal first_target, latest
    assert_equal 0, status, out
    assert_equal latest, git(@repo, 'rev-parse', 'HEAD').strip
    assert_equal "remote advanced while confirming\n", File.read(File.join(@repo, 'late-remote.txt'))
    refute File.exist?(File.join(@repo, '未跟踪 [x].txt'))
    assert_empty git(@repo, 'status', '--porcelain')
  end

  def test_declining_discard_restores_original
    dirty
    before = snapshot
    remote_change
    out, status = invoke("\n\n2\nno\n")
    assert_equal 1, status, out
    assert_equal before, snapshot
  end

  def test_option_three_accepts_empty_message_and_second_rollback_keeps_commit
    dirty
    remote_change
    out, status = invoke("\n\n3\n\n1\n")
    assert_equal 0, status, out
    refute_equal @original, git(@repo, 'rev-parse', 'HEAD').strip
    assert_equal @original, git(@repo, 'rev-parse', 'HEAD^').strip
    assert_equal '', git(@repo, 'log', '-1', '--format=%B').strip
    assert_equal "local working\n", File.read(File.join(@repo, 'shared.txt'))
    assert_equal "untracked\n", File.read(File.join(@repo, '未跟踪 [x].txt'))
    assert_empty git(@repo, 'status', '--porcelain')
  end

  def test_committed_conflict_can_rollback_without_losing_local_commit
    File.write(File.join(@repo, 'shared.txt'), "local commit\n")
    git(@repo, 'add', '.')
    git(@repo, 'commit', '-m', 'local')
    before = snapshot
    remote_change
    out, status = invoke("\n1\n")
    assert_equal 0, status, out
    assert_equal before, snapshot
  end

  def test_commit_retry_does_not_revive_changes_discarded_in_previous_attempt
    File.write(File.join(@repo, 'shared.txt'), "local committed conflict\n")
    git(@repo, 'add', 'shared.txt')
    git(@repo, 'commit', '-m', 'keep local history')
    local_head = git(@repo, 'rev-parse', 'HEAD').strip
    commit_count = git(@repo, 'rev-list', '--count', 'HEAD')
    File.write(File.join(@repo, 'other.txt'), "discard staged change\n")
    git(@repo, 'add', 'other.txt')
    File.write(File.join(@repo, 'other.txt'), "discard working change\n")
    File.write(File.join(@repo, '未跟踪 [x].txt'), "discard untracked change\n")
    remote_change
    unexpected_commit_prompt = false
    out, status = invoke("\n\n2\nYES\n3\n") do |output, writer|
      next if unexpected_commit_prompt || !output.include?('输入 commit 信息')
      unexpected_commit_prompt = true
      writer.write("\n1\n")
    end
    refute unexpected_commit_prompt, out
    assert_equal 1, status, out
    assert_equal local_head, git(@repo, 'rev-parse', 'HEAD').strip
    assert_equal commit_count, git(@repo, 'rev-list', '--count', 'HEAD')
    assert_equal "local committed conflict\n", File.read(File.join(@repo, 'shared.txt'))
    assert_equal "base\n", File.read(File.join(@repo, 'other.txt'))
    refute File.exist?(File.join(@repo, '未跟踪 [x].txt'))
    assert_empty git(@repo, 'status', '--porcelain')
  end

  def test_fetch_failure_preserves_dirty_state
    dirty
    before = snapshot
    git(@repo, 'remote', 'set-url', 'origin', File.join(@root, 'missing.git'))
    out, status = invoke("\n\n")
    assert_equal 1, status, out
    assert_equal before, snapshot
    refute_match(/输入 1 \/ 2 \/ 3/, out)
  end

  def test_user_no_commit_merge_option_cannot_report_false_success
    File.write(File.join(@repo, 'other.txt'), "local commit\n")
    git(@repo, 'add', '.')
    git(@repo, 'commit', '-m', 'local')
    git(@repo, 'config', 'branch.main.mergeOptions', '--no-commit')
    target = remote_change
    out, status = invoke("\n")
    assert_equal 0, status, out
    git(@repo, 'merge-base', '--is-ancestor', target, 'HEAD')
    refute File.exist?(File.join(@repo, '.git', 'MERGE_HEAD'))
  end

  def test_failed_diff_probe_stops_before_any_transaction
    assert_failed_probe_preserved_state('diff')
  end

  def test_failed_untracked_probe_stops_before_any_transaction
    assert_failed_probe_preserved_state('ls-files', '--others')
  end

  def test_declining_discard_after_external_edit_keeps_new_edit_and_conflict_scene
    dirty
    target = remote_change
    edited = false
    out, status = invoke("\n\n2\n") do |output, writer|
      next if edited || !output.include?('输入 YES 确认：')
      edited = true
      File.write(File.join(@repo, 'other.txt'), "external edit while confirming\n")
      writer.write("NO\n")
    end
    assert edited, out
    assert_equal 1, status, out
    assert_equal "external edit while confirming\n", File.read(File.join(@repo, 'other.txt'))
    assert_equal target, git(@repo, 'rev-parse', 'HEAD').strip
    assert_includes out, '保留现场'
    refute_match(/✔ 已回滚/, out)
  end

  def test_ignored_file_is_not_overwritten_by_remote_tracked_file
    File.write(File.join(@repo, '.git', 'info', 'exclude'), "local.secret\n")
    File.write(File.join(@repo, 'local.secret'), "private ignored content\n")
    before = snapshot
    remote_change('local.secret', "remote tracked content\n")
    out, status = invoke("\n")
    assert_equal 1, status, out
    assert_equal before, snapshot
    assert_equal "private ignored content\n", File.read(File.join(@repo, 'local.secret'))
    refute_match(/输入 1 \/ 2 \/ 3/, out)
  end

  def test_missing_upstream_stops_before_fetch
    git(@repo, 'config', '--unset', 'branch.main.remote')
    dirty
    before = snapshot
    out, status = invoke("\n")
    assert_equal 1, status, out
    assert_equal before, snapshot
    assert_includes out, 'upstream'
    assert_empty git(@repo, 'for-each-ref', 'refs/jobs-git-pull')
  end

  def test_existing_merge_conflict_is_preserved
    File.write(File.join(@repo, 'shared.txt'), "local committed conflict\n")
    git(@repo, 'add', '.')
    git(@repo, 'commit', '-m', 'local')
    remote_change
    git(@repo, 'fetch', 'origin')
    _, _, merge_status = Open3.capture3(@env, 'git', '-C', @repo, 'merge', '--no-edit', 'origin/main')
    refute merge_status.success?
    marker = File.join(@repo, '.git', 'MERGE_HEAD')
    before_marker = File.binread(marker)
    before = snapshot
    out, status = invoke("\n")
    assert_equal 1, status, out
    assert_equal before, snapshot
    assert_equal before_marker, File.binread(marker)
    assert_includes out, '已有 Git 操作进行中'
    assert_empty git(@repo, 'for-each-ref', 'refs/jobs-git-pull')
  end

  def test_user_squash_merge_option_cannot_report_false_success
    File.write(File.join(@repo, 'other.txt'), "local commit\n")
    git(@repo, 'add', '.')
    git(@repo, 'commit', '-m', 'local')
    git(@repo, 'config', 'branch.main.mergeOptions', '--squash')
    target = remote_change
    out, status = invoke("\n")
    assert_equal 0, status, out
    git(@repo, 'merge-base', '--is-ancestor', target, 'HEAD')
    assert_empty git(@repo, 'status', '--porcelain')
    refute File.exist?(File.join(@repo, '.git', 'MERGE_HEAD'))
  end

  def test_linked_worktrees_share_the_session_lock
    linked = File.join(@root, 'linked worktree')
    git(@repo, 'worktree', 'add', '-b', 'linked', linked)
    git(linked, 'branch', '--set-upstream-to=origin/main')
    dirty
    before = snapshot
    second_result = nil
    out, status = invoke("\n") do |output, writer|
      next if second_result || !output.include?('直接回车确认保护这些内容后继续')
      assert File.directory?(File.join(@repo, '.git', 'jobs-git-pull.lock')), output
      second_result = invoke("\n", linked)
      assert File.directory?(File.join(@repo, '.git', 'jobs-git-pull.lock')), second_result[0]
      writer.write("x\n")
    end
    assert_equal 0, status, out
    refute_nil second_result, out
    assert_equal 1, second_result[1], second_result[0]
    assert_includes second_result[0], '已有拉取会话或遗留锁'
    assert_equal before, snapshot
    assert_empty git(@repo, 'for-each-ref', 'refs/jobs-git-pull')
    assert_empty git(linked, 'status', '--porcelain')
    refute File.exist?(File.join(@repo, '.git', 'jobs-git-pull.lock'))
  end
end
