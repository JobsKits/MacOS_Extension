# frozen_string_literal: true
# Jobs：仅使用临时 App 夹具，系统签名与登记全部由函数替身承接。
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
require 'json'

class AppDeploymentTests < Minitest::Test
  LIBRARY = ENV.fetch('JOBS_APP_DEPLOYMENT_TEST_LIBRARY', File.expand_path('../../Scripts/【MacOS】AppDeployment.zsh/【MacOS】AppDeployment.zsh', __dir__))
  APP_ID = 'com.jobs.fixture'
  EXTENSION = 'JobsFixtureFinder.appex'
  EXTENSION_ID = 'com.jobs.fixture.findersync'

  def setup
    @temporary = Dir.mktmpdir('Jobs App部署 ')
    @root = File.realpath(@temporary)
    @applications = File.join(@root, '应用 程序')
    @derived = File.join(@root, '编译 产物', 'work', 'JobsFixtureDerivedData')
    @built = File.join(@derived, 'Build/Products/Debug/JobsFixture.app')
    @container = File.join(@applications, 'Jobs自定义右键菜单.app')
    @deployed = File.join(@container, 'Contents/Applications/JobsFixture.app')
    FileUtils.mkdir_p(@applications)
    make_container
    make_app(@built, 'new')
  end

  def teardown
    FileUtils.remove_entry(@temporary) if File.exist?(@temporary)
  end

  def test_default_build_mode_and_install_uninstall_are_unchanged
    shell(<<~'ZSH')
      unset JOBS_FINDER_INSTALL_LOCATION
      [[ "$(jobs_deployment_app_path "$BUILT")" == "$BUILT" ]] || exit 1
      jobs_deployment_install "$TEST_ROOT/missing/JobsFixture.app" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || exit 2
      jobs_deployment_uninstall "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || exit 3
      jobs_deployment_commit && jobs_deployment_rollback || exit 4
      [[ -d "$BUILT" && ! -e "$CALLS" ]] || exit 5
    ZSH
  end

  def test_complete_app_is_copied_and_commit_releases_backup_and_lock
    shell(<<~'ZSH')
      [[ "$(jobs_deployment_app_path "$BUILT")" == "$DEPLOYED" ]] || exit 1
      jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || exit 2
      [[ -d "$DEPLOYED/Contents/PlugIns/$EXTENSION" && -d "$JOBS_DEPLOYMENT_TRANSACTION_DIR" ]] || exit 3
      jobs_deployment_commit || exit 4
      [[ -z "$JOBS_DEPLOYMENT_TRANSACTION_DIR" ]] || exit 5
      [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$CONTAINER/Contents/Info.plist")" == JobsFinderManager.icns ]] || exit 6
    ZSH
    assert_equal File.binread(File.join(File.dirname(LIBRARY), 'Resources/JobsFinderManager.icns')), File.binread(File.join(@container, 'Contents/Resources/JobsFinderManager.icns'))
    assert_equal 'new', File.read(resource(@deployed))
    assert_equal File.binread(resource(@built)), File.binread(resource(@deployed))
    assert File.directory?(@derived), '默认不请求清理时必须保留构建产物'
    assert_empty Dir.glob(File.join(@applications, '.JobsFinderDeployment.*'))
  end

  def test_non_utf8_locale_keeps_raw_library_paths_and_prepares_complete_manager_resources
    package = File.join(@root, '搬迁 % 中文 空格', 'JobsPathCopier')
    scripts = File.join(package, 'Scripts')
    FileUtils.mkdir_p(scripts)
    %w[【MacOS】AppDeployment.zsh 【MacOS】联合App管理.zsh].each do |name|
      FileUtils.cp_r(File.join(File.dirname(File.dirname(LIBRARY)), name), scripts)
    end
    File.write(File.join(scripts, 'ManageExtension.zsh'), "# isolated management entry\n")
    library = File.join(scripts, '【MacOS】AppDeployment.zsh/【MacOS】AppDeployment.zsh')
    script = <<~'ZSH'
      load_library() { source "$1"; }
      load_library "$1" || exit 90
      [[ "$JOBS_DEPLOYMENT_MODULE_DIRECTORY" == "${1:A:h}" ]] || exit 1
      jobs_deployment_prepare_container || exit 2
      [[ "${JOBS_COMBINED_MANAGER_LIBRARY_SOURCE:A}" == "${1:h:h}/【MacOS】联合App管理.zsh/【MacOS】联合App管理.zsh" ]] || exit 3
      [[ "$LC_ALL" == C && "$LANG" == C ]] || exit 4
    ZSH
    output, error, result = Open3.capture3(
      { 'LC_ALL' => 'C', 'LANG' => 'C', 'JOBS_FINDER_APPLICATIONS_DIR' => @applications },
      '/bin/zsh', '-fuc', script, 'locale-fixture', library
    )
    assert result.success?, "exit=#{result.exitstatus}\n#{output}\n#{error}"
    resources = File.join(@container, 'Contents/Resources')
    assert_equal File.binread(File.join(File.dirname(library), 'Resources/JobsFinderManager.icns')),
                 File.binread(File.join(resources, 'JobsFinderManager.icns'))
    assert File.file?(File.join(resources, 'ManagerRoot/JobsPathCopier/Scripts/ManageExtension.zsh'))
    assert File.file?(File.join(resources, 'ManagerRoot/Scripts/SelectFinderExtensionFeatures.swift'))
  end

  def test_deployed_bundle_keeps_resources_after_source_is_removed
    shell('jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && jobs_deployment_commit || exit 1')
    FileUtils.remove_entry(@derived)
    assert_equal 'new', File.read(resource(@deployed))
    assert File.executable?(File.join(@deployed, 'Contents/PlugIns', EXTENSION, 'Contents/MacOS/FixtureExtension'))
    deployed_host = File.join(@deployed, 'Contents/MacOS/FixtureHost')
    output, error, result = Open3.capture3([deployed_host, deployed_host])
    assert result.success?, "部署宿主执行失败：#{error}"
    assert_equal 'new', output
  end

  def test_owned_app_is_replaced_then_rollback_restores_original_file_and_active_build
    make_app(@deployed, 'old')
    set_active(@built)
    shell(<<~'ZSH')
      jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || exit 1
      [[ "$(<"$DEPLOYED/Contents/Resources/业务.zsh")" == new ]] || exit 2
      jobs_deployment_retire_other_copies "$DEPLOYED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || exit 3
      jobs_deployment_rollback || exit 4
      [[ "$(<"$DEPLOYED/Contents/Resources/业务.zsh")" == old ]] || exit 5
      /usr/bin/grep -F "register:$BUILT" "$CALLS" >/dev/null || exit 6
      /usr/bin/grep -F "unregister:$BUILT" "$CALLS" >/dev/null || exit 7
    ZSH
    assert_empty Dir.glob(File.join(@applications, '.JobsFinderDeployment.*'))
  end

  def test_registration_failure_on_first_application_install_restores_build_registration
    set_active(@built)
    shell(<<~'ZSH')
      jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || exit 1
      jobs_deployment_retire_other_copies "$DEPLOYED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || exit 2
      jobs_deployment_rollback || exit 3
      [[ ! -e "$DEPLOYED" && -d "$BUILT" ]] || exit 4
      /usr/bin/grep -F "register:$BUILT" "$CALLS" >/dev/null || exit 5
    ZSH
  end

  def test_copy_failure_keeps_previous_application
    make_app(@deployed, 'old')
    shell(<<~'ZSH')
      jobs_deployment_copy_app() { /bin/mkdir "$2"; print partial > "$2/partial"; return 7; }
      jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && exit 1
      [[ "$?" == 7 ]] || exit 2
      [[ "$(<"$DEPLOYED/Contents/Resources/业务.zsh")" == old && -z "$JOBS_DEPLOYMENT_TRANSACTION_DIR" ]] || exit 3
    ZSH
  end

  def test_bad_staging_signature_does_not_replace_previous_application
    make_app(@deployed, 'old')
    shell(<<~'ZSH')
      jobs_deployment_verify_signature() { [[ "$1" != */staging.app ]]; }
      jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && exit 1
      [[ "$(<"$DEPLOYED/Contents/Resources/业务.zsh")" == old && -z "$JOBS_DEPLOYMENT_TRANSACTION_DIR" ]] || exit 2
    ZSH
  end

  def test_failed_final_move_restores_previous_application
    make_app(@deployed, 'old')
    shell(<<~'ZSH')
      jobs_deployment_verify_signature() { [[ "$1" != */staging.app ]] || /bin/rm -r -- "$1"; }
      jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && exit 1
      [[ "$(<"$DEPLOYED/Contents/Resources/业务.zsh")" == old && -z "$JOBS_DEPLOYMENT_TRANSACTION_DIR" ]] || exit 2
    ZSH
  end

  def test_foreign_same_name_application_is_never_overwritten_or_uninstalled
    make_app(@deployed, 'foreign', app_id: 'com.other.fixture')
    shell(<<~'ZSH')
      jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && exit 1
      jobs_deployment_uninstall "$DEPLOYED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && exit 2
      [[ "$(<"$DEPLOYED/Contents/Resources/业务.zsh")" == foreign && ! -e "$CALLS" ]] || exit 3
    ZSH
  end

  def test_symlink_destination_and_linked_applications_parent_are_rejected
    File.symlink(@built, @deployed)
    shell('jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && exit 1; [[ -L "$DEPLOYED" && -d "$BUILT" ]] || exit 2')
    File.symlink(@applications, File.join(@root, 'linked-apps'))
    shell(<<~'ZSH')
      JOBS_FINDER_APPLICATIONS_DIR="$TEST_ROOT/linked-apps"
      jobs_deployment_app_path "$BUILT" && exit 1
      JOBS_FINDER_APPLICATIONS_DIR=/
      jobs_deployment_app_path "$BUILT" && exit 2
      return 0
    ZSH
  end

  def test_external_resource_link_is_rejected_before_publication
    File.write(File.join(@root, 'outside.zsh'), 'external')
    File.symlink(File.join(@root, 'outside.zsh'), File.join(@built, 'Contents/Resources/link.zsh'))
    shell('jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && exit 1; [[ ! -e "$DEPLOYED" ]] || exit 2')
  end

  def test_exact_location_matching_and_other_enabled_detection
    set_active(@built)
    shell(<<~'ZSH')
      jobs_deployment_matches_path "$DEPLOYED" "$BUILT" || exit 1
      jobs_deployment_matches_path "$DEPLOYED/Contents/PlugIns/$EXTENSION" "$BUILT" || exit 2
      jobs_deployment_matches_path "$BUILT/Contents/PlugIns/$EXTENSION" "$BUILT" && exit 3
      jobs_deployment_matches_path "$DEPLOYED.backup" "$BUILT" && exit 4
      jobs_deployment_matches_path "$DEPLOYED/Contents/PlugIns/extra/$EXTENSION" "$BUILT" && exit 5
      jobs_deployment_has_other_enabled "$DEPLOYED" "$EXTENSION_ID" || exit 6
      jobs_deployment_has_other_enabled "$BUILT" "$EXTENSION_ID" && exit 7
      jobs_deployment_selected_exists "$BUILT" || exit 8
      return 0
    ZSH
  end

  def test_uninstall_removes_only_selected_application_and_never_build_copy
    make_app(@deployed, 'old')
    set_active(@built)
    shell(<<~'ZSH')
      jobs_deployment_uninstall "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && exit 1
      jobs_deployment_uninstall "$DEPLOYED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || exit 2
      [[ ! -e "$DEPLOYED" && -d "$BUILT" ]] || exit 3
      [[ "$(<"$CALLS")" == "unregister:$DEPLOYED" ]] || exit 4
    ZSH
  end

  def test_build_switch_retirement_can_restore_application_registration
    make_app(@deployed, 'old')
    set_active(@deployed)
    shell(<<~'ZSH')
      JOBS_FINDER_INSTALL_LOCATION=build
      jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || exit 5
      jobs_deployment_retire_other_copies "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || exit 1
      jobs_deployment_rollback || exit 2
      [[ -d "$DEPLOYED" && -d "$BUILT" ]] || exit 3
      /usr/bin/grep -F "register:$DEPLOYED" "$CALLS" >/dev/null || exit 4
      /usr/bin/grep -F "unregister:$BUILT" "$CALLS" >/dev/null || exit 6
    ZSH
  end

  def test_build_install_rollback_without_retirement_restores_original_application
    make_app(@deployed, 'old')
    set_active(@deployed)
    shell(<<~'ZSH')
      JOBS_FINDER_INSTALL_LOCATION=build
      jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || exit 1
      jobs_deployment_rollback || exit 2
      [[ "$(<"$CALLS")" == $'unregister:'"$BUILT"$'\nregister:'"$DEPLOYED" ]] || exit 3
      [[ "$(<"$DEPLOYED/Contents/Resources/业务.zsh")" == old ]] || exit 4
    ZSH
  end

  def test_registration_restore_failure_keeps_original_file_and_backup_transaction_for_retry
    make_app(@deployed, 'old')
    set_active(@built)
    shell(<<~'ZSH')
      jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || exit 1
      jobs_deployment_register_restored_app() { return 7; }
      jobs_deployment_rollback && exit 2
      [[ "$(<"$DEPLOYED/Contents/Resources/业务.zsh")" == old && -d "$JOBS_DEPLOYMENT_TRANSACTION_DIR" ]] || exit 3
      jobs_deployment_register_restored_app() { return 0; }
      jobs_deployment_rollback || exit 4
      [[ -z "$JOBS_DEPLOYMENT_TRANSACTION_DIR" ]] || exit 5
    ZSH
  end

  def test_enabled_metadata_parser_and_query_error_are_not_treated_as_disabled
    shell(<<~'ZSH')
      fixture_pluginkit() {
        print -r -- '+ com.jobs.fixture.findersync(1.0)'
        print -r -- "    Path = $BUILT/Contents/PlugIns/$EXTENSION"
        print -r -- '- com.jobs.fixture.findersync(1.0)'
        print -r -- "    Path = $DEPLOYED/Contents/PlugIns/$EXTENSION"
      }
      functions[jobs_deployment_enabled_extension_paths]="$functions[jobs_deployment_enabled_extension_paths_original]"
      [[ -n "$functions[jobs_deployment_enabled_extension_paths]" ]] || exit 1
      functions[jobs_deployment_enabled_extension_paths]="${functions[jobs_deployment_enabled_extension_paths]//\/usr\/bin\/pluginkit/fixture_pluginkit}"
      [[ "$(jobs_deployment_enabled_extension_paths "$EXTENSION_ID")" == "$BUILT/Contents/PlugIns/$EXTENSION" ]] || exit 2
      jobs_deployment_has_other_enabled "$DEPLOYED" "$EXTENSION_ID" || exit 3
      fixture_pluginkit() { return 9; }
      jobs_deployment_has_other_enabled "$DEPLOYED" "$EXTENSION_ID" && exit 4
      [[ "$?" == 2 ]] || exit 5
    ZSH
  end

  def test_internal_relative_resources_are_copied_and_commit_detects_concurrent_target_swap
    File.symlink('业务.zsh', File.join(@built, 'Contents/Resources/internal.zsh'))
    shell(<<~'ZSH')
      jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || exit 1
      [[ -L "$DEPLOYED/Contents/Resources/internal.zsh" && "$(<"$DEPLOYED/Contents/Resources/internal.zsh")" == new ]] || exit 2
      /bin/mv "$DEPLOYED" "$TEST_ROOT/concurrent.app"
      /bin/mkdir "$DEPLOYED"
      jobs_deployment_commit && exit 3
      [[ -d "$JOBS_DEPLOYMENT_TRANSACTION_DIR" && -d "$TEST_ROOT/concurrent.app" ]] || exit 4
    ZSH
  end

  def test_rollback_preserves_concurrent_replacement_and_retains_backup
    make_app(@deployed, 'old')
    shell(<<~'ZSH')
      jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || exit 1
      /bin/mv "$DEPLOYED" "$TEST_ROOT/moved.app"
      /bin/mkdir "$DEPLOYED"
      print concurrent > "$DEPLOYED/concurrent"
      jobs_deployment_rollback && exit 2
      [[ -f "$DEPLOYED/concurrent" && -d "$JOBS_DEPLOYMENT_TRANSACTION_DIR/previous.app" ]] || exit 3
    ZSH
  end

  def test_invalid_location_and_repeated_uncommitted_install_are_rejected
    shell(<<~'ZSH')
      JOBS_FINDER_INSTALL_LOCATION=invalid
      jobs_deployment_app_path "$BUILT" && exit 1
      JOBS_FINDER_INSTALL_LOCATION=applications
      jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || exit 2
      jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && exit 3
      jobs_deployment_commit || exit 4
    ZSH
  end

  def test_single_combined_container_is_created_with_fixed_name_and_identity
    FileUtils.remove_entry(@container)
    shell(<<~'ZSH')
      jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && jobs_deployment_commit || exit 1
      [[ "$(jobs_deployment_container_path)" == "$CONTAINER" ]] || exit 2
      [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$CONTAINER/Contents/Info.plist")" == Jobs自定义右键菜单 ]] || exit 3
    ZSH
    assert_equal ['Jobs自定义右键菜单.app'], Dir.children(@applications)
  end

  def test_successful_commit_migrates_only_selected_owned_top_level_application
    legacy = File.join(@applications, 'JobsFixture.app')
    other = File.join(@applications, 'JobsOther.app')
    make_app(legacy, 'legacy')
    make_app(other, 'other')
    set_active(legacy)
    shell(<<~'ZSH')
      jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && jobs_deployment_commit || exit 1
      [[ ! -e "${CONTAINER:h}/JobsFixture.app" && -d "${CONTAINER:h}/JobsOther.app" && -d "$DEPLOYED" ]] || exit 2
    ZSH
    assert_equal 'other', File.read(resource(other))
  end

  def test_failed_commit_restores_migrated_top_level_application_and_original_registration
    legacy = File.join(@applications, 'JobsFixture.app')
    make_app(legacy, 'legacy')
    set_active(legacy)
    shell(<<~'ZSH')
      jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || exit 1
      functions[original_release]="$functions[jobs_deployment_release_transaction]"
      jobs_deployment_release_transaction() { return 7; }
      jobs_deployment_commit && exit 2
      [[ ! -e "${CONTAINER:h}/JobsFixture.app" && -d "$JOBS_DEPLOYMENT_TRANSACTION_DIR/legacy.app" ]] || exit 3
      functions[jobs_deployment_release_transaction]="$functions[original_release]"
      jobs_deployment_rollback || exit 4
      [[ "$(<"${CONTAINER:h}/JobsFixture.app/Contents/Resources/业务.zsh")" == legacy ]] || exit 5
      /usr/bin/grep -F "register:${CONTAINER:h}/JobsFixture.app" "$CALLS" >/dev/null || exit 6
    ZSH
  end

  def test_unknown_top_level_application_is_retained_when_combined_host_is_installed
    legacy = File.join(@applications, 'JobsFixture.app')
    make_app(legacy, 'foreign', app_id: 'com.other.fixture')
    shell('jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && jobs_deployment_commit || exit 1')
    assert_equal 'foreign', File.read(resource(legacy))
    assert File.directory?(@deployed)
  end

  def test_foreign_container_and_container_symlink_are_rejected
    File.write(File.join(@container, 'Contents/Info.plist'), '<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.other.manager</string></dict></plist>')
    shell('jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && exit 1; [[ ! -e "$DEPLOYED" ]] || exit 2')
    FileUtils.remove_entry(@container)
    File.symlink(@built, @container)
    shell('jobs_deployment_app_path "$BUILT" && exit 1; [[ -L "$CONTAINER" ]] || exit 2')
  end

  def test_uninstall_keeps_sibling_host_and_removes_container_after_last_host
    make_app(@deployed, 'old')
    sibling = File.join(File.dirname(@deployed), 'JobsOther.app')
    make_app(sibling, 'other')
    shell(<<~'ZSH')
      jobs_deployment_uninstall "$DEPLOYED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || exit 1
      [[ -d "$CONTAINER/Contents/Applications/JobsOther.app" && -d "$CONTAINER" ]] || exit 2
      jobs_deployment_uninstall "$CONTAINER/Contents/Applications/JobsOther.app" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || exit 3
      [[ ! -e "$CONTAINER" ]] || exit 4
    ZSH
  end

  def test_outer_signing_preserves_signed_child_entitlements_and_verifies_complete_container
    extension_bundle = File.join(@built, 'Contents/PlugIns', EXTENSION)
    FileUtils.cp('/usr/bin/true', File.join(extension_bundle, 'Contents/MacOS/FixtureExtension'))
    File.chmod(0o755, File.join(extension_bundle, 'Contents/MacOS/FixtureExtension'))
    entitlements = File.join(@root, 'fixture-entitlements.plist')
    File.write(entitlements, '<plist version="1.0"><dict><key>com.jobs.fixture</key><true/></dict></plist>')
    [
      ['/usr/bin/codesign', '--force', '--sign', '-', '--entitlements', entitlements, extension_bundle],
      ['/usr/bin/codesign', '--force', '--sign', '-', @built]
    ].each do |command|
      output, error, result = Open3.capture3(*command)
      assert result.success?, "临时夹具签名失败：#{output}#{error}"
    end
    before, = Open3.capture3('/usr/bin/codesign', '-d', '--entitlements', ':-', extension_bundle)
    shell(<<~'ZSH')
      functions[jobs_deployment_verify_signature]="$functions[jobs_deployment_verify_signature_original]"
      functions[jobs_deployment_sign_container]="$functions[jobs_deployment_sign_container_original]"
      jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && jobs_deployment_commit || exit 1
      /usr/bin/codesign --verify --deep --strict "$CONTAINER" || exit 2
    ZSH
    after, error, result = Open3.capture3('/usr/bin/codesign', '-d', '--entitlements', ':-', File.join(@deployed, 'Contents/PlugIns', EXTENSION))
    assert result.success?, error
    assert_includes after, 'com.jobs.fixture'
    assert_equal before, after
  end

  def test_cleanup_removes_only_committed_derived_root_and_deployed_host_still_runs
    sibling = File.join(File.dirname(@derived), 'JobsOtherDerivedData')
    FileUtils.mkdir_p(sibling)
    File.write(File.join(sibling, 'keep'), 'sibling')
    shell(<<~'ZSH')
      jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && jobs_deployment_commit || exit 1
      print -r -- "$DEPLOYED/Contents/PlugIns/$EXTENSION" > "$TEST_ROOT/active.txt"
      jobs_deployment_cleanup_build_products "$BUILT" "$DERIVED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || exit 2
      [[ ! -e "$DERIVED" && -d "$DEPLOYED" ]] || exit 3
    ZSH
    assert_equal 'sibling', File.read(File.join(sibling, 'keep'))
    host = File.join(@deployed, 'Contents/MacOS/FixtureHost')
    output, error, result = Open3.capture3([host, host])
    assert result.success?, error
    assert_equal 'new', output
  end

  def test_cleanup_rejects_uncommitted_build_mode_and_unrelated_roots
    shell(<<~'ZSH')
      jobs_deployment_cleanup_build_products "$BUILT" "$DERIVED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && exit 1
      jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || exit 2
      jobs_deployment_cleanup_build_products "$BUILT" "$DERIVED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && exit 3
      jobs_deployment_commit || exit 4
      print -r -- "$DEPLOYED/Contents/PlugIns/$EXTENSION" > "$TEST_ROOT/active.txt"
      for rejected in "$TEST_ROOT" "${DERIVED:h}" "$CONTAINER" "$TEST_ROOT/编译 产物" /; do
        jobs_deployment_cleanup_build_products "$BUILT" "$rejected" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && exit 5
      done
      JOBS_FINDER_INSTALL_LOCATION=build
      jobs_deployment_cleanup_build_products "$BUILT" "$DERIVED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && exit 6
      [[ -d "$DERIVED" && -d "$DEPLOYED" ]] || exit 7
    ZSH
  end

  def test_cleanup_requires_exact_active_target_and_no_old_registered_source_or_process
    shell(<<~'ZSH')
      jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && jobs_deployment_commit || exit 1
      jobs_deployment_cleanup_build_products "$BUILT" "$DERIVED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && exit 2
      print -r -- "$DEPLOYED/Contents/PlugIns/$EXTENSION" > "$TEST_ROOT/active.txt"
      print -r -- "$BUILT/Contents/PlugIns/$EXTENSION" > "$TEST_ROOT/registered.txt"
      jobs_deployment_cleanup_build_products "$BUILT" "$DERIVED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && exit 3
      /bin/rm "$TEST_ROOT/registered.txt"
      jobs_deployment_source_is_running() { return 0; }
      jobs_deployment_cleanup_build_products "$BUILT" "$DERIVED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && exit 4
      [[ -d "$DERIVED" && -d "$DEPLOYED" ]] || exit 5
    ZSH
  end

  def test_cleanup_rejects_linked_parent_and_restores_root_when_a_process_appears
    shell(<<~'ZSH')
      jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && jobs_deployment_commit || exit 1
      print -r -- "$DEPLOYED/Contents/PlugIns/$EXTENSION" > "$TEST_ROOT/active.txt"
      parent_dir="${DERIVED:h}"
      /bin/mv "$parent_dir" "$parent_dir.moved"
      /bin/ln -s "$parent_dir.moved" "$parent_dir"
      jobs_deployment_cleanup_build_products "$BUILT" "$DERIVED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && exit 2
      /bin/rm "$parent_dir"
      /bin/mv "$parent_dir.moved" "$parent_dir"
      process_checks=0
      jobs_deployment_source_is_running() { (( process_checks += 1 )); (( process_checks > 1 )); }
      jobs_deployment_cleanup_build_products "$BUILT" "$DERIVED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && exit 3
      [[ -d "$DERIVED" && -d "$DEPLOYED" ]] || exit 4
    ZSH
  end

  def test_unregister_is_idempotent_only_when_failed_remove_has_no_remaining_exact_record
    shell(<<~'ZSH')
      functions[jobs_deployment_unregister_app]="$functions[jobs_deployment_unregister_app_original]"
      jobs_deployment_remove_extension_path() { return 7; }
      jobs_deployment_registered_extension_paths_for_bundle() { return 0; }
      jobs_deployment_unregister_host_path() { print -r -- "host:$1" >> "$CALLS"; }
      jobs_deployment_unregister_app "$BUILT" "$EXTENSION" || exit 1
      [[ "$(<"$CALLS")" == "host:$BUILT" ]] || exit 2
      /bin/rm "$CALLS"
      jobs_deployment_registered_extension_paths_for_bundle() { print -r -- "$BUILT/Contents/PlugIns/$EXTENSION"; }
      jobs_deployment_unregister_app "$BUILT" "$EXTENSION" && exit 3
      [[ ! -e "$CALLS" ]] || exit 4
      jobs_deployment_registered_extension_paths_for_bundle() { return 9; }
      jobs_deployment_unregister_app "$BUILT" "$EXTENSION" && exit 5
      [[ ! -e "$CALLS" ]] || exit 6
    ZSH
  end

  def test_missing_host_registration_allows_exact_uninstall_and_repeat_without_touching_other_copy
    make_app(@deployed, 'old')
    set_active(@built)
    shell(<<~'ZSH')
      functions[jobs_deployment_unregister_app]="$functions[jobs_deployment_unregister_app_original]"
      jobs_deployment_remove_extension_path() { return 0; }
      jobs_deployment_unregister_host_command() {
        print -r -- "host:$1" >> "$CALLS"
        print -u2 -r -- "failed to scan $1: -10814"
        print -u2 -r -- ' from spotlight'
        return 7
      }
      jobs_deployment_dump_host_registrations() {
        printf '%s\n' '--------------------------------------------------------------------------------' 'bundle id: fixture (0x1)' "path: $BUILT (0xab)" 'identifier: com.jobs.fixture'
        printf '%s\n' '--------------------------------------------------------------------------------' 'bundle id: prefix (0x2)' "path: $DEPLOYED.backup (0xac)" 'identifier: com.jobs.fixture'
      }
      jobs_deployment_uninstall "$DEPLOYED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || exit 1
      [[ ! -e "$DEPLOYED" && -d "$BUILT" && ! -e "$CONTAINER" ]] || exit 2
      jobs_deployment_uninstall "$DEPLOYED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || exit 3
      [[ "$(<"$CALLS")" == "host:$DEPLOYED" ]] || exit 4
    ZSH
  end

  def test_failed_host_unregister_keeps_app_when_exact_registration_still_exists
    make_app(@deployed, 'old')
    shell(<<~'ZSH')
      functions[jobs_deployment_unregister_app]="$functions[jobs_deployment_unregister_app_original]"
      jobs_deployment_remove_extension_path() { return 0; }
      jobs_deployment_unregister_host_command() { print -u2 -r -- "failed to scan $1: -10814"; return 7; }
      jobs_deployment_dump_host_registrations() { printf '%s\n' 'bundle id: fixture (0x1)' "path: $DEPLOYED (0xab)"; }
      result=0
      jobs_deployment_uninstall "$DEPLOYED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || result=$?
      [[ "$result" == 7 && -d "$DEPLOYED" && -d "$BUILT" ]] || exit 1
      [[ ! -e "$JOBS_FINDER_APPLICATIONS_DIR/.JobsFinderDeployment.Jobs自定义右键菜单.lock" ]] || exit 2
    ZSH
  end

  def test_host_unregister_query_failure_or_invalid_dump_keeps_app_and_failure_code
    make_app(@deployed, 'old')
    shell(<<~'ZSH')
      functions[jobs_deployment_unregister_app]="$functions[jobs_deployment_unregister_app_original]"
      jobs_deployment_remove_extension_path() { return 0; }
      jobs_deployment_unregister_host_command() { print -u2 -r -- "failed to scan $1: -10814"; return 7; }
      for scenario in failed empty malformed partial; do
        jobs_deployment_dump_host_registrations() {
          case "$scenario" in
            failed) print -r -- 'bundle id: partial'; return 9 ;;
            empty) return 0 ;;
            malformed) print -r -- 'unexpected database format' ;;
            partial) printf '%s\n' 'bundle id: fixture (0x1)' "path: $BUILT (0xab)" '--------------------------------' 'bundle id: truncated' ;;
          esac
        }
        result=0
        jobs_deployment_uninstall "$DEPLOYED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || result=$?
        [[ "$result" == 7 && -d "$DEPLOYED" && -d "$BUILT" ]] || exit 1
      done
    ZSH
  end

  def test_host_unregister_preserves_other_failures_without_querying_or_deleting
    make_app(@deployed, 'old')
    shell(<<~'ZSH')
      functions[jobs_deployment_unregister_app]="$functions[jobs_deployment_unregister_app_original]"
      jobs_deployment_remove_extension_path() { return 0; }
      jobs_deployment_dump_host_registrations() { print UNEXPECTED_QUERY >> "$CALLS"; return 0; }
      for reason in permission unknown mixed other-path; do
        jobs_deployment_unregister_host_command() {
          case "$reason" in
            permission) print -u2 -r -- 'Operation not permitted' ;;
            unknown) print -u2 -r -- 'failed to communicate with LaunchServices' ;;
            mixed) printf '%s\n' "failed to scan $1: -10814" 'Permission denied' ;;
            other-path) print -u2 -r -- "failed to scan $1.backup: -10814" ;;
          esac
          return 13
        }
        result=0
        jobs_deployment_uninstall "$DEPLOYED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || result=$?
        [[ "$result" == 13 && -d "$DEPLOYED" && ! -e "$CALLS" ]] || exit 1
      done
    ZSH
  end

  def test_host_dump_parser_preserves_spaces_unicode_and_literal_hex_suffix_in_paths
    shell(<<~'ZSH')
      jobs_deployment_dump_host_registrations() {
        printf '%s\n' '--------------------------------' 'bundle id: fixture (0x1)' "path: $BUILT (0xab) (0x1c)" 'identifier: com.jobs.fixture'
        printf '%s\n' '--------------------------------' 'bundle id: other (0x2)' "path: $DEPLOYED" 'identifier: com.jobs.fixture'
      }
      parsed="$(jobs_deployment_registered_host_paths)" || exit 1
      [[ "$parsed" == "$BUILT (0xab)"$'\n'"$DEPLOYED" ]] || exit 2
    ZSH
  end

  def test_uninstall_reports_delete_failure_or_false_success_and_releases_scope_lock
    make_app(@deployed, 'old')
    shell(<<~'ZSH')
      jobs_deployment_remove_app_files() { return 17; }
      result=0
      jobs_deployment_uninstall "$DEPLOYED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || result=$?
      [[ "$result" == 17 && -d "$DEPLOYED" && -d "$BUILT" ]] || exit 1
      [[ ! -e "$JOBS_FINDER_APPLICATIONS_DIR/.JobsFinderDeployment.Jobs自定义右键菜单.lock" ]] || exit 2
      jobs_deployment_remove_app_files() { return 0; }
      result=0
      jobs_deployment_uninstall "$DEPLOYED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || result=$?
      [[ "$result" == 1 && -d "$DEPLOYED" && -d "$BUILT" ]] || exit 3
    ZSH
  end

  def test_exact_app_removal_permission_denial_emits_blocker_and_retains_files
    make_app(@deployed, 'old')
    shell(<<~'ZSH')
      exec 2> "$TEST_ROOT/remove-errors.log"
      JOBS_FINDER_RESPONSIBLE_APP=FixtureManager.app
      for reason in 'Permission denied' 'Operation not permitted'; do
        jobs_deployment_remove_app_command() { print -u2 -r -- "rm: $1/Contents/Resources/业务.zsh: $reason"; return 1; }
        result=0
        jobs_deployment_uninstall "$DEPLOYED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || result=$?
        [[ "$result" == 77 && -d "$DEPLOYED" && -d "$BUILT" ]] || exit 1
        [[ ! -e "$JOBS_FINDER_APPLICATIONS_DIR/.JobsFinderDeployment.Jobs自定义右键菜单.lock" ]] || exit 2
      done
      /usr/bin/grep -F $'JOBS_MANAGER_BLOCKED\tapp-management\t77' "$TEST_ROOT/remove-errors.log" >/dev/null || exit 3
      /usr/bin/grep -F FixtureManager.app "$TEST_ROOT/remove-errors.log" >/dev/null || exit 4
      /usr/bin/grep -F '目录权限' "$TEST_ROOT/remove-errors.log" >/dev/null || exit 5
    ZSH
  end

  def test_remove_unknown_error_or_permission_for_another_path_preserves_original_code
    make_app(@deployed, 'old')
    shell(<<~'ZSH')
      exec 2> "$TEST_ROOT/remove-errors.log"
      for reason in other-path ordinary; do
        jobs_deployment_remove_app_command() {
          if [[ "$reason" == other-path ]]; then
            print -u2 -r -- "rm: $1.backup: Permission denied"
          else
            print -u2 -r -- "rm: $1: Input/output error"
          fi
          return 17
        }
        result=0
        jobs_deployment_uninstall "$DEPLOYED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || result=$?
        [[ "$result" == 17 && -d "$DEPLOYED" && -d "$BUILT" ]] || exit 1
      done
      /usr/bin/grep -F JOBS_MANAGER_BLOCKED "$TEST_ROOT/remove-errors.log" >/dev/null && exit 2
      return 0
    ZSH
  end

  def test_outer_signature_is_prepared_before_registration_and_commit_does_not_resign
    shell(<<~'ZSH')
      sign_count=0
      jobs_deployment_sign_container() { (( sign_count += 1 )); print -r -- sign >> "$CALLS"; }
      jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || exit 1
      [[ "$sign_count" == 1 && "$JOBS_DEPLOYMENT_PREPARED_REGISTRATION" == 1 ]] || exit 2
      print -r -- register >> "$CALLS"
      jobs_deployment_prepare_registration || exit 3
      jobs_deployment_commit || exit 4
      [[ "$sign_count" == 1 && "$(<"$CALLS")" == $'sign\nregister' ]] || exit 5
    ZSH
  end

  def test_registration_postcheck_resets_stability_after_an_early_enabled_record_drops
    make_app(@deployed, 'installed')
    registration_shell(<<~'ZSH')
      identity="$(/usr/bin/stat -f '%d:%i' "$DEPLOYED")"
      jobs_deployment_enabled_extension_paths() {
        [[ "$1" == "$EXTENSION_ID" ]] || return 97
        local tick="$(<"$REGISTRATION_CLOCK")"
        if (( tick == 2 )) && [[ ! -e "$TEST_ROOT/repaired-$EXTENSION_ID" ]]; then
          return 0
        fi
        print -r -- "$DEPLOYED/Contents/PlugIns/$EXTENSION"
      }
      jobs_deployment_verify_registrations 3 10 2 "$DEPLOYED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" "$identity" || exit 1
      [[ "$(<"$REGISTRATION_CLOCK")" == 6 ]] || exit 2
      [[ "$(/usr/bin/grep -c '^enable:' "$CALLS")" == 1 ]] || exit 3
      [[ "$(<"$CALLS")" == $'register-host:'"$DEPLOYED"$'\ninitialize-host:'"$DEPLOYED"'|'"$EXTENSION_ID"$'\nadd-extension:'"$DEPLOYED/Contents/PlugIns/$EXTENSION"$'\nenable:'"$EXTENSION_ID" ]] || exit 4
    ZSH
  end

  def test_registration_postcheck_shares_one_stability_window_for_multiple_ids
    make_app(@deployed, 'first')
    second = File.join(@container, 'Contents/Applications/JobsSecond.app')
    make_app(second, 'second', app_id: 'com.jobs.second', extension_id: 'com.jobs.second.findersync')
    registration_shell(<<~'ZSH')
      second="$CONTAINER/Contents/Applications/JobsSecond.app"
      first_identity="$(/usr/bin/stat -f '%d:%i' "$DEPLOYED")"
      second_identity="$(/usr/bin/stat -f '%d:%i' "$second")"
      jobs_deployment_enabled_extension_paths() {
        print -r -- "$1" >> "$TEST_ROOT/queries"
        case "$1" in
          com.jobs.fixture.findersync) print -r -- "$DEPLOYED/Contents/PlugIns/$EXTENSION" ;;
          com.jobs.second.findersync) print -r -- "$second/Contents/PlugIns/$EXTENSION" ;;
          *) return 97 ;;
        esac
      }
      jobs_deployment_verify_registrations 3 10 2 \
        "$DEPLOYED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" "$first_identity" \
        "$second" com.jobs.second "$EXTENSION" com.jobs.second.findersync "$second_identity" || exit 1
      [[ "$(<"$REGISTRATION_CLOCK")" == 3 ]] || exit 2
      [[ ! -e "$CALLS" ]] || exit 3
      [[ "$(/usr/bin/grep -c '^com.jobs.fixture.findersync$' "$TEST_ROOT/queries")" == 4 ]] || exit 4
      [[ "$(/usr/bin/grep -c '^com.jobs.second.findersync$' "$TEST_ROOT/queries")" == 4 ]] || exit 5
    ZSH
  end

  def test_registration_postcheck_failed_or_cancelled_repair_stops_before_other_ids
    make_app(@deployed, 'first')
    second = File.join(@container, 'Contents/Applications/JobsSecond.app')
    make_app(second, 'second', app_id: 'com.jobs.second', extension_id: 'com.jobs.second.findersync')
    [17, 129, 130, 143].each do |failure_code|
      registration_shell(<<~'ZSH' + "\nTEST_FAILURE_CODE=#{failure_code}\n" + <<~'ZSH')
        jobs_deployment_registration_register_host() {
          print -r -- "register-host:$1" >> "$CALLS"
          return "$TEST_FAILURE_CODE"
        }
        jobs_deployment_enabled_extension_paths() { print -r -- "$1" >> "$TEST_ROOT/queries"; return 0; }
      ZSH
        second="$CONTAINER/Contents/Applications/JobsSecond.app"
        identity="$(/usr/bin/stat -f '%d:%i' "$DEPLOYED")"
        second_identity="$(/usr/bin/stat -f '%d:%i' "$second")"
        result=0
        jobs_deployment_verify_registrations 3 10 2 \
          "$DEPLOYED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" "$identity" \
          "$second" com.jobs.second "$EXTENSION" com.jobs.second.findersync "$second_identity" || result=$?
        [[ "$result" == "$TEST_FAILURE_CODE" && "$(<"$REGISTRATION_CLOCK")" == 0 ]] || exit 1
        [[ "$(<"$TEST_ROOT/queries")" == "$EXTENSION_ID" ]] || exit 2
        [[ "$(<"$CALLS")" == "register-host:$DEPLOYED" ]] || exit 3
      ZSH
    end
  end

  def test_registration_postcheck_query_errors_do_not_trigger_registration_writes
    make_app(@deployed, 'installed')
    [9, 129, 130, 143].each do |failure_code|
      registration_shell("TEST_QUERY_CODE=#{failure_code}\n" + <<~'ZSH')
        identity="$(/usr/bin/stat -f '%d:%i' "$DEPLOYED")"
        jobs_deployment_enabled_extension_paths() { return "$TEST_QUERY_CODE"; }
        result=0
        jobs_deployment_verify_registrations 3 10 2 "$DEPLOYED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" "$identity" || result=$?
        [[ "$result" == "$TEST_QUERY_CODE" && ! -e "$CALLS" && "$(<"$REGISTRATION_CLOCK")" == 0 ]] || exit 1
      ZSH
    end
  end

  def test_registration_postcheck_does_not_override_another_enabled_copy_of_the_same_id
    make_app(@deployed, 'installed')
    registration_shell(<<~'ZSH')
      identity="$(/usr/bin/stat -f '%d:%i' "$DEPLOYED")"
      jobs_deployment_enabled_extension_paths() { print -r -- "$BUILT/Contents/PlugIns/$EXTENSION"; }
      result=0
      jobs_deployment_verify_registrations 3 10 2 "$DEPLOYED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" "$identity" || result=$?
      [[ "$result" == 1 && ! -e "$CALLS" && "$(<"$REGISTRATION_CLOCK")" == 0 ]] || exit 1
    ZSH
  end

  def test_registration_postcheck_detects_a_concurrent_target_swap_before_repair
    make_app(@deployed, 'installed')
    registration_shell(<<~'ZSH')
      identity="$(/usr/bin/stat -f '%d:%i' "$DEPLOYED")"
      jobs_deployment_enabled_extension_paths() { print -r -- "$DEPLOYED/Contents/PlugIns/$EXTENSION"; }
      jobs_deployment_registration_pause() {
        print 1 > "$REGISTRATION_CLOCK"
        /bin/mv -- "$DEPLOYED" "$DEPLOYED.original" || return 98
        /bin/mkdir -- "$DEPLOYED" || return 98
      }
      result=0
      jobs_deployment_verify_registrations 3 10 2 "$DEPLOYED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" "$identity" || result=$?
      [[ "$result" == 1 && ! -e "$CALLS" && -d "$DEPLOYED.original" && -d "$DEPLOYED" ]] || exit 1
    ZSH
  end

  def test_registration_postcheck_limits_repairs_per_id_and_total_observation_time
    make_app(@deployed, 'installed')
    registration_shell(<<~'ZSH')
      identity="$(/usr/bin/stat -f '%d:%i' "$DEPLOYED")"
      jobs_deployment_enabled_extension_paths() { return 0; }
      result=0
      jobs_deployment_verify_registrations 3 15 2 "$DEPLOYED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" "$identity" || result=$?
      [[ "$result" == 1 && "$(<"$REGISTRATION_CLOCK")" == 10 ]] || exit 1
      [[ "$(/usr/bin/grep -c '^enable:' "$CALLS")" == 2 ]] || exit 2
      /bin/rm -- "$CALLS" "$TEST_ROOT/repaired-$EXTENSION_ID"
      print 0 > "$REGISTRATION_CLOCK"
      jobs_deployment_enabled_extension_paths() {
        [[ -f "$TEST_ROOT/repaired-$EXTENSION_ID" ]] && print -r -- "$DEPLOYED/Contents/PlugIns/$EXTENSION"
        return 0
      }
      result=0
      jobs_deployment_verify_registrations 4 4 2 "$DEPLOYED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" "$identity" || result=$?
      [[ "$result" == 1 && "$(<"$REGISTRATION_CLOCK")" == 4 ]] || exit 3
      [[ "$(/usr/bin/grep -c '^enable:' "$CALLS")" == 1 ]] || exit 4
    ZSH
  end

  def test_registration_postcheck_allows_asynchronous_discovery_to_settle_without_spending_another_repair
    make_app(@deployed, 'installed')
    registration_shell(<<~'ZSH')
      identity="$(/usr/bin/stat -f '%d:%i' "$DEPLOYED")"
      jobs_deployment_enabled_extension_paths() {
        local tick="$(<"$REGISTRATION_CLOCK")"
        if (( tick >= 4 )); then
          print -r -- "$DEPLOYED/Contents/PlugIns/$EXTENSION"
        fi
        return 0
      }
      jobs_deployment_verify_registrations 3 15 2 "$DEPLOYED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" "$identity" || exit 1
      [[ "$(<"$REGISTRATION_CLOCK")" == 7 ]] || exit 2
      [[ "$(/usr/bin/grep -c '^enable:' "$CALLS")" == 1 ]] || exit 3
    ZSH
  end

  def test_registration_postcheck_reports_progress_while_one_shared_window_is_observed
    make_app(@deployed, 'installed')
    registration_shell(<<~'ZSH')
      exec 2> "$TEST_ROOT/registration-progress"
      identity="$(/usr/bin/stat -f '%d:%i' "$DEPLOYED")"
      jobs_deployment_enabled_extension_paths() { print -r -- "$DEPLOYED/Contents/PlugIns/$EXTENSION"; }
      jobs_deployment_verify_registrations 21 30 2 "$DEPLOYED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" "$identity" || exit 1
      [[ "$(<"$REGISTRATION_CLOCK")" == 21 && ! -e "$CALLS" ]] || exit 2
      /usr/bin/grep -F '已观察 10 秒' "$TEST_ROOT/registration-progress" >/dev/null || exit 3
      /usr/bin/grep -F '已观察 20 秒' "$TEST_ROOT/registration-progress" >/dev/null || exit 4
    ZSH
  end

  def test_registration_postcheck_cancelled_observation_stops_without_registration_writes
    make_app(@deployed, 'installed')
    registration_shell(<<~'ZSH')
      identity="$(/usr/bin/stat -f '%d:%i' "$DEPLOYED")"
      jobs_deployment_enabled_extension_paths() {
        print -r -- "$1" >> "$TEST_ROOT/queries"
        print -r -- "$DEPLOYED/Contents/PlugIns/$EXTENSION"
      }
      jobs_deployment_registration_pause() { return 130; }
      result=0
      jobs_deployment_verify_registrations 3 10 2 "$DEPLOYED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" "$identity" || result=$?
      [[ "$result" == 130 && ! -e "$CALLS" && "$(<"$TEST_ROOT/queries")" == "$EXTENSION_ID" ]] || exit 1
    ZSH
  end

  def test_registration_postcheck_does_not_report_success_when_a_pause_passes_the_total_deadline
    make_app(@deployed, 'installed')
    registration_shell(<<~'ZSH')
      identity="$(/usr/bin/stat -f '%d:%i' "$DEPLOYED")"
      jobs_deployment_enabled_extension_paths() { print -r -- "$DEPLOYED/Contents/PlugIns/$EXTENSION"; }
      jobs_deployment_registration_pause() { print 20 > "$REGISTRATION_CLOCK"; }
      result=0
      jobs_deployment_verify_registrations 3 10 2 "$DEPLOYED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" "$identity" || result=$?
      [[ "$result" == 1 && ! -e "$CALLS" && "$(<"$REGISTRATION_CLOCK")" == 20 ]] || exit 1
    ZSH
  end

  def test_registration_postcheck_rejects_a_final_signature_check_that_passes_the_deadline
    make_app(@deployed, 'installed')
    registration_shell(<<~'ZSH')
      identity="$(/usr/bin/stat -f '%d:%i' "$DEPLOYED")"
      signature_checks=0
      jobs_deployment_verify_signature() {
        (( signature_checks += 1 ))
        if (( signature_checks == 2 )); then
          print 20 > "$REGISTRATION_CLOCK"
        fi
        return 0
      }
      jobs_deployment_enabled_extension_paths() { print -r -- "$DEPLOYED/Contents/PlugIns/$EXTENSION"; }
      result=0
      jobs_deployment_verify_registrations 3 10 2 "$DEPLOYED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" "$identity" || result=$?
      [[ "$result" == 1 && "$signature_checks" == 2 && "$(<"$REGISTRATION_CLOCK")" == 20 && ! -e "$CALLS" ]] || exit 1
    ZSH
  end

  def test_registration_repair_rechecks_the_absolute_deadline_before_each_system_write
    make_app(@deployed, 'installed')
    registration_shell(<<~'ZSH')
      identity="$(/usr/bin/stat -f '%d:%i' "$DEPLOYED")"
      jobs_deployment_registration_register_host() {
        print -r -- "register-host:$1" >> "$CALLS"
        print 20 > "$REGISTRATION_CLOCK"
      }
      result=0
      jobs_deployment_repair_registration "$DEPLOYED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" "$identity" 10 || result=$?
      [[ "$result" == 1 && "$(<"$REGISTRATION_CLOCK")" == 20 ]] || exit 1
      [[ "$(<"$CALLS")" == "register-host:$DEPLOYED" ]] || exit 2
    ZSH
  end

  def test_registration_postcheck_does_not_repair_the_next_id_after_a_slow_final_write
    make_app(@deployed, 'first')
    second = File.join(@container, 'Contents/Applications/JobsSecond.app')
    make_app(second, 'second', app_id: 'com.jobs.second', extension_id: 'com.jobs.second.findersync')
    registration_shell(<<~'ZSH')
      second="$CONTAINER/Contents/Applications/JobsSecond.app"
      identity="$(/usr/bin/stat -f '%d:%i' "$DEPLOYED")"
      second_identity="$(/usr/bin/stat -f '%d:%i' "$second")"
      jobs_deployment_enabled_extension_paths() { print -r -- "$1" >> "$TEST_ROOT/queries"; return 0; }
      jobs_deployment_registration_enable_extension() {
        print -r -- "enable:$3" >> "$CALLS"
        print 20 > "$REGISTRATION_CLOCK"
      }
      result=0
      jobs_deployment_verify_registrations 3 10 2 \
        "$DEPLOYED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" "$identity" \
        "$second" com.jobs.second "$EXTENSION" com.jobs.second.findersync "$second_identity" || result=$?
      [[ "$result" == 1 && "$(<"$REGISTRATION_CLOCK")" == 20 ]] || exit 1
      [[ "$(<"$TEST_ROOT/queries")" == "$EXTENSION_ID" ]] || exit 2
      [[ "$(<"$CALLS")" == $'register-host:'"$DEPLOYED"$'\ninitialize-host:'"$DEPLOYED"'|'"$EXTENSION_ID"$'\nadd-extension:'"$DEPLOYED/Contents/PlugIns/$EXTENSION"$'\nenable:'"$EXTENSION_ID" ]] || exit 3
    ZSH
  end

  def test_registration_repair_rechecks_identity_before_each_system_write
    make_app(@deployed, 'installed')
    registration_shell(<<~'ZSH')
      identity="$(/usr/bin/stat -f '%d:%i' "$DEPLOYED")"
      jobs_deployment_registration_register_host() {
        print -r -- "register-host:$1" >> "$CALLS"
        /bin/mv -- "$DEPLOYED" "$DEPLOYED.original" || return 98
        /bin/mkdir -- "$DEPLOYED" || return 98
      }
      result=0
      jobs_deployment_repair_registration "$DEPLOYED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" "$identity" || result=$?
      [[ "$result" == 1 && "$(<"$CALLS")" == "register-host:$DEPLOYED" ]] || exit 1
      [[ -d "$DEPLOYED.original" && -d "$DEPLOYED" ]] || exit 2
    ZSH
  end

  def test_commit_retires_only_the_exact_previous_transaction_host_before_deleting_it
    make_app(@deployed, 'old')
    set_active(@deployed)
    shell(<<~'ZSH')
      jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || exit 1
      previous="$JOBS_DEPLOYMENT_TRANSACTION_DIR/previous.app"
      [[ -d "$previous" ]] || exit 2
      jobs_deployment_unregister_app() {
        [[ "$1" == "$previous" && -d "$1" && "$2" == "$EXTENSION" ]] || return 98
        print -r -- "unregister:$1" >> "$CALLS"
      }
      jobs_deployment_commit || exit 3
      [[ "$(<"$CALLS")" == "unregister:$previous" && ! -e "$previous" ]] || exit 4
      [[ "$(<"$DEPLOYED/Contents/Resources/业务.zsh")" == new ]] || exit 5
    ZSH
  end

  def test_failed_previous_transaction_unregister_retains_backup_until_safe_rollback
    make_app(@deployed, 'old')
    set_active(@deployed)
    shell(<<~'ZSH')
      jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || exit 1
      transaction="$JOBS_DEPLOYMENT_TRANSACTION_DIR"
      previous="$transaction/previous.app"
      jobs_deployment_unregister_app() { [[ "$1" != "$previous" ]] || return 31; }
      result=0
      jobs_deployment_commit || result=$?
      [[ "$result" == 31 && -d "$transaction" && -d "$previous" && -d "$JOBS_DEPLOYMENT_TRANSACTION_LOCK" ]] || exit 2
      [[ "$(<"$DEPLOYED/Contents/Resources/业务.zsh")" == new ]] || exit 3
      jobs_deployment_unregister_app() { print -r -- "unregister:$1" >> "$CALLS"; }
      jobs_deployment_rollback || exit 4
      [[ "$(<"$DEPLOYED/Contents/Resources/业务.zsh")" == old && -z "$JOBS_DEPLOYMENT_TRANSACTION_DIR" && ! -e "$transaction" ]] || exit 5
    ZSH
  end

  def test_cancelled_previous_transaction_unregister_preserves_code_and_does_not_release_backup
    make_app(@deployed, 'old')
    set_active(@deployed)
    shell(<<~'ZSH')
      for cancelled in 129 130 143; do
        jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || exit 1
        transaction="$JOBS_DEPLOYMENT_TRANSACTION_DIR"
        previous="$transaction/previous.app"
        jobs_deployment_unregister_app() { [[ "$1" != "$previous" ]] || return "$cancelled"; }
        result=0
        jobs_deployment_commit || result=$?
        [[ "$result" == "$cancelled" && -d "$previous" && -d "$JOBS_DEPLOYMENT_TRANSACTION_LOCK" ]] || exit 2
        [[ "$(<"$DEPLOYED/Contents/Resources/业务.zsh")" == new ]] || exit 3
        jobs_deployment_unregister_app() { print -r -- "unregister:$1" >> "$CALLS"; }
        jobs_deployment_rollback || exit 4
        [[ "$(<"$DEPLOYED/Contents/Resources/业务.zsh")" == old && ! -e "$transaction" ]] || exit 5
      done
    ZSH
  end

  def test_previous_transaction_retirement_preserves_a_real_extension_unregister_cancellation
    make_app(@deployed, 'old')
    set_active(@deployed)
    shell(<<~'ZSH')
      jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || exit 1
      previous="$JOBS_DEPLOYMENT_TRANSACTION_DIR/previous.app"
      functions[jobs_deployment_unregister_app]="$functions[jobs_deployment_unregister_app_original]"
      jobs_deployment_remove_extension_path() { print -r -- "remove-extension:$1" >> "$CALLS"; return 130; }
      jobs_deployment_registered_extension_paths_for_bundle() { print unexpected-query >> "$CALLS"; return 0; }
      jobs_deployment_unregister_host_path() { print unexpected-host >> "$CALLS"; return 0; }
      result=0
      jobs_deployment_commit || result=$?
      [[ "$result" == 130 && -d "$previous" && -d "$JOBS_DEPLOYMENT_TRANSACTION_LOCK" ]] || exit 2
      [[ "$(<"$CALLS")" == "remove-extension:$previous/Contents/PlugIns/$EXTENSION" ]] || exit 3
      [[ "$(<"$previous/Contents/Resources/业务.zsh")" == old && "$(<"$DEPLOYED/Contents/Resources/业务.zsh")" == new ]] || exit 4
    ZSH
  end

  def test_previous_transaction_retirement_preserves_cancellation_from_a_failed_remove_recheck
    make_app(@deployed, 'old')
    set_active(@deployed)
    shell(<<~'ZSH')
      jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || exit 1
      previous="$JOBS_DEPLOYMENT_TRANSACTION_DIR/previous.app"
      functions[jobs_deployment_unregister_app]="$functions[jobs_deployment_unregister_app_original]"
      jobs_deployment_remove_extension_path() { print -r -- "remove-extension:$1" >> "$CALLS"; return 7; }
      jobs_deployment_registered_extension_paths_for_bundle() { print -r -- "recheck:$1" >> "$CALLS"; return 130; }
      jobs_deployment_unregister_host_path() { print unexpected-host >> "$CALLS"; return 0; }
      result=0
      jobs_deployment_commit || result=$?
      [[ "$result" == 130 && -d "$previous" && -d "$JOBS_DEPLOYMENT_TRANSACTION_LOCK" ]] || exit 2
      [[ "$(<"$CALLS")" == $'remove-extension:'"$previous/Contents/PlugIns/$EXTENSION"$'\nrecheck:'"$previous/Contents/PlugIns/$EXTENSION" ]] || exit 3
      [[ "$(<"$previous/Contents/Resources/业务.zsh")" == old && "$(<"$DEPLOYED/Contents/Resources/业务.zsh")" == new ]] || exit 4
    ZSH
  end

  def test_app_management_signature_denial_returns_77_and_emits_responsible_app_marker
    shell(<<~'ZSH')
      setopt ERR_EXIT
      exec 2> "$TEST_ROOT/policy-error.log"
      JOBS_FINDER_RESPONSIBLE_APP='FixtureManager.app'
      functions[jobs_deployment_sign_container]="$functions[jobs_deployment_sign_container_original]"
      jobs_deployment_codesign_container() { print -u2 -r -- "$1: Operation not permitted"; return 1; }
      denied_result=0
      jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || denied_result=$?
      [[ "$denied_result" == 77 && -d "$DERIVED" && ! -e "$DEPLOYED" ]] || exit 1
      /usr/bin/grep -F $'JOBS_MANAGER_BLOCKED\tapp-management\t77' "$TEST_ROOT/policy-error.log" >/dev/null || exit 2
      /usr/bin/grep -F FixtureManager.app "$TEST_ROOT/policy-error.log" >/dev/null || exit 3
    ZSH
  end

  def test_app_management_marker_writes_only_precreated_private_control_flag
    shell(<<~'ZSH')
      control_dir="$TEST_ROOT/JobsFinderControl.12345678"
      /bin/mkdir -m 700 "$control_dir"
      JOBS_FINDER_BLOCKED_FILE="$control_dir/app-management.blocked"
      : > "$JOBS_FINDER_BLOCKED_FILE"
      /bin/chmod 600 "$JOBS_FINDER_BLOCKED_FILE"
      JOBS_FINDER_RESPONSIBLE_APP=FixtureManager.app
      blocked_result=0
      jobs_deployment_error 'Fixture.app: Operation not permitted' || blocked_result=$?
      [[ "$blocked_result" == 77 && "$(<"$JOBS_FINDER_BLOCKED_FILE")" == app-management ]] || exit 1
      jobs_deployment_error 'Fixture.app: Operation not permitted' || blocked_result=$?
      [[ "$(<"$JOBS_FINDER_BLOCKED_FILE")" == app-management ]] || exit 2
      [[ "$(/usr/bin/stat -f %Lp "$JOBS_FINDER_BLOCKED_FILE")" == 600 ]] || exit 3
    ZSH
  end

  def test_app_management_marker_rejects_wrong_paths_links_permissions_and_missing_flag
    shell(<<~'ZSH')
      safe_dir="$TEST_ROOT/JobsFinderControl.12345678"
      /bin/mkdir -m 700 "$safe_dir"
      flag="$safe_dir/app-management.blocked"
      : > "$flag"
      /bin/chmod 600 "$flag"
      JOBS_FINDER_RESPONSIBLE_APP=FixtureManager.app
      deny() { jobs_deployment_error 'Fixture.app: Operation not permitted' || true; }
      JOBS_FINDER_BLOCKED_FILE="$safe_dir/missing.blocked"
      deny
      [[ ! -e "$JOBS_FINDER_BLOCKED_FILE" ]] || exit 1
      JOBS_FINDER_BLOCKED_FILE="$safe_dir/other"
      print -nr -- untouched > "$JOBS_FINDER_BLOCKED_FILE"
      /bin/chmod 600 "$JOBS_FINDER_BLOCKED_FILE"
      deny
      [[ "$(<"$JOBS_FINDER_BLOCKED_FILE")" == untouched ]] || exit 2
      JOBS_FINDER_BLOCKED_FILE="$flag"
      /bin/chmod 644 "$flag"
      deny
      [[ ! -s "$flag" ]] || exit 3
      /bin/chmod 600 "$flag"
      /bin/chmod 755 "$safe_dir"
      deny
      [[ ! -s "$flag" ]] || exit 4
      /bin/chmod 700 "$safe_dir"
      /bin/mv "$flag" "$safe_dir/original"
      /bin/ln -s "$safe_dir/original" "$flag"
      deny
      [[ ! -s "$safe_dir/original" ]] || exit 5
      /bin/rm "$flag"
      /bin/ln "$safe_dir/original" "$flag"
      deny
      [[ ! -s "$safe_dir/original" ]] || exit 6
      /bin/rm "$flag"
      JOBS_FINDER_BLOCKED_FILE="$flag"
      deny
      [[ ! -e "$flag" ]] || exit 7
      /bin/mv "$safe_dir" "$TEST_ROOT/wrong-name"
      JOBS_FINDER_BLOCKED_FILE="$TEST_ROOT/wrong-name/app-management.blocked"
      : > "$JOBS_FINDER_BLOCKED_FILE"
      /bin/chmod 600 "$JOBS_FINDER_BLOCKED_FILE"
      deny
      [[ ! -s "$JOBS_FINDER_BLOCKED_FILE" ]] || exit 8
    ZSH
  end

  def test_other_signature_failure_keeps_its_error_code_without_app_management_marker
    shell(<<~'ZSH')
      exec 2> "$TEST_ROOT/signature-error.log"
      functions[jobs_deployment_sign_container]="$functions[jobs_deployment_sign_container_original]"
      jobs_deployment_codesign_container() { print -u2 -r -- 'bundle format unrecognized'; return 9; }
      failed_result=0
      jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || failed_result=$?
      [[ "$failed_result" == 9 && -d "$DERIVED" && ! -e "$DEPLOYED" ]] || exit 1
      /usr/bin/grep -F JOBS_MANAGER_BLOCKED "$TEST_ROOT/signature-error.log" >/dev/null && exit 2
      return 0
    ZSH
  end

  def test_independent_cleanup_in_fresh_worker_does_not_need_an_install_receipt
    shell('jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && jobs_deployment_commit || exit 1')
    set_active(@deployed)
    shell(<<~'ZSH')
      (( ${#JOBS_DEPLOYMENT_COMMITTED_RECEIPT[@]} == 0 )) || exit 1
      jobs_deployment_cleanup_existing_build_products "$BUILT" "$DERIVED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || exit 2
      [[ ! -e "$DERIVED" && -d "$DEPLOYED" ]] || exit 3
      (( ${#JOBS_DEPLOYMENT_COMMITTED_RECEIPT[@]} == 0 )) || exit 4
    ZSH
    host = File.join(@deployed, 'Contents/MacOS/FixtureHost')
    output, error, result = Open3.capture3([host, host])
    assert result.success?, error
    assert_equal 'new', output
  end

  def test_independent_cleanup_missing_or_empty_source_is_noop
    FileUtils.remove_entry(@derived)
    shell('jobs_deployment_cleanup_existing_build_products "$BUILT" "$DERIVED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || exit 1')
    FileUtils.mkdir_p(@derived)
    shell(<<~'ZSH')
      jobs_deployment_cleanup_existing_build_products "$BUILT" "$DERIVED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || exit 1
      [[ -d "$DERIVED" ]] || exit 2
    ZSH
  end

  def test_independent_cleanup_rejects_unsigned_or_unregistered_target_and_bad_scope
    shell('jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && jobs_deployment_commit || exit 1')
    shell(<<~'ZSH')
      jobs_deployment_cleanup_existing_build_products "$BUILT" "$DERIVED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && exit 1
      print -r -- "$DEPLOYED/Contents/PlugIns/$EXTENSION" > "$TEST_ROOT/active.txt"
      jobs_deployment_verify_signature() { return 8; }
      jobs_deployment_cleanup_existing_build_products "$BUILT" "$DERIVED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && exit 2
      jobs_deployment_verify_signature() { return 0; }
      jobs_deployment_cleanup_existing_build_products "$BUILT" "${DERIVED:h}" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && exit 3
      jobs_deployment_source_is_running() { return 0; }
      jobs_deployment_cleanup_existing_build_products "$BUILT" "$DERIVED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && exit 4
      [[ -d "$DERIVED" && -d "$DEPLOYED" ]] || exit 5
    ZSH
  end

  def test_independent_cleanup_after_uninstall_removes_only_unused_build_products
    sibling = File.join(File.dirname(@derived), 'JobsOtherDerivedData')
    FileUtils.mkdir_p(sibling)
    File.write(File.join(sibling, 'keep'), 'other build')
    shell(<<~'ZSH')
      jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && jobs_deployment_commit || exit 1
      jobs_deployment_uninstall "$DEPLOYED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || exit 2
      [[ ! -e "$CONTAINER" && -d "$BUILT" ]] || exit 3
    ZSH
    calls = File.binread(File.join(@root, 'calls'))
    unused_cleanup_shell(<<~'ZSH')
      jobs_deployment_cleanup_existing_build_products "$BUILT" "$DERIVED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || exit 1
      [[ ! -e "$DERIVED" && ! -e "$CONTAINER" ]] || exit 2
      (( ${#JOBS_DEPLOYMENT_COMMITTED_RECEIPT[@]} == 0 )) || exit 3
    ZSH
    assert_equal calls, File.binread(File.join(@root, 'calls')), '清理不得重新登记或卸载 App'
    assert_equal 'other build', File.read(File.join(sibling, 'keep'))
    assert_empty Dir.glob(File.join(File.dirname(@derived), '.JobsFinderCleanup.*'))
  end

  def test_unused_cleanup_preserves_another_installed_module_and_its_registration
    other = File.join(@container, 'Contents/Applications/JobsOther.app')
    make_app(other, 'installed other', app_id: 'com.jobs.other')
    File.write(File.join(@root, 'registered.txt'), File.join(other, 'Contents/PlugIns', EXTENSION) + "\n")
    File.write(File.join(@root, 'host-registered.txt'), other + "\n")
    unused_cleanup_shell(<<~'ZSH')
      jobs_deployment_cleanup_existing_build_products "$BUILT" "$DERIVED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || exit 1
      [[ ! -e "$DERIVED" && -d "$CONTAINER/Contents/Applications/JobsOther.app" && ! -e "$CALLS" ]] || exit 2
    ZSH
    assert_equal 'installed other', File.read(resource(other))
    assert_equal other + "\n", File.read(File.join(@root, 'host-registered.txt'))
  end

  def test_unused_cleanup_preserves_sources_with_extension_or_host_registration
    unused_cleanup_shell(<<~'ZSH')
      print -r -- "$BUILT/Contents/PlugIns/$EXTENSION" > "$TEST_ROOT/registered.txt"
      jobs_deployment_cleanup_existing_build_products "$BUILT" "$DERIVED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && exit 1
      [[ -d "$BUILT" ]] || exit 2
      /bin/rm "$TEST_ROOT/registered.txt"
      print -r -- "$BUILT" > "$TEST_ROOT/host-registered.txt"
      jobs_deployment_cleanup_existing_build_products "$BUILT" "$DERIVED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && exit 3
      [[ -d "$BUILT" && ! -e "$CALLS" ]] || exit 4
    ZSH
    assert_equal 'new', File.read(resource(@built))
  end

  def test_unused_cleanup_preserves_source_when_registration_or_process_queries_fail
    unused_cleanup_shell(<<~'ZSH')
      functions[jobs_registered_fixture]="$functions[jobs_deployment_registered_extension_paths]"
      functions[jobs_hosts_fixture]="$functions[jobs_deployment_dump_host_registrations]"
      jobs_deployment_registered_extension_paths() { return 19; }
      jobs_deployment_cleanup_existing_build_products "$BUILT" "$DERIVED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && exit 1
      functions[jobs_deployment_registered_extension_paths]="$functions[jobs_registered_fixture]"
      jobs_deployment_dump_host_registrations() { return 20; }
      jobs_deployment_cleanup_existing_build_products "$BUILT" "$DERIVED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && exit 2
      jobs_deployment_dump_host_registrations() { print -r -- 'unknown LaunchServices output'; }
      jobs_deployment_cleanup_existing_build_products "$BUILT" "$DERIVED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && exit 3
      functions[jobs_deployment_dump_host_registrations]="$functions[jobs_hosts_fixture]"
      jobs_deployment_source_is_running() { return 2; }
      jobs_deployment_cleanup_existing_build_products "$BUILT" "$DERIVED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && exit 4
      jobs_deployment_source_is_running() { return 0; }
      jobs_deployment_cleanup_existing_build_products "$BUILT" "$DERIVED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && exit 5
      [[ -d "$BUILT" && ! -e "$CALLS" ]] || exit 6
    ZSH
    assert_equal 'new', File.read(resource(@built))
    assert_empty Dir.glob(File.join(File.dirname(@derived), '.JobsFinderCleanup.*'))
  end

  def test_unused_cleanup_restores_source_when_a_process_or_registration_appears_after_move
    unused_cleanup_shell(<<~'ZSH')
      jobs_deployment_source_is_running() { [[ ! -d "$DERIVED" ]]; }
      jobs_deployment_cleanup_existing_build_products "$BUILT" "$DERIVED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && exit 1
      [[ -d "$BUILT" ]] || exit 2
      jobs_deployment_source_is_running() { return 1; }
      jobs_deployment_registered_extension_paths() {
        [[ -d "$DERIVED" ]] || print -r -- "$BUILT/Contents/PlugIns/$EXTENSION"
        return 0
      }
      jobs_deployment_cleanup_existing_build_products "$BUILT" "$DERIVED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && exit 3
      [[ -d "$BUILT" ]] || exit 4
      jobs_deployment_registered_extension_paths() {
        local moved_root=""
        for moved_root in "${DERIVED:h}"/.JobsFinderCleanup.*/DerivedData(N); do
          print -r -- "$moved_root/Build/Products/Debug/JobsFixture.app/Contents/PlugIns/$EXTENSION"
        done
      }
      jobs_deployment_cleanup_existing_build_products "$BUILT" "$DERIVED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && exit 5
      [[ -d "$BUILT" && ! -e "$CALLS" ]] || exit 6
    ZSH
    assert_equal 'new', File.read(resource(@built))
    assert_empty Dir.glob(File.join(File.dirname(@derived), '.JobsFinderCleanup.*'))
  end

  def test_unused_cleanup_rejects_wrong_bundle_identity_and_missing_build_app
    make_app(@built, 'unknown', app_id: 'com.example.unowned')
    unused_cleanup_shell(<<~'ZSH')
      jobs_deployment_cleanup_existing_build_products "$BUILT" "$DERIVED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && exit 1
      [[ -d "$BUILT" ]] || exit 2
    ZSH
    FileUtils.remove_entry(@built)
    unused_cleanup_shell(<<~'ZSH')
      jobs_deployment_cleanup_existing_build_products "$BUILT" "$DERIVED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && exit 1
      [[ -d "$DERIVED" && ! -e "$CALLS" ]] || exit 2
    ZSH
  end

  def test_unused_cleanup_rejects_linked_targets_and_derived_roots
    unused_cleanup_shell(<<~'ZSH')
      /bin/ln -s "$BUILT" "$DEPLOYED" || exit 1
      jobs_deployment_cleanup_existing_build_products "$BUILT" "$DERIVED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && exit 2
      [[ -L "$DEPLOYED" && -d "$BUILT" ]] || exit 3
      /bin/rm "$DEPLOYED"
      parent_dir="${DERIVED:h}"
      /bin/mv "$parent_dir" "$parent_dir.moved"
      /bin/ln -s "$parent_dir.moved" "$parent_dir"
      jobs_deployment_cleanup_existing_build_products "$BUILT" "$DERIVED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && exit 4
      [[ -d "$BUILT" && ! -e "$CALLS" ]] || exit 5
      /bin/rm "$parent_dir"
      /bin/mv "$parent_dir.moved" "$parent_dir"
      /bin/mv "$DERIVED" "$DERIVED.moved"
      /bin/ln -s "$DERIVED.moved" "$DERIVED"
      jobs_deployment_cleanup_existing_build_products "$BUILT" "$DERIVED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && exit 6
      [[ -L "$DERIVED" && -d "$BUILT" ]] || exit 7
    ZSH
  end

  def test_unused_cleanup_preserves_version_metadata_and_rejects_unrelated_scope
    unused_cleanup_shell(<<~'ZSH')
      for protected in .git .hg .svn; do
        /bin/mkdir "$DERIVED/$protected"
        jobs_deployment_cleanup_existing_build_products "$BUILT" "$DERIVED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && exit 1
        [[ -d "$BUILT" && -d "$DERIVED/$protected" ]] || exit 2
        /bin/rmdir "$DERIVED/$protected"
      done
      for rejected in "$TEST_ROOT" "${DERIVED:h}" "$CONTAINER" /; do
        jobs_deployment_cleanup_existing_build_products "$BUILT" "$rejected" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && exit 3
      done
      JOBS_FINDER_INSTALL_LOCATION=build
      jobs_deployment_cleanup_existing_build_products "$BUILT" "$DERIVED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && exit 4
      [[ -d "$BUILT" && ! -e "$CALLS" ]] || exit 5
    ZSH
    assert_equal 'new', File.read(resource(@built))
  end

  def test_open_file_query_distinguishes_idle_open_file_and_working_directory
    directory = File.join(@root, 'lsof 引用目录')
    FileUtils.mkdir_p(directory)
    held_file = File.join(directory, 'held.txt')
    File.write(held_file, 'held')
    shell(<<~'ZSH')
      query_result=0
      jobs_deployment_source_has_open_files "$TEST_ROOT/lsof 引用目录" || query_result=$?
      [[ "$query_result" == 1 ]] || exit 1
    ZSH
    File.open(held_file, 'r') do
      shell('jobs_deployment_source_has_open_files "$TEST_ROOT/lsof 引用目录" || exit 1')
    end
    Open3.popen3('/bin/zsh', '-f', '-c', 'cd -- "$1" || exit 1; print -r READY; IFS= read -r answer', 'held-cwd', directory) do |input, output, error, waiter|
      begin
        assert_equal "READY\n", output.gets
        shell('jobs_deployment_source_has_open_files "$TEST_ROOT/lsof 引用目录" || exit 1')
      ensure
        input.close
        waiter.value
      end
    end
  end

  def test_open_file_query_reports_missing_or_invalid_directory_as_failure
    shell(<<~'ZSH')
      for invalid_root in "$TEST_ROOT/missing" "$BUILT/Contents/Resources/业务.zsh"; do
        query_result=0
        jobs_deployment_source_has_open_files "$invalid_root" || query_result=$?
        [[ "$query_result" == 2 ]] || exit 1
      done
    ZSH
  end

  def test_unused_cleanup_preserves_source_with_open_files_or_failed_query
    unused_cleanup_shell(<<~'ZSH')
      jobs_deployment_source_has_open_files() { return 2; }
      jobs_deployment_cleanup_existing_build_products "$BUILT" "$DERIVED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && exit 1
      jobs_deployment_source_has_open_files() { return 0; }
      jobs_deployment_cleanup_existing_build_products "$BUILT" "$DERIVED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && exit 2
      [[ -d "$BUILT" && ! -e "$CALLS" ]] || exit 3
    ZSH
    assert_equal 'new', File.read(resource(@built))
    assert_empty Dir.glob(File.join(File.dirname(@derived), '.JobsFinderCleanup.*'))
  end

  def test_unused_cleanup_preserves_original_and_replacement_when_source_changes_during_validation
    unused_cleanup_shell(<<~'ZSH')
      jobs_deployment_cleanup_unused_source_ready() {
        /bin/mv -- "$DERIVED" "$DERIVED.original" || return 1
        /bin/mkdir -- "$DERIVED" || return 1
        print -r -- 'concurrent replacement' > "$DERIVED/keep.txt"
      }
      jobs_deployment_cleanup_existing_build_products "$BUILT" "$DERIVED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && exit 1
      [[ -d "$DERIVED.original/Build/Products/Debug/JobsFixture.app" && -f "$DERIVED/keep.txt" && ! -e "$CALLS" ]] || exit 2
    ZSH
    assert_equal 'new', File.read(resource(@built.sub(@derived, @derived + '.original')))
    assert_equal 'concurrent replacement', File.read(File.join(@derived, 'keep.txt')).strip
    assert_empty Dir.glob(File.join(File.dirname(@derived), '.JobsFinderCleanup.*'))
  end

  private

  # 用同一可控时钟验证多单元观察，全部登记系统动作只记入临时文件。
  def registration_shell(body)
    shell(<<~'ZSH' + body)
      REGISTRATION_CLOCK="$TEST_ROOT/registration-clock"
      print 0 > "$REGISTRATION_CLOCK"
      /bin/rm -f -- "$CALLS" "$TEST_ROOT/queries"
      jobs_deployment_registration_now() { print -r -- "$(<"$REGISTRATION_CLOCK")"; }
      jobs_deployment_registration_pause() {
        local tick="$(<"$REGISTRATION_CLOCK")"
        print -r -- "$((tick + 1))" > "$REGISTRATION_CLOCK"
      }
      jobs_deployment_registration_register_host() { print -r -- "register-host:$1" >> "$CALLS"; }
      jobs_deployment_registration_initialize_host() { print -r -- "initialize-host:$1|$3" >> "$CALLS"; }
      jobs_deployment_registration_add_extension() { print -r -- "add-extension:$1/Contents/PlugIns/$2" >> "$CALLS"; }
      jobs_deployment_registration_enable_extension() {
        print -r -- "enable:$3" >> "$CALLS"
        : > "$TEST_ROOT/repaired-$3"
      }
    ZSH
  end

  # 提供可控的有效 LS 记录，避免查询或改写真实系统登记。
  def unused_cleanup_shell(body)
    shell(<<~'ZSH' + body)
      jobs_deployment_source_has_open_files() { return 1; }
      jobs_deployment_dump_host_registrations() {
        local candidate=""
        printf '%s\n' 'bundle id: unrelated (0x1)' 'path: /Applications/JobsUnrelated.app (0x1)' '----------------------------------------'
        if [[ -f "$TEST_ROOT/host-registered.txt" ]]; then
          while IFS= read -r candidate; do
            printf '%s\n' 'bundle id: fixture (0x2)' "path: $candidate (0x2)" '----------------------------------------'
          done < "$TEST_ROOT/host-registered.txt"
        fi
      }
    ZSH
  end

  public

  def test_ordered_desktop_manifest_uses_fixed_owner_and_runs_before_outer_signing
    %w[JobsDiskSpaceInfo JobsEnvironmentUpdater JobsDesktopTools JobsFileCreator].each { |name| make_ordered_provider(name) }
    shell(<<~'ZSH')
      jobs_deployment_codesign_container() {
        [[ -f "$1/Contents/Resources/DesktopMenu.json" ]] || return 93
        print -r -- signed >> "$CALLS"
      }
      jobs_deployment_sign_container_original "$CONTAINER" || exit 1
    ZSH
    manifest = JSON.parse(File.read(File.join(@container, 'Contents/Resources/DesktopMenu.json')))
    assert_equal({ 'schemaVersion' => 1, 'owner' => 'JobsFileCreator',
                   'providers' => %w[JobsFileCreator JobsDesktopTools JobsEnvironmentUpdater JobsDiskSpaceInfo] }, manifest)
    assert_equal "signed\n", File.read(File.join(@root, 'calls'))
  end

  def test_ordered_desktop_manifest_reelects_after_removal_and_excludes_legacy_hosts
    make_ordered_provider('JobsFileCreator')
    make_ordered_provider('JobsDiskSpaceInfo')
    make_ordered_provider('JobsDesktopTools', protocol: nil)
    shell('jobs_deployment_refresh_desktop_menu "$CONTAINER" || exit 1')
    manifest = File.join(@container, 'Contents/Resources/DesktopMenu.json')
    assert_equal %w[JobsFileCreator JobsDiskSpaceInfo], JSON.parse(File.read(manifest)).fetch('providers')
    FileUtils.remove_entry(File.join(@container, 'Contents/Applications/JobsFileCreator.app'))
    shell('jobs_deployment_refresh_desktop_menu "$CONTAINER" || exit 1')
    assert_equal 'JobsDiskSpaceInfo', JSON.parse(File.read(manifest)).fetch('owner')
    FileUtils.remove_entry(File.join(@container, 'Contents/Applications/JobsDiskSpaceInfo.app'))
    shell('jobs_deployment_refresh_desktop_menu "$CONTAINER" || exit 1')
    refute File.exist?(manifest)
    assert File.directory?(File.join(@container, 'Contents/Applications/JobsDesktopTools.app'))
  end

  def test_ordered_desktop_manifest_rejects_links_and_bad_provider_identity_without_replacing_manifest
    make_ordered_provider('JobsDiskSpaceInfo')
    shell('jobs_deployment_refresh_desktop_menu "$CONTAINER" || exit 1')
    manifest = File.join(@container, 'Contents/Resources/DesktopMenu.json')
    original = File.binread(manifest)
    make_ordered_provider('JobsFileCreator', identifier: 'com.other.unowned')
    shell('jobs_deployment_refresh_desktop_menu "$CONTAINER"; [[ $? == 1 ]] || exit 1')
    assert_equal original, File.binread(manifest)
    FileUtils.remove_entry(File.join(@container, 'Contents/Applications/JobsFileCreator.app'))
    File.unlink(manifest)
    victim = File.join(@root, 'do-not-touch.json')
    File.write(victim, 'keep')
    File.symlink(victim, manifest)
    shell('jobs_deployment_refresh_desktop_menu "$CONTAINER"; [[ $? == 1 ]] || exit 1')
    assert_equal 'keep', File.read(victim)
    assert File.symlink?(manifest)
  end

  def test_ordered_desktop_manifest_follows_install_rollback_commit_and_uninstall
    make_ordered_provider('JobsDiskSpaceInfo')
    make_ordered_provider('JobsFileCreator')
    FileUtils.mkdir_p(File.join(@root, 'NewBuild'))
    FileUtils.mv(File.join(@container, 'Contents/Applications/JobsFileCreator.app'), File.join(@root, 'NewBuild/JobsFileCreator.app'))
    shell(<<~'ZSH')
      functions[jobs_deployment_sign_container]="$functions[jobs_deployment_sign_container_original]"
      jobs_deployment_codesign_container() { return 0; }
      CREATOR="$TEST_ROOT/NewBuild/JobsFileCreator.app"
      MANIFEST="$CONTAINER/Contents/Resources/DesktopMenu.json"
      jobs_deployment_refresh_desktop_menu "$CONTAINER" || exit 1
      original="$(/bin/cat "$MANIFEST")"
      jobs_deployment_install "$CREATOR" com.jobs.filecreator JobsFileCreatorFinderSync.appex com.jobs.filecreator.findersync || exit 2
      [[ "$(/usr/bin/plutil -extract owner raw -o - "$MANIFEST")" == JobsFileCreator ]] || exit 3
      jobs_deployment_rollback || exit 4
      [[ "$(/bin/cat "$MANIFEST")" == "$original" ]] || exit 5
      jobs_deployment_install "$CREATOR" com.jobs.filecreator JobsFileCreatorFinderSync.appex com.jobs.filecreator.findersync || exit 6
      jobs_deployment_commit || exit 7
      jobs_deployment_uninstall "$CONTAINER/Contents/Applications/JobsFileCreator.app" com.jobs.filecreator JobsFileCreatorFinderSync.appex com.jobs.filecreator.findersync || exit 8
      [[ "$(/bin/cat "$MANIFEST")" == "$original" ]] || exit 9
    ZSH
    refute File.exist?(File.join(@container, 'Contents/Applications/JobsFileCreator.app'))
    assert File.directory?(File.join(@container, 'Contents/Applications/JobsDiskSpaceInfo.app'))
  end

  def test_rollback_restores_outer_signature_before_previous_registration
    make_app(@deployed, 'old')
    set_active(@deployed)
    shell(<<~'ZSH')
      jobs_deployment_sign_container() { print -r -- restored-signature >> "$CALLS"; }
      jobs_deployment_register_restored_app() {
        [[ "$(/usr/bin/tail -n 1 "$CALLS")" == restored-signature ]] || return 94
        print -r -- "register:$1" >> "$CALLS"
      }
      jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || exit 1
      : > "$CALLS"
      jobs_deployment_rollback || exit 2
      [[ "$(/usr/bin/tail -n 1 "$CALLS")" == "register:$DEPLOYED" ]] || exit 3
    ZSH
    assert_equal 'old', File.read(resource(@deployed))
  end

  private

  def make_ordered_provider(name, protocol: 1, identifier: nil)
    make_container unless File.directory?(@container)
    identifier ||= { 'JobsFileCreator' => 'com.jobs.filecreator', 'JobsDesktopTools' => 'com.jobs.desktoptools',
                     'JobsEnvironmentUpdater' => 'com.jobs.environmentupdater', 'JobsDiskSpaceInfo' => 'com.jobs.diskspaceinfo' }.fetch(name)
    app = File.join(@container, 'Contents/Applications', "#{name}.app")
    [[app, identifier, name], [File.join(app, 'Contents/PlugIns', "#{name}FinderSync.appex"), "#{identifier}.findersync", "#{name}FinderSync"]].each do |bundle, bundle_id, executable|
      FileUtils.mkdir_p(File.join(bundle, 'Contents/MacOS'))
      marker = protocol && "<key>JobsOrderedDesktopMenuVersion</key><integer>#{protocol}</integer>"
      File.write(File.join(bundle, 'Contents/Info.plist'), "<plist version=\"1.0\"><dict><key>CFBundleIdentifier</key><string>#{bundle_id}</string><key>CFBundleExecutable</key><string>#{executable}</string>#{marker}</dict></plist>")
      program = File.join(bundle, 'Contents/MacOS', executable)
      File.write(program, "#!/bin/sh\nexit 0\n")
      File.chmod(0o755, program)
    end
  end

  def make_container
    FileUtils.mkdir_p(File.join(@container, 'Contents/Applications'))
    FileUtils.mkdir_p(File.join(@container, 'Contents/MacOS'))
    File.write(File.join(@container, 'Contents/Info.plist'), '<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.jobs.finderextensions.manager</string><key>CFBundleExecutable</key><string>JobsFinderExtensions</string><key>CFBundleName</key><string>Jobs自定义右键菜单</string></dict></plist>')
    executable = File.join(@container, 'Contents/MacOS/JobsFinderExtensions')
    File.write(executable, "#!/bin/zsh\nexit 0\n")
    File.chmod(0o755, executable)
  end

  def resource(app)
    File.join(app, 'Contents/Resources/业务.zsh')
  end

  def make_app(app, content, app_id: APP_ID, extension_id: EXTENSION_ID)
    [[app, app_id, 'FixtureHost'], [File.join(app, 'Contents/PlugIns', EXTENSION), extension_id, 'FixtureExtension']].each do |bundle, identifier, executable|
      FileUtils.mkdir_p(File.join(bundle, 'Contents/MacOS'))
      File.write(File.join(bundle, 'Contents/Info.plist'), <<~XML)
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict><key>CFBundleIdentifier</key><string>#{identifier}</string><key>CFBundleExecutable</key><string>#{executable}</string><key>CFBundlePackageType</key><string>#{executable == 'FixtureHost' ? 'APPL' : 'XPC!'}</string><key>CFBundleVersion</key><string>1</string></dict></plist>
      XML
      program = File.join(bundle, 'Contents/MacOS', executable)
      body = if executable == 'FixtureHost'
               <<~'SH'
                 #!/bin/sh
                 resource_dir=$(CDPATH= cd "$(dirname "$0")/../Resources" && pwd) || exit 1
                 exec /bin/cat "$resource_dir/业务.zsh"
               SH
             else
               "#!/bin/sh\nexit 0\n"
             end
      File.write(program, body)
      File.chmod(0o755, program)
    end
    FileUtils.mkdir_p(File.dirname(resource(app)))
    File.write(resource(app), content)
  end

  def set_active(app)
    File.write(File.join(@root, 'active.txt'), File.join(app, 'Contents/PlugIns', EXTENSION) + "\n")
  end

  def shell(body)
    script = <<~'ZSH'
      source "$1" || exit 90
      TEST_ROOT="$2"
      BUILT="$3"
      DEPLOYED="$4"
      CALLS="$TEST_ROOT/calls"
      DERIVED="${BUILT%/Build/Products/Debug/JobsFixture.app}"
      CONTAINER="${DEPLOYED%/Contents/Applications/JobsFixture.app}"
      APP_ID=com.jobs.fixture
      EXTENSION=JobsFixtureFinder.appex
      EXTENSION_ID=com.jobs.fixture.findersync
      functions[jobs_deployment_enabled_extension_paths_original]="$functions[jobs_deployment_enabled_extension_paths]"
      functions[jobs_deployment_verify_signature_original]="$functions[jobs_deployment_verify_signature]"
      functions[jobs_deployment_sign_container_original]="$functions[jobs_deployment_sign_container]"
      functions[jobs_deployment_unregister_app_original]="$functions[jobs_deployment_unregister_app]"
      jobs_deployment_verify_signature() { return 0; }
      jobs_deployment_sign_container() { return 0; }
      jobs_prepare_combined_manager_resources() { return 0; }
      jobs_deployment_enabled_extension_paths() { [[ ! -f "$TEST_ROOT/active.txt" ]] || /bin/cat "$TEST_ROOT/active.txt"; return 0; }
      jobs_deployment_registered_extension_paths() { if [[ -f "$TEST_ROOT/registered.txt" ]]; then /bin/cat "$TEST_ROOT/registered.txt"; else jobs_deployment_enabled_extension_paths "$1"; fi; }
      jobs_deployment_source_is_running() { return 1; }
      jobs_deployment_unregister_app() { print -r -- "unregister:$1" >> "$CALLS"; }
      jobs_deployment_unregister_host_command() { print -u2 -r -- 'Unexpected real host unregister call'; return 98; }
      jobs_deployment_dump_host_registrations() { print -u2 -r -- 'Unexpected real host query'; return 98; }
      jobs_deployment_register_restored_app() { print -r -- "register:$1" >> "$CALLS"; }
    ZSH
    output, error, result = Open3.capture3(
      { 'JOBS_FINDER_INSTALL_LOCATION' => 'applications', 'JOBS_FINDER_APPLICATIONS_DIR' => @applications },
      '/bin/zsh', '-f', '-c', script + body, 'AppDeploymentTests', LIBRARY, @root, @built, @deployed
    )
    assert result.success?, "exit=#{result.exitstatus}\nstdout=#{output}\nstderr=#{error}\n#{body}"
  end
end
