# frozen_string_literal: true
# 管理 GUI 的隔离后端回归：所有扩展业务、桌面启动及编译均由替身承接。
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
require 'fileutils'

class ManagementGUIBackendTests < Minitest::Test
  ROOT = File.expand_path('..', __dir__)
  MANAGER = File.join(ROOT, 'Scripts/ManageFinderExtensions.zsh')
  STANDALONE = %w[JobsFlutterTools JobsIOSTools JobsIPAResigner JobsPathCopier JobsRunAuthorizationRevoker JobsRunAuthorizer JobsTerminalOpener JobsProjectTools JobsDesktopTools JobsFileCreator].freeze

  def definitions(path)
    File.read(path).sub(/^(?:manager_)?main "\$@"\s*\z/, '')
  end

  def execute(source, *arguments, env: {})
    Open3.capture3(env, '/bin/zsh', '-c', source, 'fixture', *arguments)
  end

  def test_root_emits_success_and_failure_for_each_leaf_and_continues_after_failure
    %w[install uninstall].each do |operation|
      output, errors, result = execute(definitions(MANAGER) + <<~'ZSH', operation)
        LOG_FILE=/dev/null
        MANAGEMENT_ACTION="$1"
        parse_feature_selection git-pull,git-rollback,run-authorize,path_copier || exit $?
        ensure_feature_projects_exist() { return 0; }
        install_feature() { printf 'without-newline'; [[ "$1" != run-authorize ]]; }
        uninstall_feature() { printf 'without-newline'; [[ "$1" != run-authorize ]]; }
        if [[ "$MANAGEMENT_ACTION" == uninstall ]]; then uninstall_selected_features; else install_selected_features; fi
        print -r -- "EXIT=$FINAL_EXIT_STATUS"
      ZSH
      assert result.success?, errors
      events = output.lines.grep(/^JOBS_MANAGER_EVENT\t/).map { |line| line.split("\t")[1, 2] }
      assert_equal [['git-pull', 'running'], ['git-rollback', 'running'], ['git-pull', 'succeeded'], ['git-rollback', 'succeeded'], ['run-authorize', 'running'], ['run-authorize', 'failed'], ['path_copier', 'running'], ['path_copier', 'succeeded']], events
      assert_includes output, 'EXIT=1'
    end
  end

  def test_single_package_worker_reports_real_failure_exit_and_uses_gui_leaf_identifier
    path = Dir.glob(File.join(ROOT, 'JobsFlutterTools', 'Scripts/ManageExtension.zsh')).fetch(0)
    output, errors, result = execute(definitions(path) + <<~'ZSH', path)
      ZSH_ARGZERO="$1"
      manager_validate_existing_configuration() { return 0; }
      run_install_operation() { printf 'tail-without-newline'; return 37; }
      manager_main --action install --features flutter-package-ios --non-interactive
    ZSH
    assert_equal 37, result.exitstatus, errors
    events = output.lines.grep(/^JOBS_MANAGER_EVENT\t/).map { |line| line.split("\t")[1, 2] }
    assert_equal [['flutter-package-ios', 'running'], ['flutter-package-ios', 'failed']], events
  end

  def test_all_functional_entrypoints_open_gui_and_never_dispatch_business_by_default
    entries = Dir.glob(File.join(ROOT, 'Jobs*', 'Scripts/ManageExtension.zsh'))
    assert_equal 31, entries.length
    entries.each do |path|
      boundaries = if path.include?('/JobsFileCreator/')
                     <<~'ZSH'
                       manager_main() { main "$@"; }
                       open_management_panel() { print -r -- 'GUI=file-create'; }
                       run_worker() { print -u2 unexpected-worker; return 97; }
                     ZSH
                   else
                     ''
                   end
      output, errors, result = execute(definitions(path) + boundaries + <<~'ZSH', path)
        ZSH_ARGZERO="$1"
        manager_open_gui() { print -r -- "GUI=$MANAGER_UI_SCOPE"; }
        run_install_operation() { print -u2 unexpected-install; return 97; }
        run_uninstall_operation() { print -u2 unexpected-uninstall; return 97; }
        read() { print -u2 unexpected-read; return 97; }
        fzf() { print -u2 unexpected-fzf; return 97; }
        manager_main
      ZSH
      assert result.success?, "#{path}: #{errors}"
      assert_match(/^GUI=.+/, output)
      refute_match(/unexpected-/, output + errors)
    end
  end

  def test_standalone_packages_keep_identical_panel_source_and_launch_support
    STANDALONE.each do |name|
      assert_equal File.binread(File.join(ROOT, 'Scripts', 'SelectFinderExtensionFeatures.swift')), File.binread(File.join(ROOT, name, 'Scripts', 'ManagementPanel.swift')), name
      assert_equal File.binread(File.join(ROOT, 'Scripts', 'FinderManagerGUI.zsh')), File.binread(File.join(ROOT, name, 'Scripts', 'FinderManagerGUI.zsh')), name
    end
  end

  def test_app_bundles_are_text_only_launchers_with_executable_relative_entrypoints
    apps = Dir.glob(File.join(ROOT, '**', '【MacOS】*Finder扩展.app'))
    assert_equal 32, apps.length
    apps.each do |app|
      launcher = File.join(app, 'Contents', 'MacOS', 'LaunchManager')
      assert File.executable?(launcher), app
      assert File.file?(app.sub(/\.app\z/, '.command')), app
      worker = File.join(File.dirname(app), 'Scripts', File.dirname(app) == ROOT ? 'ManageFinderExtensions.zsh' : 'ManageExtension.zsh')
      assert File.file?(worker), app
      output, result = Open3.capture2e('/usr/bin/plutil', '-lint', File.join(app, 'Contents', 'Info.plist'))
      assert result.success?, output
      output, result = Open3.capture2e('/bin/zsh', '-n', launcher)
      assert result.success?, output
      refute_match(/quit.*Terminal|killall.*Terminal|close every/, File.read(launcher))
      assert_includes File.read(launcher), 'tty of targetTab is launchTTY'
      assert_includes File.read(launcher), '(count of processes of targetTab) is 0'
      assert_includes File.read(launcher), 'not busy of targetTab'
    end
  end

  def test_gui_bootstrap_executes_cached_panel_with_worker_scope
    Dir.mktmpdir('jobs-gui-helper-') do |directory|
      scripts = File.join(directory, 'Scripts')
      FileUtils.mkdir_p(scripts)
      FileUtils.mkdir_p(File.join(directory, 'work'))
      File.write(File.join(scripts, 'SelectFinderExtensionFeatures.swift'), '// fixture')
      panel = File.join(directory, 'work', 'SelectFinderExtensionFeatures')
      File.write(panel, "#!/bin/zsh\nprintf '%s\n' \"$@\"\n")
      File.chmod(0o755, panel)
      helper = File.read(File.join(ROOT, 'Scripts', 'FinderManagerGUI.zsh'))
      worker = File.join(scripts, 'ManageFinderExtensions.zsh')
      output, errors, result = execute(helper + <<~'ZSH', worker)
        jobs_manager_launch_error() { print -u2 unexpected-error; return 1; }
        jobs_launch_finder_manager_gui "$1" 'git-pull,run-authorize' uninstall 1
      ZSH
      assert result.success?, errors
      assert_equal ['--manager', worker, '--action', 'uninstall', '--install-location', 'build', '--scope', 'git-pull,run-authorize'], output.lines.map(&:chomp)
    end
  end
  def test_actual_launchers_resolve_script_paths_inside_zsh_functions
    Dir.mktmpdir('jobs-launch 中文 ') do |directory|
      Dir.glob(File.join(ROOT, '**', '【MacOS】*Finder扩展.app')).each_with_index do |app, index|
        package = File.join(directory, "功能#{index}")
        local_app = File.join(package, File.basename(app))
        launcher = File.join(local_app, 'Contents', 'MacOS', 'LaunchManager')
        FileUtils.mkdir_p(File.dirname(launcher))
        FileUtils.cp(File.join(app, 'Contents', 'MacOS', 'LaunchManager'), launcher)
        FileUtils.mkdir_p(File.join(package, 'Scripts'))
        worker_name = File.dirname(app) == ROOT ? 'ManageFinderExtensions.zsh' : 'ManageExtension.zsh'
        File.write(File.join(package, 'Scripts', worker_name), "#!/bin/zsh\nprintf '%s\n' \"$@\"\n")
        output, result = Open3.capture2e('/bin/zsh', launcher, '--action', 'uninstall')
        assert result.success?, "#{app}: #{output}"
        assert_equal ['--gui-session', '--action', 'uninstall'], output.lines.map(&:chomp), app
      end
    end
  end

  def test_original_command_entries_only_open_the_full_gui
    entries = Dir.glob(File.join(ROOT, '**', '【MacOS】*Finder扩展.app')).map { |app| app.sub(/\.app\z/, '.command') }
    assert_equal 32, entries.count
    entries.each do |entry|
      source = definitions(entry).gsub('/usr/bin/open', 'fake_open')
      output, errors, result = execute(source + <<~'ZSH', entry)
        ZSH_ARGZERO="$1"
        fake_open() { print -l -r -- "$@"; }
        main
      ZSH
      assert result.success?, "#{entry}: #{errors}"
      assert_equal ['-n', entry.sub(/\.command\z/, '.app'), '--args', '--package-root', File.dirname(entry)], output.lines.map(&:chomp), entry
      refute_match(/--non-interactive|xcodebuild|pluginkit|killall|read /, File.read(entry))
    end
  end

  def test_app_retains_local_action_aliases_as_scoped_gui_selection
    {
      'JobsFlutterTools' => [['--features', 'run,package-android'], 'flutter-run,flutter-package-android'],
      'JobsTerminalOpener' => [['--features', 'file-content'], 'file_content'],
      'JobsIOSTools' => [['--features=ios-code-snippets'], 'ios-code-snippets']
    }.each do |name, (arguments, expected_scope)|
      Dir.mktmpdir('jobs-alias GUI 中文 ') do |directory|
        scripts = File.join(directory, name, 'Scripts')
        FileUtils.mkdir_p(scripts)
        FileUtils.cp(File.join(ROOT, name, 'Scripts/ManageExtension.zsh'), File.join(scripts, 'ManageExtension.zsh'))
        root_scripts = File.join(directory, 'Scripts')
        FileUtils.mkdir_p(root_scripts)
        File.write(File.join(root_scripts, 'ManageFinderExtensions.zsh'), "#!/bin/zsh\nprintf '%s\\n' \"$@\"\n")
        app = Dir.glob(File.join(ROOT, name, '【MacOS】*Finder扩展.app')).fetch(0)
        launcher = File.join(directory, name, File.basename(app), 'Contents/MacOS/LaunchManager')
        FileUtils.mkdir_p(File.dirname(launcher))
        FileUtils.cp(File.join(app, 'Contents/MacOS/LaunchManager'), launcher)
        output, result = Open3.capture2e('/bin/zsh', launcher, *arguments)
        assert result.success?, output
        assert_equal ['--scope', expected_scope, '--action', 'install', '--install-location', 'build', '--gui-session'], output.lines.map(&:chomp), name
        source = definitions(launcher) + <<~'ZSH'
          launch_management_error() { print -u2 blocked; return 2; }
          ZSH_ARGZERO="$1"
          shift
          main "$@"
        ZSH
        output, errors, result = execute(source, launcher, '--action', 'uninstall', '--non-interactive')
        assert_equal 2, result.exitstatus, output + errors
        assert_empty output
        assert_includes errors, 'blocked'
      end
    end
  end

  def test_bootstrap_compile_failure_uses_error_dialog_and_preserves_failure_status
    Dir.mktmpdir('jobs-panel-bootstrap-') do |directory|
      FileUtils.mkdir_p(File.join(directory, 'Scripts'))
      File.write(File.join(directory, 'Scripts', 'SelectFinderExtensionFeatures.swift'), '// fixture')
      helper = File.read(File.join(ROOT, 'Scripts', 'FinderManagerGUI.zsh')).gsub('/usr/bin/xcrun', 'fake_compiler')
      output, errors, result = execute(helper + <<~'ZSH', File.join(directory, 'Scripts', 'ManageFinderExtensions.zsh'), env: { 'TMPDIR' => "#{directory}/" })
        fake_compiler() { print -u2 simulated-compiler-error; return 23; }
        jobs_manager_launch_error() { print -r -- "DIALOG=$1|$2"; return 1; }
        jobs_launch_finder_manager_gui "$1" '' install 1
      ZSH
      assert_equal 23, result.exitstatus, errors
      assert_includes output, 'DIALOG='
      assert_includes output, '管理面板编译失败'
      logs = Dir.glob(File.join(directory, 'JobsFinderManagerLaunch.*'))
      assert_equal 1, logs.length
      assert_includes File.read(logs.first), 'simulated-compiler-error'
      refute File.exist?(File.join(directory, 'work', 'SelectFinderExtensionFeatures'))
    end
  end

  def test_changed_panel_source_replaces_stale_cached_binary_without_opening_gui
    Dir.mktmpdir('jobs-panel-source-update-') do |directory|
      scripts = File.join(directory, 'Scripts')
      FileUtils.mkdir_p([scripts, File.join(directory, 'work')])
      source = File.join(scripts, 'SelectFinderExtensionFeatures.swift')
      FileUtils.cp(File.join(ROOT, 'Scripts', 'SelectFinderExtensionFeatures.swift'), source)
      binary = File.join(directory, 'work', 'SelectFinderExtensionFeatures')
      File.write(binary, "#!/bin/zsh\nprint STALE-PANEL\n")
      File.chmod(0o755, binary)
      File.utime(Time.now - 10, Time.now - 10, binary)
      helper = File.read(File.join(ROOT, 'Scripts', 'FinderManagerGUI.zsh')).gsub('/usr/bin/xcrun', 'fake_compiler')
      output, errors, result = execute(helper + <<~'ZSH', File.join(scripts, 'ManageFinderExtensions.zsh'), env: { 'TMPDIR' => "#{directory}/" })
        fake_compiler() {
          [[ "$1" == swiftc && "$2" == -O && "$4" == -o ]] || return 91
          /usr/bin/grep -Fq 'failedStatusClicked' "$3" || return 92
          printf '#!/bin/zsh\nprint REFRESHED-PANEL\nprint -l -r -- "$@"\n' > "$5"
          /bin/chmod 755 "$5"
        }
        jobs_manager_launch_error() { print -u2 unexpected-error; return 1; }
        jobs_launch_finder_manager_gui "$1" 'git-pull' install 1
      ZSH
      assert result.success?, errors
      assert_equal ['REFRESHED-PANEL', '--manager', File.join(scripts, 'ManageFinderExtensions.zsh'), '--action', 'install', '--install-location', 'build', '--scope', 'git-pull'], output.lines.map(&:chomp)
      refute_includes File.read(binary), 'STALE-PANEL'
    end
  end
end
