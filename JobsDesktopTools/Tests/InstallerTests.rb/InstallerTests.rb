# frozen_string_literal: true
# 使用真实配置发布与临时文件，系统登记和构建由函数替身承接。
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
require 'open3'
require 'json'
require 'digest'

require_relative '../../../Tests/SourceLayoutHelper.rb/SourceLayoutHelper'

class DesktopInstallerTests < Minitest::Test
  ROOT = File.expand_path('..', File.dirname(__dir__))
  MANAGER = JobsSourceLayout.file(File.join(ROOT, 'Scripts/【MacOS】ManageDesktopTools.zsh/【MacOS】ManageDesktopTools.zsh'))

  def test_prepare_context_resolves_wrapped_and_published_manager_paths
    Dir.mktmpdir('jobs-desktop-context-') do |directory|
      directory = File.realpath(directory)
      source = File.read(MANAGER).sub(/^main "\$@"\s*\z/, '')
      deployment = File.join(ROOT, 'Scripts/【MacOS】AppDeployment.zsh/【MacOS】AppDeployment.zsh')
      ['ManageDesktopTools.zsh', '【MacOS】ManageDesktopTools.zsh/【MacOS】ManageDesktopTools.zsh'].each do |entry|
        project = File.join(directory, "迁移 后的桌面工具 #{entry.include?('/') ? '源码' : '发布'}")
        manager = File.join(project, 'Scripts', entry)
        library = File.join(project, 'Scripts/【MacOS】AppDeployment.zsh/【MacOS】AppDeployment.zsh')
        FileUtils.mkdir_p(File.dirname(manager))
        FileUtils.mkdir_p(File.dirname(library))
        File.write(manager, source)
        FileUtils.cp(deployment, library)
        checks = <<~'ZSH'
          source "$1" || exit $?
          resolved="$(jobs_layout_directory "$1" 1)"
          [[ "$resolved" == "$2" ]] || exit 2
          prepare_context uninstall hidden-files-toggle --non-interactive --install-location build || exit $?
          [[ "$PROJECT_ROOT" == "$2" ]] || exit 3
          [[ "$BUILT_APP_PATH" == "$2/work/DerivedData/Build/Products/Debug/JobsDesktopTools.app" ]] || exit 4
          [[ "$APP_PATH" == "$BUILT_APP_PATH" ]] || exit 5
          [[ "$JOBS_DEPLOYMENT_MODULE_DIRECTORY" == "$2/Scripts/【MacOS】AppDeployment.zsh" ]] || exit 6
        ZSH
        output, status = Open3.capture2e(
          {'NO_COLOR' => '1', 'LC_ALL' => 'C', 'JOBS_FINDER_INSTALL_LOCATION' => 'build', 'JOBS_FINDER_CLEANUP_BUILD_PRODUCTS' => '0'},
          '/bin/zsh', '-ef', '-c', checks, 'desktop-context', manager, project, chdir: directory
        )
        assert status.success?, "#{entry}: #{output} (exit #{status.exitstatus})"
      end
    end
  end

  def test_first_install_migrates_only_enabled_legacy_leaves
    run_checks(<<~'ZSH')
      OPERATION=install
      REQUESTED=(ios-simulator-create)
      extension_is_enabled() { [[ "$1" == com.jobs.androidsimulatorrepairer.findersync ]]; }
      read_configuration && plan_configuration && publish_configuration || exit 1
      [[ "$(<"$CONFIG_PATH")" == ios-simulator-create,android-simulator-repair ]] || exit 2
      [[ ! -e "$MARKER_PATH" ]] || exit 3
    ZSH
  end

  def test_existing_selection_is_preserved_without_remigrating_closed_leaves
    run_checks(<<~'ZSH')
      print -nr -- hidden-files-toggle > "$CONFIG_PATH"
      OPERATION=install
      REQUESTED=(ios-simulator-create)
      extension_is_enabled() { return 0; }
      read_configuration && plan_configuration && publish_configuration || exit 1
      [[ "$(<"$CONFIG_PATH")" == ios-simulator-create,hidden-files-toggle ]] || exit 2
    ZSH
  end

  def test_failed_retirement_restores_original_configuration
    run_checks(<<~'ZSH')
      print -nr -- hidden-files-toggle > "$CONFIG_PATH"
      /bin/chmod 640 "$CONFIG_PATH"
      OPERATION=install
      REQUESTED=(ios-simulator-create)
      build_and_verify() { return 0; }
      register_and_verify() { return 0; }
      retire_legacy() { return 7; }
      read_configuration && plan_configuration || exit 1
      if install_features; then exit 2; fi
      rollback_transaction
      [[ "$(<"$CONFIG_PATH")" == hidden-files-toggle ]] || exit 3
      [[ "$(/usr/bin/stat -f %Lp "$CONFIG_PATH")" == 640 ]] || exit 4
      [[ ! -e "$MARKER_PATH" ]] || exit 5
    ZSH
  end

  def test_registration_failure_publishes_nothing_and_keeps_legacy_state
    run_checks(<<~'ZSH')
      OPERATION=install
      REQUESTED=(ios-simulator-create)
      build_and_verify() { print -r -- build >> "$TRANSACTION_DIR/calls"; return 0; }
      register_and_verify() { print -r -- register >> "$TRANSACTION_DIR/calls"; return 7; }
      retire_legacy() { print -r -- retire >> "$TRANSACTION_DIR/calls"; return 0; }
      read_configuration && plan_configuration || exit 1
      if install_features; then exit 2; fi
      [[ ! -e "$CONFIG_PATH" && ! -e "$MARKER_PATH" ]] || exit 3
      [[ "$(<"$TRANSACTION_DIR/calls")" == $'build\nregister' ]] || exit 4
    ZSH
  end

  def test_failure_after_migration_marker_publication_restores_both_files
    [false, true].each do |had_marker|
      run_checks(<<~ZSH)
        #{had_marker ? 'print -nr -- previous > "$MARKER_PATH"' : ':'}
        OPERATION=install
        REQUESTED=(ios-simulator-create)
        build_and_verify() { return 0; }
        register_and_verify() { return 0; }
        retire_legacy() { return 0; }
        functions[real_publish_marker]="$functions[publish_marker]"
        publish_marker() { real_publish_marker || return 1; return 7; }
        read_configuration && plan_configuration || exit 1
        if install_features; then exit 2; fi
        [[ "$(<"$MARKER_PATH")" == 1 ]] || exit 3
        rollback_transaction
        [[ ! -e "$CONFIG_PATH" ]] || exit 4
        #{had_marker ? '[[ "$(<"$MARKER_PATH")" == previous ]] || exit 5' : '[[ ! -e "$MARKER_PATH" ]] || exit 5'}
      ZSH
    end
  end

  def test_external_configuration_edit_is_preserved
    run_checks(<<~'ZSH')
      print -nr -- hidden-files-toggle > "$CONFIG_PATH"
      OPERATION=install
      REQUESTED=(ios-simulator-create)
      read_configuration && plan_configuration || exit 1
      print -nr -- harmony-simulator-create > "$CONFIG_PATH"
      if publish_configuration; then exit 2; fi
      [[ "$(<"$CONFIG_PATH")" == harmony-simulator-create ]] || exit 3
    ZSH
  end

  def test_partial_uninstall_keeps_other_leaf_and_last_uninstall_disables_aggregate
    run_checks(<<~'ZSH')
      print -nr -- ios-simulator-create,hidden-files-toggle > "$CONFIG_PATH"
      OPERATION=uninstall
      REQUESTED=(ios-simulator-create)
      disable_aggregate_extension() { print -r -- disable >> "$TRANSACTION_DIR/calls"; }
      retire_legacy() { return 0; }
      read_configuration && plan_configuration && uninstall_features || exit 1
      [[ "$(<"$CONFIG_PATH")" == hidden-files-toggle && ! -e "$TRANSACTION_DIR/calls" ]] || exit 2
      CONFIG_PUBLISHED=0
      REQUESTED=(hidden-files-toggle)
      read_configuration && plan_configuration && uninstall_features || exit 3
      [[ ! -s "$CONFIG_PATH" && "$(<"$TRANSACTION_DIR/calls")" == disable ]] || exit 4
    ZSH
  end

  def test_malformed_configuration_never_becomes_default_all
    ["ios-simulator-create\n", 'unknown', 'ios-simulator-create,', 'ios-simulator-create,,hidden-files-toggle', 'hidden-files-toggle,hidden-files-toggle'].each do |value|
      run_checks('if read_configuration; then exit 1; fi', configuration: value)
    end
  end

  def test_temporary_root_accepts_both_trailing_slash_forms
    ['', '/'].each do |suffix|
      run_checks(<<~ZSH)
        TMPDIR="$1#{suffix}"
        prepare_context install hidden-files-toggle --non-interactive || exit 1
        [[ "$LOG_FILE" == "$1/JobsDesktopToolsInstall.log" ]] || exit 2
        CONFIG_DIR="$1/temporary-config"
        CONFIG_PATH="$CONFIG_DIR/EnabledFeatures.txt"
        MARKER_PATH="$CONFIG_DIR/MigrationVersion.txt"
        LOCK_PATH="$CONFIG_DIR/.manager-lock"
        initialize_runtime
        [[ "$TRANSACTION_DIR" == "$1"/JobsDesktopToolsTransaction.* ]] || exit 3
        TRANSACTION_COMMITTED=1
      ZSH
    end
  end

  def test_bundled_sources_match_manifest_and_canonical_sources
    JSON.parse(File.read(JobsSourceLayout.file(File.join(ROOT, 'SourceManifest.json')))).each do |record|
      target = JobsSourceLayout.file(File.join(ROOT, record.fetch('target')))
      source = File.expand_path(record.fetch('source'), ROOT)
      assert_equal record.fetch('sha256'), Digest::SHA256.file(target).hexdigest, target
      assert_equal File.binread(source), File.binread(target), source
    end
  end

  def test_total_installer_deduplicates_six_leaves_into_one_project
    installer = JobsSourceLayout.file(File.join(ROOT, '../Scripts/【MacOS】ManageFinderExtensions.zsh/【MacOS】ManageFinderExtensions.zsh'))
    run_checks(<<~'ZSH', source: installer)
      parse_feature_selection ios-simulator-create,android-simulator-create,harmony-simulator-create,android-simulator-repair,harmony-simulator-repair,hidden-files-toggle,ios-simulator-create || exit 1
      [[ "${(j:,:)SELECTED_KEYS}" == desktop-tools && ${#SELECTED_FUNCTION_IDS} == 6 ]] || exit 2
      [[ "${FEATURE_PROJECT_DIR[desktop-tools]}" == JobsDesktopTools ]] || exit 3
      [[ "${FEATURE_EXTENSION_ID[desktop-tools]}" == com.jobs.desktoptools.findersync ]] || exit 4
    ZSH
  end

  private

  def run_checks(checks, configuration: nil, source: MANAGER)
    Dir.mktmpdir('jobs-desktop-installer-') do |directory|
      source_text = File.read(source).sub(/^main "\$@"\s*\z/, '')
      # 新模块通过动态 source 加载，旧配置层夹具必须封住该边界。
      source_text = source_text.gsub('source "$PROJECT_ROOT/Scripts/【MacOS】AppDeployment.zsh/【MacOS】AppDeployment.zsh"', ':')
      fixture = File.join(directory, 'fixture.zsh')
      setup = <<~'ZSH'
        setopt NO_NOMATCH PIPE_FAIL
        CONFIG_DIR="$1/config"
        CONFIG_PATH="$CONFIG_DIR/EnabledFeatures.txt"
        MARKER_PATH="$CONFIG_DIR/MigrationVersion.txt"
        TRANSACTION_DIR="$1/transaction"
        LOG_FILE="$1/fixture.log"
        /bin/mkdir -p "$CONFIG_DIR" "$TRANSACTION_DIR"
        extension_is_enabled() { return 1; }
        jobs_deployment_app_path() { print -r -- "$1"; }
        jobs_deployment_enabled_extension_paths() { return 0; }
        jobs_deployment_commit() { return 0; }
        jobs_deployment_rollback() { return 0; }
      ZSH
      FileUtils.mkdir_p(File.join(directory, 'config'))
      File.write(File.join(directory, 'config/EnabledFeatures.txt'), configuration) unless configuration.nil?
      File.write(fixture, source_text + "\n" + setup + checks)
      output, status = Open3.capture2e({'NO_COLOR' => '1'}, '/bin/zsh', '-f', fixture, directory)
      assert status.success?, "#{output}\n#{checks}"
    end
  end
end
