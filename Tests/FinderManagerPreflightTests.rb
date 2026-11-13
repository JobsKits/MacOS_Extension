# frozen_string_literal: true
# 只在临时工程夹具中验证源码预检隔离；所有构建、登记、卸载与 Finder 刷新均被替身阻断。
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
require_relative 'IsolatedInstallerDefinitions'

class FinderManagerPreflightTests < Minitest::Test
  include IsolatedInstallerDefinitions
  ROOT = File.expand_path('..', __dir__)
  MANAGER = File.join(ROOT, 'Scripts/ManageFinderExtensions.zsh')
  SOURCE = File.read(MANAGER)
  KEYS = SOURCE[/^FEATURE_KEYS=\(([^)]+)\)/, 1].split.freeze
  PROJECTS = SOURCE.scan(/^FEATURE_PROJECT_DIR\[([^\]]+)\]="([^"]+)"/).to_h.freeze
  PANEL_FEATURES = File.read(File.join(ROOT, 'Scripts/SelectFinderExtensionFeatures.swift')).scan(/FeatureOption\(identifier: "([^"]+)"/).flatten.freeze

  def test_missing_unselected_project_does_not_block_selected_project
    output, errors, result = run_fixture('path_copier', available: ['path_copier'])
    assert result.success?, output + errors
    assert_includes output, 'INSTALL=path_copier'
    assert_includes output, 'SUMMARY=0|1|0'
    refute_includes output, 'JobsFileCreator.xcodeproj'
    refute_includes errors, 'blocked unexpected system operation'
  end

  def test_selecting_every_leaf_with_one_missing_project_only_fails_that_unit
    output, errors, result = run_fixture(PANEL_FEATURES.join(','), available: KEYS - ['file-create'])
    assert_equal 1, result.exitstatus, output + errors
    installs = output.lines.grep(/^INSTALL=/).map { |line| line.chomp.delete_prefix('INSTALL=') }
    assert_equal (KEYS - ['file-create']).sort, installs.sort
    assert_includes output, "SUMMARY=1|#{PANEL_FEATURES.length - 1}|1"
    assert_includes output, 'JobsFileCreator/JobsFileCreator.xcodeproj/project.pbxproj'
    events = output.lines.grep(/^JOBS_MANAGER_EVENT\t/).map { |line| line.split("\t")[1, 2] }
    assert_equal [['file-create', 'failed']], events.select { |_, state| state == 'failed' }
    assert_equal PANEL_FEATURES.length - 1, events.count { |_, state| state == 'succeeded' }
    assert_includes output, "JOBS_MANAGER_EVENT\tflutter-maintenance\tsucceeded"
    refute_includes errors, 'blocked unexpected system operation'
  end

  def test_missing_shared_project_fails_its_selected_leaves_and_continues
    output, errors, result = run_fixture('git-pull,git-rollback,path_copier', available: ['path_copier'])
    assert_equal 1, result.exitstatus, output + errors
    assert_equal ['INSTALL=path_copier'], output.lines.map(&:chomp).grep(/^INSTALL=/)
    assert_includes output, 'SUMMARY=1|1|2'
    assert_includes output, 'JobsProjectTools/JobsProjectTools.xcodeproj/project.pbxproj'
    assert_includes output, "JOBS_MANAGER_EVENT\tgit-pull\tfailed"
    assert_includes output, "JOBS_MANAGER_EVENT\tgit-rollback\tfailed"
    refute_includes output, 'JobsFileCreator.xcodeproj'
    refute_includes errors, 'blocked unexpected system operation'
  end

  def test_hash_and_permission_units_remain_independent_in_both_operation_plans
    selection = 'file-hash,run-authorize,run-revoke'
    expected = %w[file-hash run-authorize run-revoke]
    output, errors, result = run_fixture(selection, available: expected)
    assert result.success?, output + errors
    assert_equal expected.map { |key| "INSTALL=#{key}" }, output.lines.map(&:chomp).grep(/^INSTALL=/)
    assert_includes output, 'SUMMARY=0|3|0'
    output, errors, result = run_fixture(selection, available: [], action: 'uninstall')
    assert result.success?, output + errors
    assert_equal expected.map { |key| "UNINSTALL=#{key}" }, output.lines.map(&:chomp).grep(/^UNINSTALL=/)
    refute_includes errors, 'blocked unexpected system operation'
  end

  def test_no_argument_source_diagnostic_only_checks_the_selected_plan
    output, errors, result = run_fixture('path_copier', available: ['path_copier'], checks: <<~'ZSH')
      parse_feature_selection "$CLI_FEATURES" || exit 1
      ensure_feature_projects_exist || exit 1
      print -r -- selected-project-ready
    ZSH
    assert result.success?, output + errors
    assert_equal "selected-project-ready\n", output
  end

  def test_missing_selected_source_reports_the_exact_runtime_path_before_any_work
    output, errors, result = run_fixture('file-create', available: [])
    assert_equal 1, result.exitstatus, output + errors
    assert_includes output, 'SUMMARY=1|0|1'
    assert_match(%r{jobs-finder-preflight-[^\n]+/搬迁后的源码 中文/JobsFileCreator/JobsFileCreator\.xcodeproj/project\.pbxproj}, output)
    refute_match(/^(?:INSTALL|UNINSTALL)=/, output)
    refute_includes errors, 'blocked unexpected system operation'
  end

  def test_required_global_environment_failures_still_stop_before_all_work
    [
      { 'JOBS_TEST_PLATFORM' => 'Linux' },
      { 'JOBS_TEST_MISSING_COMMAND' => 'pluginkit' },
      { 'JOBS_TEST_XCODE_RESULT' => '1' },
      { 'JOBS_TEST_MISSING_LSREGISTER' => '1' }
    ].each do |environment|
      output, errors, result = run_fixture('path_copier', available: ['path_copier'], environment: environment)
      assert_equal 1, result.exitstatus, environment.inspect + output + errors
      refute_match(/^(?:INSTALL|UNINSTALL|REFRESH)=/, output)
      refute_includes output, "JOBS_MANAGER_EVENT\t"
      refute_includes errors, 'blocked unexpected system operation'
    end
  end

  def test_uninstall_does_not_require_project_sources_or_xcode
    output, errors, result = run_fixture('path_copier,file-create', available: [], action: 'uninstall', environment: { 'JOBS_TEST_XCODE_RESULT' => '1' })
    assert result.success?, output + errors
    assert_equal ['UNINSTALL=path_copier', 'UNINSTALL=file-create'], output.lines.map(&:chomp).grep(/^UNINSTALL=/)
    assert_includes output, 'SUMMARY=0|2|0'
    refute_includes output, '.xcodeproj/project.pbxproj'
    refute_includes errors, 'blocked unexpected system operation'
  end

  private

  def run_fixture(selection, available:, action: 'install', environment: {}, checks: nil)
    replacements = {
      '/usr/bin/xcode-select' => 'jobs_fixture_xcode_select',
      'command -v "$command_name"' => 'jobs_fixture_command_present "$command_name"'
    }
    definitions = isolated_installer_source(MANAGER, replacements: replacements)
    Dir.mktmpdir('jobs-finder-preflight-') do |temporary|
      workspace = File.join(File.realpath(temporary), '搬迁后的源码 中文')
      FileUtils.mkdir_p(workspace)
      available.each do |key|
        project = File.join(workspace, PROJECTS.fetch(key), "#{PROJECTS.fetch(key)}.xcodeproj")
        FileUtils.mkdir_p(project)
        File.write(File.join(project, 'project.pbxproj'), '// isolated source-presence fixture; never built')
      end
      File.write(File.join(workspace, 'selector.swift'), '// isolated UI source presence fixture')
      setup = <<~'ZSH'
        WORKSPACE_DIR="$1"
        FEATURE_SELECTOR_SOURCE_PATH="$WORKSPACE_DIR/selector.swift"
        LOG_FILE="$WORKSPACE_DIR/session.log"
        CLI_FEATURES="$2"
        MANAGEMENT_ACTION="$3"
        MANAGER_NON_INTERACTIVE=1
        [[ "$CLI_FEATURES" == all ]] && CLI_FEATURES="${(j:,:)SELECTABLE_FUNCTION_IDS}"
        uname() { print -r -- "${JOBS_TEST_PLATFORM:-Darwin}"; }
        jobs_fixture_command_present() { [[ "$1" != "${JOBS_TEST_MISSING_COMMAND:-}" ]]; }
        jobs_fixture_xcode_select() { return "${JOBS_TEST_XCODE_RESULT:-0}"; }
        lsregister_path() { [[ "${JOBS_TEST_MISSING_LSREGISTER:-0}" == 0 ]] && print -r -- fixture-lsregister; }
        install_feature() { print -r -- "INSTALL=$1"; }
        uninstall_feature() { print -r -- "UNINSTALL=$1"; }
        restart_finder_after_install() { print -r -- 'REFRESH=fixture-only'; }
      ZSH
      checks ||= <<~'ZSH'
        run_management_worker
        worker_result=$?
        print -r -- "SUMMARY=$worker_result|${#SUCCEEDED_FEATURES[@]}|${#FAILED_FEATURES[@]}"
        exit "$worker_result"
      ZSH
      fixture = File.join(temporary, 'preflight.zsh')
      File.write(fixture, definitions + setup + checks)
      Open3.capture3(isolated_installer_environment(temporary).merge(environment), '/bin/zsh', '-f', fixture, workspace, selection, action)
    end
  end
end
