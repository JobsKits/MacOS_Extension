# frozen_string_literal: true
# 总管理器的“新建文件”映射回归；仅临时夹具及命令替身，不构建、登记扩展或刷新 Finder。
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

class FileCreatorInstallerIntegrationTests < Minitest::Test
  include IsolatedInstallerDefinitions
  ROOT = File.expand_path('..', __dir__)
  MANAGER = File.join(ROOT, 'Scripts/ManageFinderExtensions.zsh')
  KEY = 'file-create'
  APP = 'JobsFileCreator'

  def test_catalog_maps_one_file_creation_action_to_its_independent_unit
    source = File.read(File.join(ROOT, 'Scripts/SelectFinderExtensionFeatures.swift'))
    options = source.scan(/FeatureOption\(identifier: "([^"]+)", title: "([^"]+)"\)/)
    assert_equal [[KEY, '新建文件']], options.select { |identifier, _| identifier == KEY }
    general = source[/FeatureGroup\(identifier: "general".*?identifiers: \[(.*?)\]\)/m, 1]
    assert_includes general.scan(/"([^"]+)"/).flatten, KEY

    output, errors, result = run_definitions(<<~'ZSH', ROOT)
      WORKSPACE_DIR="$1"
      parse_feature_selection file-create,file-create || exit 1
      print -r -- "${(j:,:)SELECTED_KEYS}|${(j:,:)SELECTED_FUNCTION_IDS}"
      print -r -- "${FEATURE_TITLE[file-create]}|${FEATURE_PROJECT_DIR[file-create]}|${FEATURE_SCHEME[file-create]}"
      print -r -- "${FEATURE_APP_NAME[file-create]}|${FEATURE_EXTENSION_NAME[file-create]}|${FEATURE_EXTENSION_ID[file-create]}"
      app_bundle_id_for_key file-create
      project_file_for_key file-create
      derived_data_dir_for_key file-create
      print -r -- "terminal:$TERMINAL_OPENER_ENABLED_FEATURES|ios:$IOS_TOOLS_ENABLED_FEATURES|flutter:$FLUTTER_TOOLS_ENABLED_FEATURES"
    ZSH
    assert result.success?, errors
    assert_equal ["#{KEY}|#{KEY}", "新建文件|#{APP}|#{APP}",
                  "#{APP}|#{APP}FinderSync.appex|com.jobs.filecreator.findersync",
                  'com.jobs.filecreator', File.join(ROOT, APP, "#{APP}.xcodeproj"),
                  File.join(ROOT, "work/#{APP}DerivedData"), 'terminal:|ios:|flutter:'], output.lines.map(&:chomp)
  end

  def test_scoped_install_and_uninstall_plan_contains_only_file_creation
    %w[install uninstall].each do |action|
      output, errors, result = run_definitions(<<~'ZSH', action)
        parse_management_options --scope file-create --features file-create,file-create --action "$1" --non-interactive || exit $?
        select_management_features || exit $?
        print -r -- "$MANAGEMENT_ACTION|${(j:,:)SELECTED_KEYS}|${(j:,:)SELECTED_FUNCTION_IDS}"
      ZSH
      assert result.success?, errors
      assert_equal "#{action}|#{KEY}|#{KEY}\n", output
    end
  end

  def test_single_file_creation_scope_rejects_other_tools_before_work
    ['terminal_open', 'hidden-files-toggle', 'file-create,run-authorize', 'file-create,', 'file-create,,file-create'].each do |features|
      output, _, result = run_definitions(<<~'ZSH', features)
        parse_management_options --scope file-create --features "$1" --action install --non-interactive || exit $?
        print unexpected-work
      ZSH
      refute result.success?, features
      refute_includes output, 'unexpected-work'
    end
  end

  def test_file_creation_and_terminal_choices_remain_separate
    output, errors, result = run_definitions(<<~'ZSH')
      parse_feature_selection file-create,terminal_open,file-create,file_content || exit 1
      print -r -- "${(j:,:)SELECTED_KEYS}|${(j:,:)SELECTED_FUNCTION_IDS}|$TERMINAL_OPENER_ENABLED_FEATURES"
    ZSH
    assert result.success?, errors
    assert_equal "file-create,terminal_opener|file-create,terminal_open,file_content|open,file-content\n", output
  end

  def test_install_dispatches_only_file_creator_build_and_registration
    output, errors, result = run_definitions(<<~'ZSH')
      parse_feature_selection file-create || exit 1
      ensure_feature_projects_exist() { [[ $# == 1 && "$1" == file-create ]]; }
      build_feature() { print -r -- "BUILD=$1"; }
      register_and_enable_feature() { print -r -- "REGISTER=$1"; }
      install_selected_features || exit $?
      print -r -- "RESULT=$FINAL_EXIT_STATUS"
    ZSH
    assert result.success?, errors
    assert_equal ['BUILD=file-create', 'REGISTER=file-create'], output.lines.map(&:chomp).grep(/^(?:BUILD|REGISTER)=/)
    assert_includes output, "JOBS_MANAGER_EVENT\tfile-create\tsucceeded"
    assert_includes output, 'RESULT=0'
    refute_includes errors, 'blocked unexpected system operation'
  end

  def test_uninstall_calls_only_the_file_creator_manager_without_restarting_finder
    Dir.mktmpdir('jobs-file-create-uninstall-') do |directory|
      entry = File.join(directory, APP, 'Scripts/ManageExtension.zsh')
      FileUtils.mkdir_p(File.dirname(entry))
      File.write(entry, '# fixture: this file must never execute')
      replacements = {
        '/bin/zsh "${entries[1]}" "${arguments[@]}"' => 'jobs_record_manager "${entries[1]}" "${arguments[@]}"'
      }
      output, errors, result = run_definitions(<<~'ZSH', directory, replacements: replacements)
        WORKSPACE_DIR="$1"
        selected_location_has_app() { return 0; }
        another_location_is_active() { return 1; }
        jobs_record_manager() { print -r -- "WORKER=${(j:|:)@}|skip=$JOBS_SKIP_FINDER_RESTART"; }
        parse_feature_selection file-create || exit 1
        uninstall_selected_features || exit $?
      ZSH
      assert result.success?, errors
      assert_equal ["WORKER=#{entry}|--action|uninstall|--non-interactive|--skip-finder-restart|--install-location|build|skip=1"], output.lines.map(&:chomp).grep(/^WORKER=/)
      assert_includes output, "JOBS_MANAGER_EVENT\tfile-create\tsucceeded"
      refute_includes errors, 'blocked unexpected system operation'
    end
  end

  def test_registration_initializes_host_once_without_opening_a_creation_dialog
    output, errors, result = run_definitions(<<~'ZSH', replacements: {'/usr/bin/open' => 'jobs_record_open'})
      jobs_record_open() { print -r -- "${(j:|:)@}"; }
      open_host_for_extension_registration file-create '/fixture/中文 space/JobsFileCreator.app'
    ZSH
    assert result.success?, errors
    assert_equal "-gj|/fixture/中文 space/JobsFileCreator.app|--args|--initialize-finder-extension\n", output
  end

  def test_invisible_first_registration_is_added_again_after_host_initialization
    output, errors, result = run_registration_recovery_fixture
    assert result.success?, output + errors
    records = output.lines.map(&:chomp).grep(/^REC:/)
    expected_path = output.lines.find { |line| line.start_with?('TARGET=') }.delete_prefix('TARGET=').chomp
    assert_equal ["REC:pluginkit|-a|#{expected_path}"] * 2, records.grep(/^REC:pluginkit\|-a\|/)
    assert_equal 2, records.count { |line| line == 'REC:pluginkit|-e|use|-i|com.jobs.filecreator.findersync' }
    host = records.index { |line| line.start_with?('REC:open|') }
    assert host, records.join("\n")
    assert records[host].end_with?('|--args|--initialize-finder-extension')
    assert records[host + 1].start_with?('REC:pluginkit|-a|'), records.join("\n")
    assert_equal 'REC:pluginkit|-e|use|-i|com.jobs.filecreator.findersync', records[host + 2]
    assert_includes output, '扩展已启用：新建文件'
    refute_includes errors, 'blocked unexpected system operation'
  end

  def test_failed_second_registration_stops_without_an_enabled_result
    output, errors, result = run_registration_recovery_fixture(retry_status: 41)
    assert_equal 41, result.exitstatus, output + errors
    records = output.lines.map(&:chomp).grep(/^REC:/)
    expected_path = output.lines.find { |line| line.start_with?('TARGET=') }.delete_prefix('TARGET=').chomp
    assert_equal ["REC:pluginkit|-a|#{expected_path}"] * 2, records.grep(/^REC:pluginkit\|-a\|/)
    assert_equal 1, records.count { |line| line == 'REC:pluginkit|-e|use|-i|com.jobs.filecreator.findersync' }
    refute_includes output, '扩展已启用：新建文件'
    refute_includes errors, 'blocked unexpected system operation'
  end

  def test_cancel_and_empty_panel_output_never_form_an_install_plan
    ['__CANCELLED__', '__NONE__', ''].each do |selection|
      Dir.mktmpdir('jobs-file-create-cancel-') do |directory|
        selector = File.join(directory, 'selector.zsh')
        File.write(selector, "#!/bin/zsh\nprint -r -- \"$JOBS_TEST_SELECTION\"\n")
        File.chmod(0o700, selector)
        output, errors, result = run_definitions(<<~'ZSH', selector, selection)
          FEATURE_SCOPE=file-create
          FEATURE_SELECTOR_BINARY_PATH="$1"
          export JOBS_TEST_SELECTION="$2"
          build_feature_selector_if_needed() { return 0; }
          select_features_with_ui
          print unexpected-work
        ZSH
        assert result.success?, errors
        refute_includes output, 'unexpected-work'
        refute_includes errors, 'blocked unexpected system operation'
      end
    end
  end

  private

  def run_registration_recovery_fixture(retry_status: 0)
    Dir.mktmpdir('jobs-file-create-rediscovery-') do |directory|
      workspace = File.join(directory, '中文 space')
      app = File.join(workspace, "work/#{APP}DerivedData/Build/Products/Debug/#{APP}.app")
      FileUtils.mkdir_p(File.join(app, "Contents/PlugIns/#{APP}FinderSync.appex"))
      replacements = {
        '/usr/bin/pluginkit' => 'jobs_record_pluginkit',
        '/usr/bin/open' => 'jobs_record_open',
        '/bin/sleep' => 'jobs_skip_sleep'
      }
      run_definitions(<<~'ZSH', workspace, retry_status.to_s, replacements: replacements)
        WORKSPACE_DIR="$1"
        export JOBS_REGISTRATION_CALLS="${0:h}/registration-calls"
        export JOBS_REGISTRATION_COUNT="${0:h}/registration-count"
        export JOBS_RETRY_STATUS="$2"
        stop_feature_processes() { return 0; }
        cleanup_stale_registration_records() { return 0; }
        register_app_with_launchservices() { return 0; }
        jobs_skip_sleep() { return 0; }
        jobs_record_open() {
          print -r -- "REC:open|${(j:|:)@}" >> "$JOBS_REGISTRATION_CALLS"
        }
        jobs_record_pluginkit() {
          print -r -- "REC:pluginkit|${(j:|:)@}" >> "$JOBS_REGISTRATION_CALLS"
          if [[ "$1" == -a ]]; then
            local count=0
            [[ ! -f "$JOBS_REGISTRATION_COUNT" ]] || read -r count < "$JOBS_REGISTRATION_COUNT"
            count=$((count + 1))
            print -r -- "$count" > "$JOBS_REGISTRATION_COUNT"
            (( count != 2 || JOBS_RETRY_STATUS == 0 )) || return "$JOBS_RETRY_STATUS"
          fi
          return 0
        }
        wait_until_extension_enabled() {
          [[ "$1" == com.jobs.filecreator.findersync && "$2" == "$(extension_path_for_key file-create)" ]] || return 97
          local count=0
          [[ ! -f "$JOBS_REGISTRATION_COUNT" ]] || read -r count < "$JOBS_REGISTRATION_COUNT"
          (( count == 2 ))
        }
        register_and_enable_feature file-create
        result=$?
        while IFS= read -r record; do
          print -r -- "$record"
        done < "$JOBS_REGISTRATION_CALLS"
        print -r -- "TARGET=$(extension_path_for_key file-create)"
        exit "$result"
      ZSH
    end
  end

  def run_definitions(checks, *arguments, replacements: {})
    source = isolated_installer_source(MANAGER, replacements: replacements)
    Dir.mktmpdir('jobs-file-create-integration-') do |directory|
      fixture = File.join(directory, 'mapping.zsh')
      File.write(fixture, source + "\nLOG_FILE=\"${0:h}/mapping.log\"\n" + checks)
      Open3.capture3(isolated_installer_environment(directory), '/bin/zsh', '-f', fixture, *arguments)
    end
  end
end
