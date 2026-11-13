# frozen_string_literal: true
# 在临时配置和命令替身下验证统一管理计划，不构建、登记扩展或刷新 Finder。
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

class FinderManagerTests < Minitest::Test
  ROOT = File.expand_path('..', __dir__)
  MANAGER = File.join(ROOT, 'Scripts/ManageFinderExtensions.zsh')

  def run_definitions(checks, *arguments, stdin: '', replacements: {}, real_location: false)
    source = File.read(MANAGER).sub(/^main "\$@"\s*\z/, '')
    replacements.each { |from, to| source = source.gsub(from, to) }
    Dir.mktmpdir('jobs-finder-manager-') do |directory|
      fixture = File.join(directory, '管理 定义.zsh')
      # These cases isolate shared feature configuration; location guards have separate filesystem fixtures.
      location_guards = real_location ? '' : "selected_location_has_app() { return 0; }\nanother_location_is_active() { return 1; }\n"
      File.write(fixture, source + "\nLOG_FILE=/dev/null\n" + location_guards + checks)
      Open3.capture3('/bin/zsh', fixture, *arguments, stdin_data: stdin)
    end
  end

  def test_explicit_scope_and_action_form_one_deduplicated_plan
    output, errors, status = run_definitions(<<~'ZSH')
      parse_management_options --scope git-pull,git-rollback --features git-pull,git-pull,git-rollback --action uninstall --non-interactive || exit $?
      select_management_features || exit $?
      print -r -- "$MANAGEMENT_ACTION|${(j:,:)SELECTED_KEYS}|${(j:,:)SELECTED_FUNCTION_IDS}"
    ZSH
    assert status.success?, errors
    assert_equal "uninstall|project-tools|git-pull,git-rollback\n", output
  end

  def test_invalid_unknown_empty_or_out_of_scope_parameters_stop
    [
      %w[--non-interactive],
      %w[--action uninstall --non-interactive],
      %w[--action erase],
      ['--scope', ''],
      %w[--scope unknown],
      %w[--scope git-pull --action uninstall --features git-rollback --non-interactive],
      %w[--action uninstall --features git-pull, --non-interactive],
      %w[--action uninstall --features git-pull,,git-rollback --non-interactive],
      %w[--features git-pull]
    ].each do |arguments|
      _, _, status = run_definitions('parse_management_options "$@"', *arguments)
      refute status.success?, arguments.inspect
    end
  end

  def test_panel_install_and_uninstall_execute_without_another_terminal_read
    %w[install uninstall].each do |action|
      output, errors, status = run_definitions(<<~'ZSH', action)
        MANAGEMENT_ACTION="$1"
        MANAGER_NON_INTERACTIVE=1
        CLI_FEATURES=path_copier
        show_script_intro_and_wait() { return 0; }
        init_runtime() { return 0; }
        select_management_features() { parse_feature_selection path_copier; }
        read() { print -u2 'unexpected terminal confirmation'; return 99; }
        check_environment() { return 0; }
        install_selected_features() { print 'BUSINESS=install'; }
        uninstall_selected_features() { print 'BUSINESS=uninstall'; }
        restart_finder_after_install() { return 0; }
        print_done_tips() { return 0; }
        main
      ZSH
      assert status.success?, errors
      assert_includes output, "BUSINESS=#{action}"
      refute_includes errors, 'unexpected terminal confirmation'
    end
  end

  def test_partial_flutter_uninstall_keeps_sibling_and_never_unloads_package
    Dir.mktmpdir('jobs-flutter-partial-') do |directory|
      config = File.join(directory, '配置 带空格', 'flutter.conf')
      FileUtils.mkdir_p(File.dirname(config))
      File.write(config, 'run,package-android,codegen')
      output, errors, status = run_definitions(<<~'ZSH', config)
        FLUTTER_FEATURE_CONFIG_PATH="$1"
        MANAGEMENT_ACTION=uninstall
        parse_feature_selection flutter-package-android || exit 1
        run_independent_uninstall() { print 'unexpected-full-uninstall'; return 99; }
        uninstall_feature flutter-tools || exit 1
      ZSH
      assert status.success?, errors
      refute_includes output, 'unexpected-full-uninstall'
      assert_equal 'run,codegen', File.read(config)
    end
  end

  def test_last_flutter_action_unloads_only_its_package
    Dir.mktmpdir('jobs-flutter-last-') do |directory|
      config = File.join(directory, 'flutter.conf')
      File.write(config, 'package-android')
      output, errors, status = run_definitions(<<~'ZSH', config)
        FLUTTER_FEATURE_CONFIG_PATH="$1"
        MANAGEMENT_ACTION=uninstall
        parse_feature_selection flutter-package-android || exit 1
        run_independent_uninstall() { print -r -- "unload:$1"; }
        uninstall_feature flutter-tools
      ZSH
      assert status.success?, errors
      assert_includes output, 'unload:flutter-tools'
      refute_includes output, 'unload:terminal_opener'
    end
  end

  def test_terminal_uninstall_preserves_current_and_legacy_siblings
    Dir.mktmpdir('jobs-terminal-partial-') do |directory|
      config = File.join(directory, 'terminal.conf')
      File.write(config, 'open,pod-install,codegraph-bootstrap')
      _, errors, status = run_definitions(<<~'ZSH', config)
        TERMINAL_FEATURE_CONFIG_PATH="$1"
        MANAGEMENT_ACTION=uninstall
        parse_feature_selection terminal_open || exit 1
        run_independent_uninstall() { return 99; }
        uninstall_feature terminal_opener
      ZSH
      assert status.success?, errors
      assert_equal 'pod-install,codegraph-bootstrap', File.read(config)
    end
  end

  def test_file_viewer_maps_to_terminal_and_uninstalls_only_its_action
    Dir.mktmpdir('jobs-file-viewer-selection-') do |directory|
      config = File.join(directory, 'terminal.conf')
      File.write(config, 'open,file-content,pod-install,codegraph-bootstrap')
      output, errors, status = run_definitions(<<~'ZSH', config)
        TERMINAL_FEATURE_CONFIG_PATH="$1"
        parse_feature_selection file_content,file_content || exit 1
        print -r -- "${(j:,:)SELECTED_KEYS}|$TERMINAL_OPENER_ENABLED_FEATURES"
        validate_group_configuration terminal_opener 'file-content' || exit 1
        run_independent_uninstall() { print 'unexpected-full-uninstall'; return 99; }
        uninstall_feature terminal_opener || exit 1
      ZSH
      assert status.success?, errors
      assert_includes output, 'terminal_opener|file-content'
      refute_includes output, 'unexpected-full-uninstall'
      assert_equal 'open,pod-install,codegraph-bootstrap', File.read(config)
    end
  end

  def test_installing_file_viewer_preserves_existing_terminal_choices
    Dir.mktmpdir('jobs-file-viewer-add-') do |directory|
      config = File.join(directory, 'terminal.conf')
      File.write(config, 'open,codegraph-bootstrap')
      _, errors, status = run_definitions(<<~'ZSH', config)
        TERMINAL_FEATURE_CONFIG_PATH="$1"
        TERMINAL_FEATURE_CONFIG_DIR="${1:h}"
        parse_feature_selection file_content || exit 1
        build_feature() { return 0; }
        register_and_enable_feature() { return 0; }
        deploy_feature_to_applications() { ROOT_DEPLOYMENT_ACTIVE=0; return 0; }
        install_feature terminal_opener || exit 1
      ZSH
      assert status.success?, errors
      assert_equal %w[open codegraph-bootstrap file-content].sort, File.read(config).split(',').sort
    end
  end

  def test_terminal_missing_user_config_reads_enabled_app_default
    Dir.mktmpdir('jobs-terminal-fallback-') do |directory|
      app = File.join(directory, '中文 目录', 'JobsTerminalOpener.app')
      info = File.join(app, 'Contents', 'Info.plist')
      FileUtils.mkdir_p(File.dirname(info))
      File.write(info, '<?xml version="1.0"?><plist version="1.0"><dict><key>JobsTerminalEnabledFeatures</key><string>open,codegraph-bootstrap</string></dict></plist>')
      extension = File.join(app, 'Contents', 'PlugIns', 'JobsTerminalFinderSync.appex')
      output, errors, status = run_definitions(<<~'ZSH', File.join(directory, 'missing'), extension, replacements: {'/usr/bin/pluginkit' => 'fake_pluginkit'})
        TERMINAL_FEATURE_CONFIG_PATH="$1"
        MANAGEMENT_ACTION=uninstall
        records="$2"
        fake_pluginkit() { print -r -- '+ com.jobs.JobsTerminalOpener.FinderSyncExtension'; print -r -- "    Path = $records"; }
        parse_feature_selection terminal_open || exit 1
        plan_group_feature_removal terminal_opener || exit 1
        print -r -- "remaining:$REMAINING_CONFIG_FEATURES"
      ZSH
      assert status.success?, errors
      assert_includes output, 'remaining:codegraph-bootstrap'
      refute_includes output, 'pod-install'
    end
  end

  def test_symlink_configuration_is_rejected_before_unload_or_write
    Dir.mktmpdir('jobs-config-link-') do |directory|
      original = File.join(directory, 'original')
      config = File.join(directory, 'linked')
      File.write(original, 'run,codegen')
      File.symlink(original, config)
      _, _, status = run_definitions(<<~'ZSH', config)
        FLUTTER_FEATURE_CONFIG_PATH="$1"
        parse_feature_selection flutter-codegen || exit 1
        MANAGEMENT_ACTION=uninstall
        run_independent_uninstall() { return 0; }
        uninstall_feature flutter-tools
      ZSH
      refute status.success?
      assert_equal 'run,codegen', File.read(original)
    end
  end

  def test_malformed_group_configuration_stops_before_overwrite
    Dir.mktmpdir('jobs-invalid-config-') do |directory|
      config = File.join(directory, 'flutter.conf')
      ['run,unknown', 'run,,codegen', 'run,run', ',run', 'run,'].each do |value|
        File.write(config, value)
        _, _, status = run_definitions(<<~'ZSH', config)
          FLUTTER_FEATURE_CONFIG_PATH="$1"
          parse_feature_selection flutter-codegen || exit 1
          run_independent_uninstall() { return 0; }
          uninstall_feature flutter-tools
        ZSH
        refute status.success?, value
        assert_equal value, File.read(config)
      end
    end
  end

  def test_missing_or_disabled_flutter_registration_does_not_enable_old_defaults
    ['  (no matches)', '- com.jobs.JobsFlutterTools.FinderSyncExtension'].each do |records|
      output, errors, status = run_definitions(<<~'ZSH', records, replacements: {'/usr/bin/pluginkit' => 'fake_pluginkit'})
        FLUTTER_FEATURE_CONFIG_PATH="${0:h}/missing"
        records="$1"
        fake_pluginkit() { print -r -- "$records"; }
        read_group_configuration flutter-tools
      ZSH
      assert status.success?, errors
      assert_empty output
    end
  end

  def test_bad_ios_configuration_stops_before_build_and_keeps_file
    Dir.mktmpdir('jobs-ios-invalid-') do |directory|
      config = File.join(directory, 'ios.conf')
      File.write(config, 'ios-pod-install,unknown')
      output, _, status = run_definitions(<<~'ZSH', config)
        IOS_FEATURE_CONFIG_PATH="$1"
        parse_feature_selection ios-code-snippets || exit 1
        build_feature() { print 'unexpected-build'; return 0; }
        install_feature ios-tools
      ZSH
      refute status.success?
      refute_includes output, 'unexpected-build'
      assert_equal 'ios-pod-install,unknown', File.read(config)
    end
  end

  def test_project_and_desktop_delegates_receive_only_selected_leaf_ids
    output, errors, status = run_definitions(<<~'ZSH', replacements: {'/bin/zsh "$WORKSPACE_DIR/JobsProjectTools/Scripts/ManageProjectTools.zsh"' => 'record_project', '/bin/zsh "$WORKSPACE_DIR/JobsDesktopTools/Scripts/ManageDesktopTools.zsh"' => 'record_desktop'})
      record_project() { print -r -- "project:${(j:|:)@}"; }
      record_desktop() { print -r -- "desktop:${(j:|:)@}"; }
      parse_feature_selection git-rollback,android-simulator-repair || exit 1
      uninstall_selected_features || exit 1
    ZSH
    assert status.success?, errors
    assert_includes output, 'project:uninstall|git-rollback'
    assert_includes output, 'desktop:uninstall|android-simulator-repair|--non-interactive|--skip-finder-restart'
    refute_includes output, 'git-pull'
  end

  def test_installing_one_flutter_action_keeps_existing_choices
    Dir.mktmpdir('jobs-flutter-add-') do |directory|
      config = File.join(directory, 'flutter.conf')
      File.write(config, 'run')
      _, errors, status = run_definitions(<<~'ZSH', config)
        FLUTTER_FEATURE_CONFIG_PATH="$1"
        FLUTTER_FEATURE_CONFIG_DIR="${1:h}"
        parse_feature_selection flutter-codegen || exit 1
        build_feature() { return 0; }
        register_and_enable_feature() { return 0; }
        deploy_feature_to_applications() { ROOT_DEPLOYMENT_ACTIVE=0; return 0; }
        install_feature flutter-tools
      ZSH
      assert status.success?, errors
      assert_equal 'run,codegen', File.read(config)
    end
  end

  def test_failure_reports_selected_leaf_and_keeps_failure_status
    output, errors, status = run_definitions(<<~'ZSH')
      parse_feature_selection git-pull,run-authorize || exit 1
      uninstall_feature() { [[ "$1" == project-tools ]]; }
      uninstall_selected_features
      print -r -- "result:$FINAL_EXIT_STATUS|${(j:,:)SUCCEEDED_FEATURES}|${(j:,:)FAILED_FEATURES}"
    ZSH
    assert status.success?, errors
    assert_includes output, 'result:1|拉取 Git 到最新|授予执行权限（chmod +x）'
  end

  def test_aggregate_pipeline_preserves_each_worker_failure_before_if_finishes
    {
      'git-pull,git-rollback' => ['project-tools', 37],
      'android-simulator-create,harmony-simulator-create' => ['desktop-tools', 47]
    }.each do |selection, (key, expected)|
      replacements = {
        '/bin/zsh "$WORKSPACE_DIR/JobsProjectTools/Scripts/ManageProjectTools.zsh"' => 'failed_worker',
        '/bin/zsh "$WORKSPACE_DIR/JobsDesktopTools/Scripts/ManageDesktopTools.zsh"' => 'failed_worker'
      }
      output, errors, status = run_definitions(<<~'ZSH', selection, key, expected.to_s, replacements: replacements)
        expected="$3"
        failed_worker() { print -r -- "original-worker-failure=$expected"; return "$expected"; }
        parse_feature_selection "$1" || exit 1
        result=0
        uninstall_feature "$2" || result=$?
        print -r -- "preserved-result=$result"
      ZSH
      assert status.success?, errors
      assert_includes output, "original-worker-failure=#{expected}"
      assert_includes output, "preserved-result=#{expected}"
    end
  end

  def test_missing_group_and_single_locations_have_separate_completion_state
    output, errors, status = run_definitions(<<~'ZSH')
      MANAGEMENT_ACTION=uninstall
      selected_location_has_app() { return 1; }
      run_independent_uninstall() { print unexpected-uninstall; return 99; }
      parse_feature_selection git-pull,android-simulator-create,file-hash || exit 1
      uninstall_selected_features
      print -r -- "result:$FINAL_EXIT_STATUS|success:${#SUCCEEDED_FEATURES}|absent:${#NOT_INSTALLED_FEATURES}|failed:${#FAILED_FEATURES}"
      print_done_tips
    ZSH
    assert status.success?, errors
    assert_includes output, 'result:0|success:0|absent:3|failed:0'
    assert_includes output, "JOBS_MANAGER_EVENT\tgit-pull\tnot-installed\t所选位置未安装，无需卸载"
    assert_includes output, "JOBS_MANAGER_EVENT\tandroid-simulator-create\tnot-installed"
    assert_includes output, "JOBS_MANAGER_EVENT\tfile-hash\tnot-installed"
    assert_includes output, '卸载按安装单元汇总：成功 0，所选位置未安装 3，失败 0'
    refute_includes output, 'unexpected-uninstall'
    refute_includes output, "\tsucceeded\t"
  end

  def test_real_worker_exit_three_is_not_confused_with_missing_installation
    replacements = {
      '/bin/zsh "$WORKSPACE_DIR/JobsProjectTools/Scripts/ManageProjectTools.zsh"' => 'failed_worker'
    }
    output, errors, status = run_definitions(<<~'ZSH', replacements: replacements)
      MANAGEMENT_ACTION=uninstall
      failed_worker() { return 3; }
      parse_feature_selection git-pull || exit 1
      uninstall_selected_features
      print -r -- "result:$FINAL_EXIT_STATUS|absent:${#NOT_INSTALLED_FEATURES}|failed:${#FAILED_FEATURES}"
    ZSH
    assert status.success?, errors
    assert_includes output, 'result:1|absent:0|failed:1'
    assert_includes output, '退出码 3'
    assert_includes output, "JOBS_MANAGER_EVENT\tgit-pull\tfailed"
    refute_includes output, "\tnot-installed\t"
  end

  def test_shared_failure_summary_reports_one_installation_unit_and_multiple_menu_items
    output, errors, status = run_definitions(<<~'ZSH')
      MANAGEMENT_ACTION=uninstall
      parse_feature_selection git-pull,git-rollback,file-hash || exit 1
      uninstall_feature() {
        if [[ "$1" == file-hash ]]; then
          UNINSTALL_OUTCOME=not-installed
          return 3
        fi
        return 9
      }
      uninstall_selected_features
      print_done_tips
    ZSH
    refute status.success?, errors
    assert_equal 1, status.exitstatus
    assert_includes output, '关联的 2 项菜单共同标记失败'
    assert_includes output, '卸载按安装单元汇总：成功 0，所选位置未安装 1，失败 1，未执行 0；菜单项：成功 0，无需卸载 1，失败 2，未执行 0'
    assert_includes output, '失败安装单元：IDE 项目工具 / Git操作'
  end

  def test_aggregate_build_location_matches_each_independent_manager
    output, errors, status = run_definitions(<<~'ZSH')
      WORKSPACE_DIR='/temporary/源码 中文'
      JOBS_FINDER_INSTALL_LOCATION=build
      app_path_for_key project-tools
      app_path_for_key desktop-tools
      JOBS_FINDER_INSTALL_LOCATION=applications
      JOBS_FINDER_APPLICATIONS_DIR='/temporary/应用程序'
      app_path_for_key project-tools
    ZSH
    assert status.success?, errors
    assert_includes output, '/temporary/源码 中文/JobsProjectTools/work/DerivedData/Build/Products/Debug/JobsProjectTools.app'
    assert_includes output, '/temporary/源码 中文/JobsDesktopTools/work/DerivedData/Build/Products/Debug/JobsDesktopTools.app'
    assert_includes output, '/temporary/应用程序/Jobs自定义右键菜单.app/Contents/Applications/JobsProjectTools.app'
  end

  def test_absent_aggregate_app_only_checks_its_selected_location_and_never_calls_worker
    Dir.mktmpdir('jobs-uninstall-absence-') do |workspace|
      output, errors, status = run_definitions(<<~'ZSH', workspace, real_location: true)
        WORKSPACE_DIR="$1"
        JOBS_FINDER_INSTALL_LOCATION=build
        MANAGEMENT_ACTION=uninstall
        parse_feature_selection git-pull,android-simulator-create || exit 1
        load_deployment_support() { print unexpected-deployment-library; return 99; }
        uninstall_selected_features
        print -r -- "result:$FINAL_EXIT_STATUS|absent:${#NOT_INSTALLED_FEATURES}|failed:${#FAILED_FEATURES}"
      ZSH
      assert status.success?, errors
      assert_includes output, 'result:0|absent:2|failed:0'
      refute_includes output, 'unexpected-deployment-library'
    end
  end

  def test_non_directory_app_collision_is_failure_not_absence
    Dir.mktmpdir('jobs-uninstall-collision-') do |workspace|
      app = File.join(workspace, 'work/JobsFileHasherDerivedData/Build/Products/Debug/JobsFileHasher.app')
      FileUtils.mkdir_p(File.dirname(app))
      File.write(app, 'preserve existing file')
      output, errors, status = run_definitions(<<~'ZSH', workspace, real_location: true)
        WORKSPACE_DIR="$1"
        JOBS_FINDER_INSTALL_LOCATION=build
        MANAGEMENT_ACTION=uninstall
        parse_feature_selection file-hash || exit 1
        uninstall_selected_features
        print -r -- "result:$FINAL_EXIT_STATUS|absent:${#NOT_INSTALLED_FEATURES}|failed:${#FAILED_FEATURES}"
      ZSH
      assert status.success?, errors
      assert_includes output, 'result:1|absent:0|failed:1'
      assert_includes output, '非目录对象占用'
      assert_equal 'preserve existing file', File.read(app)
    end
  end

  def test_app_management_block_keeps_completed_and_absent_results_and_skips_later_units
    output, errors, status = run_definitions(<<~'ZSH')
      MANAGEMENT_ACTION=uninstall
      parse_feature_selection git-pull,file-hash,run-authorize,flutter-run,ios-pod-update || exit 1
      uninstall_feature() {
        print -r -- "attempt:$1"
        case "$1" in
          project-tools) return 0 ;;
          file-hash) UNINSTALL_OUTCOME=not-installed; return 3 ;;
          run-authorize) return 77 ;;
          *) print unexpected-later-uninstall; return 99 ;;
        esac
      }
      uninstall_selected_features
      print -r -- "result:$FINAL_EXIT_STATUS|success:${#SUCCEEDED_FEATURES}|absent:${#NOT_INSTALLED_FEATURES}|failed:${#FAILED_FEATURES}|skipped:${#UNINSTALL_SKIPPED_FEATURES}"
      print_done_tips
    ZSH
    assert_equal 77, status.exitstatus, errors
    assert_includes output, 'result:77|success:1|absent:1|failed:1|skipped:2'
    assert_includes output, "JOBS_MANAGER_BLOCKED\tapp-management\t77"
    assert_includes output, "JOBS_MANAGER_EVENT\tflutter-run\tskipped"
    assert_includes output, "JOBS_MANAGER_EVENT\tios-pod-update\tskipped"
    refute_includes output, 'attempt:flutter-tools'
    refute_includes output, 'attempt:ios-tools'
    refute_includes output, 'unexpected-later-uninstall'
  end

  def test_app_management_control_file_cannot_be_hidden_by_child_success_code
    Dir.mktmpdir('jobs-uninstall-blocked-') do |directory|
      marker = File.join(directory, 'app-management.blocked')
      File.write(marker, '')
      output, errors, status = run_definitions(<<~'ZSH', marker)
        MANAGEMENT_ACTION=uninstall
        JOBS_FINDER_BLOCKED_FILE="$1"
        parse_feature_selection git-pull,path_copier || exit 1
        uninstall_feature() {
          print -r -- "attempt:$1"
          print -r -- app-management > "$JOBS_FINDER_BLOCKED_FILE"
          return 0
        }
        uninstall_selected_features
        print -r -- "result:$FINAL_EXIT_STATUS|success:${#SUCCEEDED_FEATURES}|failed:${#FAILED_FEATURES}|skipped:${#UNINSTALL_SKIPPED_FEATURES}"
      ZSH
      assert status.success?, errors
      assert_includes output, 'result:77|success:0|failed:1|skipped:1'
      refute_includes output, 'attempt:path_copier'
      assert_includes output, "JOBS_MANAGER_EVENT\tgit-pull\tfailed"
      assert_includes output, "JOBS_MANAGER_EVENT\tpath_copier\tskipped"
    end
  end
end
