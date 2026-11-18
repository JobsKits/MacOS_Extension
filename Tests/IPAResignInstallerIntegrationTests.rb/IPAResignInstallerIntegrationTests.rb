# frozen_string_literal: true
# 只读取真实安装器定义并在临时 Shell 内核对映射，不注册扩展或执行 IPA 重签。

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
require_relative '../IsolatedInstallerDefinitions'

class IPAResignInstallerIntegrationTests < Minitest::Test
  include IsolatedInstallerDefinitions
  ROOT = File.expand_path('..', File.dirname(__dir__))
  INSTALLER = File.join(ROOT, 'Scripts/【MacOS】ManageFinderExtensions.zsh/【MacOS】ManageFinderExtensions.zsh')
  UNINSTALLER = File.join(ROOT, 'Scripts/【MacOS】ManageFinderExtensions.zsh/【MacOS】ManageFinderExtensions.zsh')
  PROJECT = File.join(ROOT, 'JobsIPAResigner')
  KEY = 'ipa-resign'
  APP = 'JobsIPAResigner'
  APP_ID = 'com.jobs.JobsIPAResigner'
  TITLE = 'IPA 免编译重签'

  def test_selector_contains_ipa_resign_once
    selector = File.read(File.join(ROOT, 'Scripts/SelectFinderExtensionFeatures.swift'))
    options = selector.scan(/FeatureOption\(identifier: "([^"]+)", title: "([^"]+)"\)/)
    assert_equal [[KEY, TITLE]], options.select { |identifier, _| identifier == KEY }
  end

  def test_ipa_resign_is_available_once_in_install_and_uninstall_feature_lists
    [INSTALLER, UNINSTALLER].each do |entry|
      output = run_definitions(entry, 'print -rl -- "${FEATURE_KEYS[@]}"')
      assert_equal 1, output.lines.map(&:strip).count(KEY), entry
    end
  end

  def test_install_mapping_keeps_an_independent_project_and_explicit_bundle_ids
    output = run_definitions(INSTALLER, <<~'ZSH', ROOT)
      WORKSPACE_DIR="$1"
      parse_feature_selection 'ipa-resign,ipa-resign' || exit 1
      print -r -- "${(j:,:)SELECTED_KEYS}"
      print -r -- "${(j:,:)SELECTED_FUNCTION_IDS}"
      print -r -- "${FEATURE_TITLE[ipa-resign]}"
      print -r -- "${FEATURE_PROJECT_DIR[ipa-resign]}"
      print -r -- "${FEATURE_SCHEME[ipa-resign]}"
      print -r -- "${FEATURE_APP_NAME[ipa-resign]}"
      print -r -- "${FEATURE_EXTENSION_NAME[ipa-resign]}"
      app_bundle_id_for_key ipa-resign
      print -r -- "${FEATURE_EXTENSION_ID[ipa-resign]}"
      print -r -- "terminal:${TERMINAL_OPENER_ENABLED_FEATURES}"
      project_file_for_key ipa-resign
      derived_data_dir_for_key ipa-resign
    ZSH
    assert_equal [KEY, KEY, TITLE, APP, APP, APP, 'JobsIPAResignerFinderSync.appex',
                  APP_ID, "#{APP_ID}.FinderSyncExtension", 'terminal:', File.join(PROJECT, "#{APP}.xcodeproj"),
                  File.join(ROOT, "work/#{APP}DerivedData")], output.lines.map(&:strip)
  end

  def test_install_selection_deduplicates_ipa_resign_when_combined_with_terminal
    output = run_definitions(INSTALLER, <<~'ZSH')
      parse_feature_selection 'ipa-resign,terminal_open,ipa-resign,terminal_open' || exit 1
      print -r -- "${(j:,:)SELECTED_KEYS}"
      print -r -- "${(j:,:)SELECTED_FUNCTION_IDS}"
      print -r -- "$TERMINAL_OPENER_ENABLED_FEATURES"
    ZSH
    assert_equal ['ipa-resign,terminal_opener', 'ipa-resign,terminal_open', 'open'],
                 output.lines.map(&:strip)
  end

  def test_unknown_feature_selection_is_rejected
    output = run_definitions(INSTALLER, <<~'ZSH')
      if parse_feature_selection 'unexpected-ipa-resign-feature,ipa-resign'; then
        exit 1
      fi
      [[ "${#SELECTED_KEYS[@]}" == 0 ]] || exit 1
      print -r -- 'unknown-rejected'
    ZSH
    assert_includes output, '未知标识：unexpected-ipa-resign-feature'
    assert_includes output, 'unknown-rejected'
  end

  def test_registration_initializes_host_without_resigning_ipa
    output = run_definitions(INSTALLER, <<~'ZSH', replacements: {'/usr/bin/open' => 'jobs_record_open'})
      jobs_record_open() {
        print -r -- "${(j:|:)@}"
      }
      open_host_for_extension_registration ipa-resign '/fixture/中文 space/JobsIPAResigner.app'
    ZSH
    assert_equal ['-gj|/fixture/中文 space/JobsIPAResigner.app|--args|--initialize-finder-extension'],
                 output.lines.map(&:strip)
  end

  def test_uninstall_mapping_and_title_selection_keep_the_same_identity
    output = run_definitions(UNINSTALLER, <<~'ZSH', ROOT)
      WORKSPACE_DIR="$1"
      parse_feature_selection 'ipa-resign,ipa-resign' || exit 1
      print -r -- "${(j:,:)SELECTED_KEYS}"
      print -r -- "${FEATURE_TITLE[ipa-resign]}"
      print -r -- "${FEATURE_PROJECT_DIR[ipa-resign]}"
      print -r -- "${FEATURE_APP_NAME[ipa-resign]}"
      print -r -- "${FEATURE_EXTENSION_NAME[ipa-resign]}"
      print -r -- "${FEATURE_EXTENSION_ID[ipa-resign]}"
      derived_data_dir_for_key ipa-resign
    ZSH
    assert_equal [KEY, TITLE, APP, APP, 'JobsIPAResignerFinderSync.appex', "#{APP_ID}.FinderSyncExtension",

                  File.join(ROOT, "work/#{APP}DerivedData")], output.lines.map(&:strip)
  end

  def test_missing_ipa_resign_project_is_reported_before_building
    Dir.mktmpdir('jobs-ipa-resign-missing-project-') do |workspace|
      output = run_definitions(INSTALLER, <<~'ZSH', workspace)
        WORKSPACE_DIR="$1"
        for key in "${FEATURE_KEYS[@]}"; do
          [[ "$key" == ipa-resign ]] && continue
          /bin/mkdir -p "$(project_file_for_key "$key")"
          print -r -- '// fixture' > "$(project_file_for_key "$key")/project.pbxproj"
        done
        if ensure_feature_projects_exist; then
          exit 1
        fi
        print -r -- 'installation-stopped'
      ZSH
      assert_includes output, 'JobsIPAResigner.xcodeproj/project.pbxproj'
      assert_includes output, 'installation-stopped'
      assert_includes output, '重新取得包含全部工程源码的完整 MacOS@Extension 仓库'
      refute_includes output, 'JobsIOSSimulatorCreator.xcodeproj/project.pbxproj'
    end
  end

  private

  def run_definitions(path, checks, *arguments, replacements: {})
    source = isolated_installer_source(path, replacements: replacements)

    Dir.mktmpdir('jobs-ipa-resign-install-mapping-') do |directory|
      fixture = File.join(directory, 'mapping.zsh')
      File.write(fixture, source + "\nLOG_FILE=\"${0:h}/mapping.log\"\n" + checks)
      output, status = Open3.capture2e(isolated_installer_environment(directory), '/bin/zsh', '-f', fixture, *arguments)
      assert status.success?, output
      output
    end
  end
end
