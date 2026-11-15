# frozen_string_literal: true
# 编译真实远程打开源码；浏览器和 Terminal 用替身，Git 与 fzf 只访问临时夹具。

require 'minitest/autorun'
require 'open3'
require 'tmpdir'
require 'fileutils'
require 'json'
require 'pty'
require 'io/console'

class GitRemoteBrowserOpenerTests < Minitest::Test
  ROOT = File.expand_path('../../..', __dir__)
  SOURCE = File.join(ROOT, 'JobsGitRemoteOpener/JobsGitRemoteOpener/GitRemoteBrowserOpener.swift')
  RESOLVER = File.join(ROOT, 'JobsGitRemoteCopier/JobsGitRemoteCopyFinderSync/GitRemoteResolver.swift')
  DISPATCH = /    private func dispatch\(commandLine: String\) throws \{.*?(?=\n    \/\/ 统一宿主)/m
  REAL_FZF = ['/opt/homebrew/bin/fzf', '/usr/local/bin/fzf'].find { |path| File.executable?(path) }

  def setup
    @directory = Dir.mktmpdir('git-remote-browser-')
    @environment = ENV.to_h.reject { |key, _| key.start_with?('GIT_') }.merge(
      'GIT_CONFIG_NOSYSTEM' => '1', 'GIT_CONFIG_GLOBAL' => File::NULL,
      'TMPDIR' => @directory, 'NO_COLOR' => '1', 'TERM' => 'xterm-256color'
    )
    @binary = File.join(@directory, 'test-browser')
    source = File.read(SOURCE).sub('NSWorkspace.shared.open(webURL)', 'TestWorkspace.open(webURL)')
    source = source.gsub('FileManager.default.temporaryDirectory', 'URL(fileURLWithPath: ProcessInfo.processInfo.environment["TMPDIR"]!, isDirectory: true)')
    assert_match DISPATCH, source
    source = source.sub(DISPATCH, <<~'SWIFT')
          private func dispatch(commandLine: String) throws {
              TestEffects.dispatched.append(commandLine)
              if ProcessInfo.processInfo.environment["JOBS_TEST_DISPATCH_FAIL"] == "1" {
                  throw failure("test dispatch failure")
              }
          }
    SWIFT
    harness = <<~'SWIFT'
      enum TestEffects {
          static var opened: [String] = []
          static var dispatched: [String] = []
      }
      enum TestWorkspace {
          static func open(_ url: URL) -> Bool {
              TestEffects.opened.append(url.absoluteString)
              return ProcessInfo.processInfo.environment["JOBS_TEST_BROWSER_FAIL"] != "1"
          }
      }
      let opener = GitRemoteBrowserOpener()
      let mode = CommandLine.arguments[1]
      let root = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
      var result: [String: Any] = [:]
      do {
          switch mode {
          case "list":
              result["remotes"] = try opener.configuredRemotes(at: root).map { ["name": $0.name, "address": $0.address] }
          case "script":
              print(opener.selectionScript(remotes: try opener.configuredRemotes(at: root)))
          case "open":
              try opener.open(from: root)
          case "convert":
              result["url"] = try GitRemoteResolver().webURL(forRemoteURLString: CommandLine.arguments[2]).absoluteString
          default:
              fatalError("unsupported harness mode")
          }
      } catch {
          result["error"] = error.localizedDescription
      }
      if mode != "script" {
          result["opened"] = TestEffects.opened
          result["dispatched"] = TestEffects.dispatched
          let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
          print(String(decoding: data, as: UTF8.self))
      }
    SWIFT
    file = File.join(@directory, 'main.swift')
    File.write(file, [File.read(RESOLVER), source, harness].join("\n"))
    output, status = Open3.capture2e(@environment, '/usr/bin/xcrun', 'swiftc', file, '-o', @binary, unsetenv_others: true)
    assert status.success?, output
    @repository = File.join(@directory, "仓库 空格 ' $() `id` \\ \n")
    git('init', '-q', '-b', 'main', @repository, at: @directory)
  end

  def teardown
    FileUtils.remove_entry(@directory) if @directory && File.directory?(@directory)
  end

  def test_zero_single_and_multiple_remotes_preserve_raw_configuration
    result = browser('open')
    assert_match(/没有配置 remote/, result.fetch('error'))
    assert_empty result.fetch('opened')
    assert_empty result.fetch('dispatched')
    git('remote', 'add', 'origin', 'https://example.test/jobs/original.git')
    git('config', 'url.https://rewrite.example/.insteadOf', 'https://example.test/')
    git('config', '--add', 'remote.origin.url', 'https://example.test/jobs/second-url.git')
    assert_equal [{ 'name' => 'origin', 'address' => 'https://example.test/jobs/original.git' }], browser('list').fetch('remotes')
    result = browser('open')
    assert_equal ['https://example.test/jobs/original'], result.fetch('opened')
    assert_empty result.fetch('dispatched')
    result = browser('open', environment: { 'JOBS_TEST_BROWSER_FAIL' => '1' })
    assert_match(/浏览器未能打开/, result.fetch('error'))
    git('remote', 'add', 'a-镜像', 'git@example.test:jobs/mirror.git')
    git('config', 'branch.main.remote', 'origin')
    git('config', 'branch.main.merge', 'refs/heads/main')
    names = browser('list').fetch('remotes').map { |remote| remote.fetch('name') }
    assert_equal ['a-镜像', 'origin'], names
    result = browser('open')
    assert_empty result.fetch('opened'), 'branch/origin cannot bypass selection when multiple remotes exist'
    assert_equal 1, result.fetch('dispatched').length
    refute_match(/[\r\n]/, result.fetch('dispatched').first)
    carriers = Dir.glob(File.join(@directory, 'JobsGitRemoteOpen-*', 'select.zsh'))
    assert_equal 1, carriers.length
    assert_equal 0o600, File.stat(carriers.first).mode & 0o777
    assert_equal 0o700, File.stat(File.dirname(carriers.first)).mode & 0o777
    FileUtils.remove_entry(File.dirname(carriers.first))
    result = browser('open', environment: { 'JOBS_TEST_DISPATCH_FAIL' => '1' })
    assert_equal 'test dispatch failure', result.fetch('error')
    assert_empty Dir.glob(File.join(@directory, 'JobsGitRemoteOpen-*')), 'failed dispatch cleans only its private carrier'
  end

  def test_native_git_reads_include_subdirectory_and_worktree_config
    included = File.join(@directory, 'included config 中文')
    File.write(included, "[remote \"included\"]\n\turl = https://example.test/jobs/included.git\n")
    git('config', 'include.path', included)
    subdirectory = File.join(@repository, '子目录')
    FileUtils.mkdir_p(subdirectory)
    assert_equal ['included'], browser('list', at: subdirectory).fetch('remotes').map { |remote| remote.fetch('name') }
    File.write(File.join(@repository, 'fixture.txt'), 'fixture')
    git('add', 'fixture.txt')
    git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.test', 'commit', '-qm', 'fixture')
    git('config', 'extensions.worktreeConfig', 'true')
    worktree = File.join(@directory, "worktree 中文 ' $()")
    git('worktree', 'add', '-q', '--detach', worktree)
    git('config', '--worktree', 'remote.worktree.url', 'https://example.test/jobs/worktree.git', at: worktree)
    assert File.file?(File.join(worktree, '.git'))
    assert_equal ['included', 'worktree'], browser('list', at: worktree).fetch('remotes').map { |remote| remote.fetch('name') }
    assert_equal ['included'], browser('list').fetch('remotes').map { |remote| remote.fetch('name') }
  end

  def test_unsupported_single_remote_and_invalid_repository_do_not_dispatch
    assert_equal 'https://example.test/team/repo', browser('convert', at: 'ssh://git@example.test:2222/team/repo.git').fetch('url')
    git('remote', 'add', 'origin', 'file:///unsupported/repository')
    result = browser('open')
    assert_match(/暂不支持/, result.fetch('error'))
    assert_empty result.fetch('opened')
    assert_empty result.fetch('dispatched')
    result = browser('open', at: @directory)
    assert_match(/无法读取/, result.fetch('error'))
    assert_empty result.fetch('opened')
    assert_empty result.fetch('dispatched')
  end

  def test_real_fzf_direction_keys_cancel_and_select_exactly_one_remote
    refute_nil REAL_FZF, 'Install fzf before running interactive selector tests'
    two_remotes
    cases = [
      ["\e[B\e[B\r", ['https://example.test/jobs/second']],
      ["\e[B\e[B\e[A\r", ['https://example.test/jobs/first']],
      ["\r", []], ["\e", []], ["\e[D", []]
    ]
    cases.each do |keys, expected|
      output, status, opened = run_selector(fzf: :real, keys: keys)
      assert status.success?, output
      assert_equal expected, opened, "unexpected browser result for #{keys.inspect}"
    end
  end

  def test_fzf_error_empty_invalid_missing_and_broken_never_open
    two_remotes
    cases = {
      'error2' => [2, /fzf 选择失败/], 'empty' => [0, /已取消/],
      'empty1' => [0, /已取消/], 'abort' => [0, /已取消/],
      'invalid' => [1, /无效的远程/], 'missing' => [1, /fzf 缺失或损坏/],
      'broken' => [1, /fzf 缺失或损坏/], 'no-options' => [1, /不支持所需选择选项/]
    }
    cases.each do |mode, (expected_status, message)|
      output, status, opened = run_selector(fzf: mode)
      assert_equal expected_status, status.exitstatus, output
      assert_match message, output
      assert_empty opened, "#{mode} cannot fall back to the first remote"
    end
  end

  def test_unsupported_selection_and_browser_failure_preserve_failure
    two_remotes
    git('config', 'remote.z-second.url', 'file:///unsupported/repository')
    output, status, opened = run_selector(fzf: 'second')
    assert_equal 1, status.exitstatus, output
    assert_match(/所选远程地址类型暂不支持/, output)
    assert_empty opened
    git('config', 'remote.z-second.url', 'https://example.test/jobs/second.git')
    output, status, opened = run_selector(fzf: 'second', environment: { 'JOBS_TEST_OPEN_EXIT' => '7' })
    assert_equal 1, status.exitstatus, output
    assert_match(/浏览器未能打开/, output)
    assert_equal ['https://example.test/jobs/second'], opened
  end

  private

  def git(*arguments, at: @repository)
    output, status = Open3.capture2e(@environment, '/usr/bin/git', '-C', at, *arguments, unsetenv_others: true)
    assert status.success?, output
    output
  end

  def browser(mode, at: @repository, environment: {})
    output, status = Open3.capture2e(@environment.merge(environment), @binary, mode, at, unsetenv_others: true)
    assert status.success?, output
    mode == 'script' ? output : JSON.parse(output)
  end

  def two_remotes
    git('remote', 'add', 'a-first', 'git@example.test:jobs/first.git')
    git('remote', 'add', 'z-second', 'https://example.test/jobs/second.git')
  end

  def shell_word(value)
    "'#{value.gsub("'") { %q('\'') }}'"
  end

  def run_selector(fzf:, keys: nil, environment: {})
    root = Dir.mktmpdir("选择器 中文 ' ", @directory)
    runtime = File.join(root, 'runtime')
    bin = File.join(root, 'bin')
    FileUtils.mkdir_p([runtime, bin])
    captured = File.join(root, 'opened.txt')
    browser_stub = File.join(bin, 'browser-stub')
    File.write(browser_stub, "#!/bin/zsh\nprint -rl -- \"$@\" >> \"$JOBS_TEST_OPEN_LOG\"\nexit \"${JOBS_TEST_OPEN_EXIT:-0}\"\n")
    File.chmod(0o700, browser_stub)
    if fzf == :real
      File.symlink(REAL_FZF, File.join(bin, 'fzf'))
    elsif fzf != 'missing'
      File.write(File.join(bin, 'fzf'), fake_fzf)
      File.chmod(0o700, File.join(bin, 'fzf'))
    end
    script = browser('script')
    script = script.sub('path+=(/opt/homebrew/bin /usr/local/bin)') { "path=(#{shell_word(bin)})" }
    script = script.sub('/usr/bin/open "${urls[index]}"') { "#{shell_word(browser_stub)} \"${urls[index]}\"" }
    path = File.join(runtime, 'select.zsh')
    File.write(path, script)
    syntax, syntax_status = Open3.capture2e('/bin/zsh', '-n', path)
    assert syntax_status.success?, syntax
    child_environment = @environment.merge(
      'JOBS_TEST_OPEN_LOG' => captured, 'JOBS_TEST_FZF_MODE' => fzf.to_s,
      'FZF_DEFAULT_OPTS' => '--filter=z-second', 'FZF_DEFAULT_OPTS_FILE' => '/not/a/real/options/file'
    ).merge(environment)
    output = +''
    status = nil
    PTY.spawn(child_environment, '/bin/zsh', path, unsetenv_others: true) do |reader, writer, pid|
      reader.winsize = [30, 180]
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 8
      sent = false
      begin
        loop do
          raise "fzf PTY timed out: #{output.inspect}" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
          if IO.select([reader], nil, nil, 0.05)
            chunk = reader.read_nonblock(65_536, exception: false)
            break if chunk.nil?
            if chunk != :wait_readable
              output << chunk
              writer.write("\e[1;1R") if chunk.include?("\e[6n")
            end
          end
          if keys && !sent && output.include?('z-second')
            writer.write(keys)
            writer.flush
            sent = true
          end
          reaped = Process.waitpid2(pid, Process::WNOHANG)
          if reaped
            status = reaped[1]
            break
          end
        end
      rescue Errno::EIO
        # PTY 从进程退出后读到 EIO 是正常关闭。
      ensure
        unless status
          begin
            _, status = Process.waitpid2(pid, Process::WNOHANG)
            unless status
              Process.kill('TERM', pid)
              _, status = Process.waitpid2(pid)
            end
          rescue Errno::ECHILD
            status = $?
          end
        end
      end
    end
    refute File.exist?(path), 'selector cleans its own carrier after completion'
    opened = File.exist?(captured) ? File.readlines(captured, chomp: true) : []
    [output.force_encoding(Encoding::UTF_8), status, opened]
  end

  def fake_fzf
    <<~'SHELL'
      #!/bin/zsh
      if [[ "$1" == --version ]]; then
        [[ "$JOBS_TEST_FZF_MODE" == broken ]] && exit 9
        print -r -- 'test-fzf 1.0'
        exit 0
      fi
      if [[ "$1" == --help ]]; then
        [[ "$JOBS_TEST_FZF_MODE" == no-options ]] && exit 0
        print -r -- '--bind --delimiter --with-nth'
        exit 0
      fi
      case "$JOBS_TEST_FZF_MODE" in
        error2) exit 2 ;;
        empty) exit 0 ;;
        empty1) exit 1 ;;
        abort) exit 130 ;;
        invalid) print -r -- $'2\twrong\thttps://wrong.example'; exit 0 ;;
        second) /usr/bin/sed -n '3p'; exit 0 ;;
      esac
      exit 3
    SHELL
  end
end
