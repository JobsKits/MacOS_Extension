# frozen_string_literal: true
# 读取真实安装定义，在隔离目录核对 iOS 子功能映射、配置合并与派发；不构建或注册扩展。

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
require_relative 'IsolatedInstallerDefinitions'

class IOSToolsInstallerIntegrationTests < Minitest::Test
  include IsolatedInstallerDefinitions
  ROOT = File.expand_path('..', __dir__)
  INSTALLER = File.join(ROOT, 'Scripts/ManageFinderExtensions.zsh')
  UNINSTALLER = File.join(ROOT, 'Scripts/ManageFinderExtensions.zsh')
  IDS = %w[ios-disable-sandbox ios-install-cocoapods ios-pods-source-github
           ios-extract-pods ios-pod-update ios-xcode-dependencies ios-pod-repo-update ios-pod-build-check ios-code-snippets ios-clean-build-artifacts].freeze
  ACTION_IDS = (IDS.take(4) + ['ios-pod-install'] + IDS.drop(4)).freeze

  def test_ios_options_are_unique_and_map_to_one_project
    selector = File.read(File.join(ROOT, 'Scripts/SelectFinderExtensionFeatures.swift'))
    ios = selector[/static let ios:.*?\n    \]/m]
    refute_nil ios
    assert_equal IDS, ios.scan(/FeatureOption\(identifier: "([^"]+)"/).flatten
    output = run_definitions(INSTALLER, <<~'ZSH', IDS.join(','))
      parse_feature_selection "$1,$1" || exit 1
      print -r -- "${(j:,:)SELECTED_FUNCTION_IDS}"
      print -r -- "${(j:,:)SELECTED_KEYS}"
      print -r -- "$IOS_TOOLS_ENABLED_FEATURES"
      print -r -- "terminal:$TERMINAL_OPENER_ENABLED_FEATURES"
      print -r -- "${#SELECTABLE_FUNCTION_IDS[@]}:${#FEATURE_KEYS[@]}"
    ZSH
    lines = output.lines.map(&:strip)
    assert_equal [IDS.join(','), 'ios-tools', IDS.join(','), 'terminal:'], lines.first(4)
    option_count, project_count = lines.last.split(':').map(&:to_i)
    assert_equal selector.scan(/FeatureOption\(identifier: "([^"]+)"/).length, option_count
    assert_operator option_count, :>=, 29
    assert_equal 9, project_count
  end

  def test_codesnippets_can_be_installed_alone_without_disabling_existing_ios_tools
    Dir.mktmpdir('jobs-snippets-feature-config-') do |directory|
      config = File.join(directory, 'EnabledFeatures.txt')
      File.write(config, 'ios-pod-update')
      run_definitions(INSTALLER, <<~'ZSH', config)
        IOS_FEATURE_CONFIG_PATH="$1"
        IOS_FEATURE_CONFIG_DIR="${1:h}"
        parse_feature_selection 'ios-code-snippets' || exit 1
        [[ "${(j:,:)SELECTED_KEYS}" == ios-tools ]] || exit 1
        persist_ios_feature_selection ios-tools || exit 1
      ZSH
      assert_equal 'ios-pod-update,ios-code-snippets', File.read(config)
    end
  end

  def test_pod_install_and_ios_build_cleanup_are_independent_ios_actions
    output = run_definitions(INSTALLER, <<~'ZSH')
      parse_feature_selection 'pod_install,ios-clean-build-artifacts,pod_install' || exit 1
      print -r -- "${(j:,:)SELECTED_KEYS}"
      print -r -- "$IOS_TOOLS_ENABLED_FEATURES"
      print -r -- "terminal:$TERMINAL_OPENER_ENABLED_FEATURES"
    ZSH
    assert_equal ['ios-tools', 'ios-pod-install,ios-clean-build-artifacts', 'terminal:'], output.lines.map(&:strip)
  end

  def test_all_seven_git_actions_share_one_project_without_terminal_dependencies
    ids = %w[git-sourcetree git-pull git-rollback git_remote git_remote_copier git-proxy-configure git_empty_commit_push]
    output = run_definitions(INSTALLER, <<~'ZSH', ids.join(','))
      parse_feature_selection "$1" || exit 1
      print -r -- "${(j:,:)SELECTED_KEYS}"
      print -r -- "terminal:$TERMINAL_OPENER_ENABLED_FEATURES"
      print -r -- "ios:$IOS_TOOLS_ENABLED_FEATURES"
    ZSH
    assert_equal ['project-tools', 'terminal:', 'ios:'], output.lines.map(&:strip)
    output = run_definitions(UNINSTALLER, <<~'ZSH', ROOT, ids.join(','), replacements: {'/bin/zsh' => 'jobs_record_git_uninstall'})
      WORKSPACE_DIR="$1"
      jobs_record_git_uninstall() { print -r -- "delegate:${(j:|:)@}"; }
      parse_feature_selection "$2" || exit 1
      uninstall_feature project-tools || exit 1
    ZSH
    assert_equal ["delegate:#{File.join(ROOT, 'JobsProjectTools/Scripts/ManageProjectTools.zsh')}|uninstall|#{ids.join('|')}"], output.lines.map(&:strip)
  end

  def test_independent_install_and_uninstall_share_the_complete_fixed_action_list
    %i[install uninstall].each do |operation|
      path = File.join(ROOT, 'JobsIOSTools/Scripts/ManageExtension.zsh')
      output = run_definitions(path, <<~'ZSH', operation: operation)
        parse_feature_options --features ios-code-snippets || exit 1
        print -r -- "${(j:,:)ALL_FEATURES}"
        print -r -- "${(j:,:)REQUESTED_FEATURES}"
      ZSH
      assert_equal [ACTION_IDS.join(','), 'ios-code-snippets'], output.lines.map(&:strip)
    end
  end

  def test_ios_project_identity_matches_install_and_uninstall
    output = run_definitions(INSTALLER, <<~'ZSH', ROOT)
      WORKSPACE_DIR="$1"
      print -r -- "${FEATURE_PROJECT_DIR[ios-tools]}"
      print -r -- "${FEATURE_SCHEME[ios-tools]}"
      print -r -- "${FEATURE_APP_NAME[ios-tools]}"
      print -r -- "${FEATURE_EXTENSION_NAME[ios-tools]}"
      app_bundle_id_for_key ios-tools
      print -r -- "${FEATURE_EXTENSION_ID[ios-tools]}"
      derived_data_dir_for_key ios-tools
    ZSH
    assert_equal ['JobsIOSTools', 'JobsIOSTools', 'JobsIOSTools', 'JobsIOSToolsFinderSync.appex',
                  'com.jobs.JobsIOSTools', 'com.jobs.JobsIOSTools.FinderSyncExtension',
                  File.join(ROOT, 'work/JobsIOSToolsDerivedData')], output.lines.map(&:strip)
    output = run_definitions(UNINSTALLER, <<~'ZSH')
      parse_feature_selection 'ios-code-snippets' || exit 1
      print -r -- "${(j:,:)SELECTED_KEYS}"
      print -r -- "${FEATURE_PROJECT_DIR[ios-tools]}"
      print -r -- "${FEATURE_EXTENSION_NAME[ios-tools]}"
      print -r -- "${FEATURE_EXTENSION_ID[ios-tools]}"
    ZSH
    assert_equal ['ios-tools', 'JobsIOSTools', 'JobsIOSToolsFinderSync.appex', 'com.jobs.JobsIOSTools.FinderSyncExtension'], output.lines.map(&:strip)
  end

  def test_installation_merges_valid_ios_selection_and_deduplicates_legacy_actions
    Dir.mktmpdir('jobs-ios-feature-config-') do |directory|
      config = File.join(directory, '配置 space', 'EnabledFeatures.txt')
      output = run_definitions(INSTALLER, <<~'ZSH', config)
        IOS_FEATURE_CONFIG_PATH="$1"
        IOS_FEATURE_CONFIG_DIR="${1:h}"
        /bin/mkdir -p "$IOS_FEATURE_CONFIG_DIR"
        print -nr -- 'ios-pod-build-check,ios-clean-cache' > "$IOS_FEATURE_CONFIG_PATH"
        parse_feature_selection 'ios-pod-update,ios-pod-update,ios-clean-cache,ios-clean-build-artifacts' || exit 1
        persist_ios_feature_selection ios-tools || exit 1
        print -r -- "configured:$(<"$IOS_FEATURE_CONFIG_PATH")"
      ZSH
      assert_includes output.lines.map(&:strip), 'configured:ios-pod-update,ios-pod-build-check,ios-clean-build-artifacts'
      assert_equal 'ios-pod-update,ios-pod-build-check,ios-clean-build-artifacts', File.read(config)
      assert_empty Dir.glob(File.join(File.dirname(config), '.features.*'))
    end
  end

  def test_legacy_cache_selection_maps_to_the_single_build_cleanup_action
    output = run_definitions(INSTALLER, <<~'ZSH')
      parse_feature_selection 'ios-clean-cache,ios-clean-build-artifacts' || exit 1
      print -r -- "${(j:,:)SELECTED_FUNCTION_IDS}"
      print -r -- "$IOS_TOOLS_ENABLED_FEATURES"
    ZSH
    assert_equal ['ios-clean-build-artifacts', 'ios-clean-build-artifacts'], output.lines.map(&:strip)
  end

  def test_first_install_or_empty_configuration_only_enables_selected_tools
    [false, true].each do |empty_existing|
      Dir.mktmpdir('jobs-ios-subset-config-') do |directory|
        config = File.join(directory, 'EnabledFeatures.txt')
        File.write(config, '') if empty_existing
        run_definitions(INSTALLER, <<~'ZSH', config)
          IOS_FEATURE_CONFIG_PATH="$1"
          IOS_FEATURE_CONFIG_DIR="${1:h}"
          parse_feature_selection 'ios-pod-build-check' || exit 1
          persist_ios_feature_selection ios-tools || exit 1
        ZSH
        assert_equal 'ios-pod-build-check', File.read(config)
      end
    end
  end

  def test_other_features_do_not_write_ios_configuration
    Dir.mktmpdir('jobs-ios-no-config-') do |directory|
      config = File.join(directory, 'not-created', 'EnabledFeatures.txt')
      run_definitions(INSTALLER, <<~'ZSH', config)
        IOS_FEATURE_CONFIG_PATH="$1"
        IOS_FEATURE_CONFIG_DIR="${1:h}"
        parse_feature_selection 'terminal_open' || exit 1
        persist_ios_feature_selection terminal_opener || exit 1
      ZSH
      refute File.exist?(File.dirname(config))
    end
  end

  def test_build_failure_does_not_persist_configuration_and_registration_reads_saved_selection
    output = run_definitions(INSTALLER, <<~'ZSH')
      build_feature() { print -r -- 'build'; return 1; }
      persist_ios_feature_selection() { print -r -- 'persist'; }
      register_and_enable_feature() { print -r -- 'register'; }
      if install_feature ios-tools; then exit 1; fi
      build_feature() { print -r -- 'build'; }
      persist_terminal_feature_selection() { print -r -- 'terminal'; }
      install_feature ios-tools || exit 1
    ZSH
    phases = output.lines.map(&:strip).select { |line| %w[build persist register terminal].include?(line) }
    assert_equal %w[build build persist register terminal], phases
  end

  def test_ios_host_initialization_never_dispatches_a_tool
    output = run_definitions(INSTALLER, <<~'ZSH', replacements: {'/usr/bin/open' => 'jobs_record_open'})
      jobs_record_open() { print -r -- "${(j:|:)@}"; }
      open_host_for_extension_registration ios-tools '/fixture/中文 space/JobsIOSTools.app'
    ZSH
    assert_equal ['-gj|/fixture/中文 space/JobsIOSTools.app|--args|--initialize-finder-extension'], output.lines.map(&:strip)
  end

  def test_ios_partial_uninstall_delegates_selected_actions_without_root_artifact_cleanup
    output = run_definitions(UNINSTALLER, <<~'ZSH', ROOT, replacements: {'/bin/zsh' => 'jobs_record_uninstall'})
      WORKSPACE_DIR="$1"
      jobs_record_uninstall() { print -r -- "delegate:${(j:|:)@}"; }
      for phase in print_current_extension_status disable_extension stop_host_application stop_extension_processes reset_election_and_unregister_extension clear_runtime_markers remove_xcode_deriveddata_app_bundles remove_local_deriveddata_dir remove_legacy_automator_service; do
        functions[$phase]='print -r -- "phase:${funcstack[1]}:$1"'
      done
      parse_feature_selection ios-code-snippets || exit 1
      uninstall_feature ios-tools || exit 1
    ZSH
    assert_includes output, "delegate:#{File.join(ROOT, 'JobsIOSTools/Scripts/ManageExtension.zsh')}|--action|uninstall|--non-interactive|--skip-finder-restart|--features|ios-code-snippets"
    refute_includes output, 'phase:remove_local_deriveddata_dir:ios-tools'
    refute_includes output, 'phase:reset_election_and_unregister_extension:ios-tools'
  end

  private

  def run_definitions(path, checks, *arguments, replacements: {}, operation: :install)
    source = isolated_installer_source(path, replacements: replacements, operation: operation)

    Dir.mktmpdir('jobs-ios-install-mapping-') do |directory|
      fixture = File.join(directory, 'mapping.zsh')
      File.write(fixture, source + "\nLOG_FILE=\"${0:h}/mapping.log\"\n" + checks)
      output, status = Open3.capture2e(isolated_installer_environment(directory), '/bin/zsh', '-f', fixture, *arguments)
      assert status.success?, output
      output
    end
  end
end
