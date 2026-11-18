# frozen_string_literal: true
# 验证真实分发器的 SDK / Java 门禁和退出码；所有 worker 在临时目录替换，不执行安装。
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

require_relative '../../../Tests/SourceLayoutHelper.rb/SourceLayoutHelper'

class VersionManagerDispatchTests < Minitest::Test
  def setup
    @root = File.realpath(Dir.mktmpdir('jobs-version-dispatch-'))
    @tools = File.join(@root, 'tools')
    @project = File.join(@root, "项目 ' $(touch NEVER) ; space")
    @trace = File.join(@root, 'trace')
    FileUtils.mkdir_p([@tools, File.join(@project, 'lib')])
    File.write(File.join(@project, 'pubspec.yaml'), "name: fixture\ndependencies:\n  flutter:\n    sdk: flutter\n")
    JobsSourceLayout.copy(File.expand_path('../Scripts/Tools/【MacOS】DispatchFlutterTools.zsh/【MacOS】DispatchFlutterTools.zsh', File.dirname(__dir__)), @tools)
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def write_worker(name, body)
    File.write(File.join(@tools, name), "#!/bin/zsh\n#{body}\n")
  end

  def dispatch(action)
    Open3.capture3({ 'JOBS_DISPATCH_TRACE' => @trace }, '/bin/zsh', File.join(@tools, 'DispatchFlutterTools.zsh'), action, @project)
  end

  def prepare_fvm
    File.write(File.join(@project, '.fvmrc'), '{"flutter":"fixture"}')
    %w[bin/flutter bin/cache/dart-sdk/bin/dart].each do |relative|
      path = File.join(@project, '.fvm/flutter_sdk', relative)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "#!/bin/zsh\nexit 97\n")
      FileUtils.chmod(0o755, path)
    end
  end

  def test_new_managers_run_without_fvm_and_with_unresolved_java_declaration
    File.write(File.join(@project, '.java-version'), 'unresolved-fixture')
    { 'ohos-sdk-manage' => 'ManageHarmonyFlutterVersion.zsh', 'java-manage' => 'ManageProjectJava.zsh' }.each do |action, worker|
      write_worker(worker, 'printf "%s\0" "$@" > "$JOBS_DISPATCH_TRACE"; exit 19')
      output, error, status = dispatch(action)
      assert_equal 19, status.exitstatus, output + error
      assert_equal ['--project', @project], File.binread(@trace).force_encoding('UTF-8').split("\0")
      refute File.exist?(File.join(@root, 'NEVER'))
    end
  end

  def test_java_binding_failure_stops_worker
    prepare_fvm
    File.write(File.join(@project, '.java-version'), '17')
    write_worker('ManageProjectJava.zsh', 'pj_bind_project_java() { return 23; }')
    write_worker('PackageFlutter.zsh', 'touch "$JOBS_DISPATCH_TRACE"')
    output, error, status = dispatch('package-android')
    assert_equal 23, status.exitstatus, output + error
    refute File.exist?(@trace)
  end

  def test_project_java_reaches_package_and_runner_workers
    prepare_fvm
    File.write(File.join(@project, '.java-version'), '17')
    write_worker('ManageProjectJava.zsh', <<~'SH')
      pj_bind_project_java() {
        export JAVA_HOME="$1/fixture-jdk"
        export GRADLE_OPTS='-Dorg.gradle.java.home="fixture-jdk"'
      }
    SH
    %w[PackageFlutter.zsh RunFlutterProject.zsh].each do |worker|
      write_worker(worker, 'printf "%s\0" "$JAVA_HOME" "$GRADLE_OPTS" > "$JOBS_DISPATCH_TRACE"; exit 21')
    end
    %w[package-android run].each do |action|
      output, error, status = dispatch(action)
      assert_equal 21, status.exitstatus, output + error
      assert_equal [File.join(@project, 'fixture-jdk'), '-Dorg.gradle.java.home="fixture-jdk"'], File.binread(@trace).force_encoding('UTF-8').split("\0")
    end
  end

  def test_projects_without_java_declaration_keep_old_worker_behavior
    prepare_fvm
    write_worker('PackageFlutter.zsh', 'printf "%s\0" "$@" > "$JOBS_DISPATCH_TRACE"; exit 29')
    output, error, status = dispatch('package-android')
    assert_equal 29, status.exitstatus, output + error
    assert_equal ['--project', @project, '--platform', 'android'], File.binread(@trace).force_encoding('UTF-8').split("\0")
  end

  def test_sdk_inspection_does_not_require_project_java
    prepare_fvm
    File.write(File.join(@project, '.java-version'), 'unresolved-fixture')
    write_worker('ManageProjectJava.zsh', 'pj_bind_project_java() { return 23; }')
    write_worker('InspectFlutterSdkVersion.zsh', 'printf "%s\0" "$@" > "$JOBS_DISPATCH_TRACE"; exit 31')
    output, error, status = dispatch('sdk-version')
    assert_equal 31, status.exitstatus, output + error
    assert_equal ['--project', @project], File.binread(@trace).force_encoding('UTF-8').split("\0")
  end

  def test_dependency_import_dispatch_preserves_path_and_worker_failure_without_binding_java
    prepare_fvm
    File.write(File.join(@project, '.java-version'), 'unresolved-fixture')
    write_worker('ManageProjectJava.zsh', 'pj_bind_project_java() { return 23; }')
    write_worker('ImportFlutterDependencies.zsh', 'printf "%s\0" "$@" > "$JOBS_DISPATCH_TRACE"; exit 37')
    output, error, status = dispatch('import-dependencies')
    assert_equal 37, status.exitstatus, output + error
    assert_equal [@project], File.binread(@trace).force_encoding('UTF-8').split("\0")
    refute File.exist?(File.join(@root, 'NEVER'))
  end

  def test_dependency_import_dispatches_a_flutter_root_without_lib
    prepare_fvm
    Dir.rmdir(File.join(@project, 'lib'))
    write_worker('ImportFlutterDependencies.zsh', 'printf "%s\0" "$@" > "$JOBS_DISPATCH_TRACE"; exit 37')
    output, error, status = dispatch('import-dependencies')
    assert_equal 37, status.exitstatus, output + error
    assert_equal [@project], File.binread(@trace).force_encoding('UTF-8').split("\0")
    refute File.exist?(File.join(@root, 'NEVER'))
  end

  def test_dependency_import_exception_does_not_expand_other_sdk_actions
    prepare_fvm
    Dir.rmdir(File.join(@project, 'lib'))
    write_worker('InspectFlutterSdkVersion.zsh', 'printf "%s\0" "$@" > "$JOBS_DISPATCH_TRACE"; exit 37')
    output, error, status = dispatch('sdk-version')
    assert_equal 1, status.exitstatus, output + error
    assert_includes error, '请选择 Flutter 项目根目录。'
    refute File.exist?(@trace)
  end
end
