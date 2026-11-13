# frozen_string_literal: true
# 总管理器的双安装位置回归；仅使用临时目录和登记替身，不执行安装、注销或刷新 Finder。
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
require_relative '../IsolatedInstallerDefinitions'

class ApplicationsLocationIntegrationTests < Minitest::Test
  include IsolatedInstallerDefinitions
  ROOT = File.expand_path('../..', __dir__)
  MANAGER = File.join(ROOT, 'Scripts/ManageFinderExtensions.zsh')

  def run_fixture(checks, *arguments)
    source = isolated_installer_source(MANAGER)
    Dir.mktmpdir('jobs-location-integration-') do |directory|
      fixture = File.join(directory, 'manager.zsh')
      File.write(fixture, source + "\nLOG_FILE=/dev/null\n" + checks)
      Open3.capture3(isolated_installer_environment(directory), '/bin/zsh', '-f', fixture, *arguments)
    end
  end

  def test_location_defaults_to_build_and_rejects_unknown_or_missing_values
    output, errors, result = run_fixture(<<~'ZSH')
      parse_management_options --action install --features file-create --non-interactive || exit $?
      print -r -- "DEFAULT=$JOBS_FINDER_INSTALL_LOCATION"
      parse_management_options --action uninstall --features file-create --non-interactive --install-location applications || exit $?
      print -r -- "APPS=$JOBS_FINDER_INSTALL_LOCATION"
    ZSH
    assert result.success?, errors
    assert_equal "DEFAULT=build\nAPPS=applications\n", output
    [%w[--install-location elsewhere], ['--install-location']].each do |options|
      _, _, failed = run_fixture('parse_management_options --action install --features file-create --non-interactive "$@"', *options)
      assert_equal 2, failed.exitstatus
    end
  end

  def test_build_output_and_selected_registration_path_remain_distinct
    Dir.mktmpdir('中文 Apps ') do |directory|
      output, errors, result = run_fixture(<<~'ZSH', directory)
        WORKSPACE_DIR="$1/source"
        export JOBS_FINDER_APPLICATIONS_DIR="$1/Applications"
        print -r -- "BUILD=$(built_app_path_for_key file-create)"
        print -r -- "DEFAULT=$(app_path_for_key file-create)"
        JOBS_FINDER_INSTALL_LOCATION=applications
        print -r -- "TARGET=$(app_path_for_key file-create)"
        print -r -- "EXT=$(extension_path_for_key file-create)"
        print -r -- "SOURCE=$(built_app_path_for_key file-create)"
      ZSH
      assert result.success?, errors
      built = File.join(directory, 'source/work/JobsFileCreatorDerivedData/Build/Products/Debug/JobsFileCreator.app')
      target = File.join(directory, 'Applications/Jobs自定义右键菜单.app/Contents/Applications/JobsFileCreator.app')
      assert_equal ["BUILD=#{built}", "DEFAULT=#{built}", "TARGET=#{target}",
                    "EXT=#{target}/Contents/PlugIns/JobsFileCreatorFinderSync.appex", "SOURCE=#{built}"], output.lines.map(&:chomp)
    end
  end

  def test_applications_deployment_commits_only_after_registration_and_rolls_back_failure
    [0, 41].each do |registration_result|
      output, errors, result = run_fixture(<<~'ZSH', registration_result.to_s)
        JOBS_FINDER_INSTALL_LOCATION=applications
        parse_feature_selection file-create || exit 1
        build_feature() { print 'BUILD'; }
        jobs_deployment_install() { print -r -- "COPY=${(j:|:)@}"; }
        jobs_deployment_commit() { print 'COMMIT'; }
        jobs_deployment_rollback() { print 'ROLLBACK'; }
        register_and_enable_feature() { print 'REGISTER'; return "$JOBS_TEST_REGISTRATION_RESULT"; }
        JOBS_TEST_REGISTRATION_RESULT="$1"
        install_feature file-create
      ZSH
      if registration_result.zero?
        assert result.success?, errors
        assert_includes output, 'COMMIT'
        refute_includes output, 'ROLLBACK'
      else
        refute result.success?, errors
        assert_includes output, 'ROLLBACK'
        refute_includes output, 'COMMIT'
      end
      assert_match(/COPY=.*JobsFileCreator\.app\|com\.jobs\.filecreator\|JobsFileCreatorFinderSync\.appex\|com\.jobs\.filecreator\.findersync/, output)
      assert_operator output.index('BUILD'), :<, output.index('COPY=')
      assert_operator output.index('COPY='), :<, output.index('REGISTER')
    end
  end

  def test_uninstall_of_missing_selected_location_preserves_shared_configuration
    Dir.mktmpdir('jobs-location-missing-') do |directory|
      config = File.join(directory, 'flutter.conf')
      File.write(config, 'run,codegen')
      %w[build applications].each do |location|
        output, errors, result = run_fixture(<<~'ZSH', directory, config, location)
          WORKSPACE_DIR="$1/source"
          JOBS_FINDER_APPLICATIONS_DIR="$1/Applications"
          FLUTTER_FEATURE_CONFIG_PATH="$2"
          JOBS_FINDER_INSTALL_LOCATION="$3"
          parse_feature_selection flutter-codegen || exit 1
          run_independent_uninstall() { print unexpected-uninstall; return 99; }
          outcome_result=0
          uninstall_feature flutter-tools || outcome_result=$?
          [[ "$outcome_result" == 3 && "$UNINSTALL_OUTCOME" == not-installed ]] || exit 1
        ZSH
        assert result.success?, errors
        refute_includes output, 'unexpected-uninstall'
        assert_equal 'run,codegen', File.read(config)
      end
    end
  end

  def test_foreign_app_is_rejected_before_shared_configuration_is_changed
    Dir.mktmpdir('jobs-location-identity-') do |directory|
      app = File.join(directory, 'Jobs自定义右键菜单.app/Contents/Applications/JobsFlutterTools.app')
      FileUtils.mkdir_p(File.join(app, 'Contents'))
      File.write(File.join(app, 'Contents/Info.plist'), <<~XML)
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict><key>CFBundleIdentifier</key><string>org.foreign.app</string></dict></plist>
      XML
      output, errors, result = run_fixture(<<~'ZSH', directory)
        load_deployment_support() { return 0; }
        jobs_deployment_app_path() { print -r -- "$JOBS_FINDER_APPLICATIONS_DIR/Jobs自定义右键菜单.app/Contents/Applications/JobsFlutterTools.app"; }
        jobs_deployment_validate_app() {
          [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$1/Contents/Info.plist")" == "$2" ]]
        }
        JOBS_FINDER_APPLICATIONS_DIR="$1"
        JOBS_FINDER_INSTALL_LOCATION=applications
        parse_feature_selection flutter-codegen || exit 1
        write_group_configuration() { print unexpected-config-write; }
        run_independent_uninstall() { print unexpected-uninstall; }
        uninstall_feature flutter-tools
      ZSH
      assert_equal 2, result.exitstatus, errors
      refute_includes output, 'unexpected-config-write'
      refute_includes output, 'unexpected-uninstall'
      assert File.exist?(File.join(app, 'Contents/Info.plist'))
    end
  end

  def test_failed_registration_restores_original_ios_configuration_bytes
    Dir.mktmpdir('jobs-location-config-') do |directory|
      config = File.join(directory, 'ios.conf')
      original = "ios-code-snippets\n"
      File.write(config, original)
      output, errors, result = run_fixture(<<~'ZSH', config)
        IOS_FEATURE_CONFIG_PATH="$1"
        IOS_FEATURE_CONFIG_DIR="${1:h}"
        JOBS_FINDER_INSTALL_LOCATION=applications
        parse_feature_selection ios-pod-update || exit 1
        build_feature() { return 0; }
        jobs_deployment_install() { return 0; }
        jobs_deployment_rollback() { print ROLLBACK; }
        register_and_enable_feature() { return 41; }
        install_feature ios-tools
      ZSH
      refute result.success?, errors
      assert_includes output, 'ROLLBACK'
      assert_equal original, File.read(config)
    end
  end

  def test_configuration_failure_after_flutter_publication_restores_old_choices
    [false, true].each do |concurrent_change|
      Dir.mktmpdir('jobs-location-config-publication-') do |directory|
        config = File.join(directory, 'flutter.conf')
        File.write(config, "run\n")
        output, errors, result = run_fixture(<<~'ZSH', config, concurrent_change ? '1' : '0')
          FLUTTER_FEATURE_CONFIG_PATH="$1"
          FLUTTER_FEATURE_CONFIG_DIR="${1:h}"
          JOBS_FINDER_INSTALL_LOCATION=applications
          parse_feature_selection flutter-codegen || exit 1
          JOBS_TEST_CONCURRENT_CHANGE="$2"
          build_feature() { return 0; }
          jobs_deployment_install() { return 0; }
          jobs_deployment_rollback() { print ROLLBACK; }
          register_and_enable_feature() { return 0; }
          persist_terminal_feature_selection() {
            if [[ "$JOBS_TEST_CONCURRENT_CHANGE" == 1 ]]; then
              print -r -- externally-changed > "$FLUTTER_FEATURE_CONFIG_PATH"
            fi
            return 41
          }
          install_feature flutter-tools
        ZSH
        refute result.success?, errors
        assert_includes output, 'ROLLBACK'
        assert_equal concurrent_change ? "externally-changed\n" : "run\n", File.read(config)
      end
    end
  end

  def test_inactive_copy_uninstall_bypasses_active_copys_shared_configuration
    Dir.mktmpdir('jobs-location-active-') do |directory|
      config = File.join(directory, 'flutter.conf')
      File.write(config, 'run,codegen')
      output, errors, result = run_fixture(<<~'ZSH', config)
        FLUTTER_FEATURE_CONFIG_PATH="$1"
        parse_feature_selection flutter-codegen || exit 1
        selected_location_has_app() { return 0; }
        another_location_is_active() { return 0; }
        run_independent_uninstall() { print 'REMOVE_INACTIVE_COPY'; }
        uninstall_feature flutter-tools
      ZSH
      assert result.success?, errors
      assert_includes output, 'REMOVE_INACTIVE_COPY'
      assert_equal 'run,codegen', File.read(config)
    end
  end

  def test_cleanup_flag_is_only_valid_for_applications_install_before_any_work
    [%w[install applications], %w[install build], %w[uninstall applications], %w[uninstall build]].each do |action, location|
      output, errors, result = run_fixture(<<~'ZSH', action, location)
        parse_management_options --action "$1" --install-location "$2" --cleanup-build-products --features file-create --non-interactive || exit $?
        print -r -- "ACCEPTED=$JOBS_FINDER_CLEANUP_BUILD_PRODUCTS"
      ZSH
      if action == 'install' && location == 'applications'
        assert result.success?, errors
        assert_includes output, 'ACCEPTED=1'
      else
        assert_equal 2, result.exitstatus
        refute_includes output, 'ACCEPTED='
      end
    end
  end

  def test_cleanup_is_after_commit_and_never_after_registration_failure
    [0, 41].each do |registration_result|
      output, errors, result = run_fixture(<<~'ZSH', registration_result.to_s)
        JOBS_FINDER_INSTALL_LOCATION=applications
        JOBS_FINDER_CLEANUP_BUILD_PRODUCTS=1
        JOBS_TEST_REGISTRATION_RESULT="$1"
        parse_feature_selection file-create || exit 1
        build_feature() { print BUILD; }
        jobs_deployment_install() { print DEPLOY; }
        jobs_deployment_commit() { print COMMIT; }
        jobs_deployment_rollback() { print ROLLBACK; }
        register_and_enable_feature() { print REGISTER; return "$JOBS_TEST_REGISTRATION_RESULT"; }
        jobs_deployment_cleanup_build_products() { print -r -- "CLEAN=${(j:|:)@}"; return 71; }
        install_feature file-create
      ZSH
      if registration_result.zero?
        assert result.success?, errors
        assert_match(/CLEAN=.*JobsFileCreator\.app\|.*JobsFileCreatorDerivedData\|com\.jobs\.filecreator\|JobsFileCreatorFinderSync\.appex\|com\.jobs\.filecreator\.findersync/, output)
        assert_operator output.index('COMMIT'), :<, output.index('CLEAN=')
        assert_includes output, '清理失败'
        refute_includes output, 'ROLLBACK'
      else
        refute result.success?, errors
        refute_includes output, 'CLEAN='
        assert_includes output, 'ROLLBACK'
      end
    end
  end

  def test_independent_cleanup_is_apps_only_and_reuses_each_units_exact_build_root
    output, errors, result = run_fixture(<<~'ZSH', ROOT)
      WORKSPACE_DIR="$1"
      parse_management_options --action cleanup --install-location applications --features git-pull,git-rollback,file-create --non-interactive || exit $?
      parse_feature_selection "$CLI_FEATURES" || exit 1
      jobs_deployment_cleanup_existing_build_products() { print -r -- "CLEAN=${(j:|:)@}"; }
      install_feature() { print unexpected-install; return 99; }
      cleanup_selected_features
    ZSH
    assert result.success?, errors
    calls = output.lines.grep(/^CLEAN=/)
    assert_equal 2, calls.length
    assert_includes calls[0], '/JobsProjectTools/work/DerivedData/Build/Products/Debug/JobsProjectTools.app|'
    assert_includes calls[1], '/work/JobsFileCreatorDerivedData/Build/Products/Debug/JobsFileCreator.app|'
    refute_includes output, 'unexpected-install'
    _, _, rejected = run_fixture('parse_management_options --action cleanup --install-location build --features file-create --non-interactive')
    assert_equal 2, rejected.exitstatus
  end

  def test_stop_waits_until_current_install_unit_finishes_then_skips_remaining_units
    Dir.mktmpdir('jobs-cooperative-stop-') do |directory|
      output, errors, result = run_fixture(<<~'ZSH', File.join(directory, 'stop-request'))
        parse_management_options --action install --features file-create,path_copier,run-authorize --stop-request-file "$1" --non-interactive || exit $?
        parse_feature_selection "$CLI_FEATURES" || exit 1
        ensure_feature_projects_exist() { return 0; }
        install_feature() {
          print -r -- "INSTALL_START=$1"
          : > "$JOBS_FINDER_STOP_REQUEST_FILE"
          print -r -- "INSTALL_FINISHED=$1"
        }
        install_selected_features
        print -r -- "EXIT=$FINAL_EXIT_STATUS"
      ZSH
      assert result.success?, errors
      assert_equal ['INSTALL_START=file-create', 'INSTALL_FINISHED=file-create'], output.lines.map(&:chomp).grep(/^INSTALL_/)
      assert_includes output, "JOBS_MANAGER_EVENT\tfile-create\tsucceeded"
      assert_includes output, "JOBS_MANAGER_EVENT\tpath_copier\tskipped"
      assert_includes output, "JOBS_MANAGER_EVENT\trun-authorize\tskipped"
      assert_includes output, 'JOBS_MANAGER_STOPPED'
      assert_includes output, 'EXIT=0'
      refute_match(/\tfailed\t/, output)
    end
  end

  def test_app_management_block_from_child_stops_next_build_and_preserves_exit_77
    Dir.mktmpdir('jobs-auth-blocked-') do |directory|
      output, errors, result = run_fixture(<<~'ZSH', File.join(directory, 'app-management.blocked'))
        JOBS_FINDER_BLOCKED_FILE="$1"
        parse_feature_selection file-create,path_copier,run-authorize || exit 1
        ensure_feature_projects_exist() { return 0; }
        install_feature() { print -r -- "INSTALL=$1"; print app-management > "$JOBS_FINDER_BLOCKED_FILE"; return 1; }
        install_selected_features
        print -r -- "EXIT=$FINAL_EXIT_STATUS"
      ZSH
      assert result.success?, errors
      assert_equal ['INSTALL=file-create'], output.lines.map(&:chomp).grep(/^INSTALL=/)
      assert_includes output, "JOBS_MANAGER_BLOCKED\tapp-management\t77"
      assert_includes output, "JOBS_MANAGER_EVENT\tfile-create\tfailed"
      assert_includes output, "JOBS_MANAGER_EVENT\tpath_copier\tskipped"
      assert_includes output, 'EXIT=77'
      refute_includes output, 'JOBS_MANAGER_STOPPED'
    end
  end

  def test_private_block_flag_survives_real_child_process_even_if_its_status_is_wrapped
    library = File.join(ROOT, 'Scripts/【MacOS】AppDeployment.zsh/【MacOS】AppDeployment.zsh')
    output, errors, result = run_fixture(<<~'ZSH', library)
      init_runtime
      MODULE_FIXTURE="$1"
      export JOBS_FINDER_RESPONSIBLE_APP=/fixture/JobsManager.app
      parse_feature_selection file-create,path_copier || exit 1
      ensure_feature_projects_exist() { return 0; }
      install_feature() {
        print -r -- "INSTALL=$1"
        /bin/zsh -f -c 'source "$1"; jobs_deployment_error "Operation not permitted: /Applications/Jobs自定义右键菜单.app/Contents/_CodeSignature"' fixture "$MODULE_FIXTURE" || return 1
      }
      install_selected_features
      [[ -s "$JOBS_FINDER_BLOCKED_FILE" ]] || exit 91
      print -r -- "EXIT=$FINAL_EXIT_STATUS"
    ZSH
    assert result.success?, errors
    assert_equal ['INSTALL=file-create'], output.lines.map(&:chomp).grep(/^INSTALL=/)
    assert_includes output, 'EXIT=77'
    assert_includes output, "JOBS_MANAGER_EVENT\tpath_copier\tskipped"
    assert_includes errors, "JOBS_MANAGER_BLOCKED\tapp-management\t77"
  end
end
