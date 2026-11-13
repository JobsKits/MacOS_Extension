# frozen_string_literal: true
# Created by Jobs on 2026年10月28日，星期三。
# 临时工程验证组件计划、本机配置合并与节点事件，不运行下载、安装或许可证命令。
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

require 'fileutils'
require 'minitest/autorun'
require 'open3'
require 'tmpdir'

class AndroidSetupPlatformTests < Minitest::Test
  TOOLS = File.expand_path('../Scripts/Tools', __dir__)

  def setup
    @root = File.realpath(Dir.mktmpdir('jobs-android-setup-'))
    @project = File.join(@root, "项目 空格 ' $literal")
    @sdk = File.join(@root, 'Flutter SDK')
    @run = File.join(@root, 'run')
    FileUtils.mkdir_p([File.join(@project, 'android/app'), File.join(@sdk, 'bin'), @run])
    @build = File.join(@project, 'android/app/build.gradle.kts')
    File.write(@build, "android { compileSdk = 36\n buildToolsVersion = \"36.0.0\"\n ndkVersion = \"28.2.13676358\"\n externalNativeBuild { cmake { version = \"3.22.1\" } } }\n")
    @env = { 'AP_TEST_PROJECT' => @project, 'AP_TEST_SDK' => @sdk, 'AP_TEST_RUN' => @run,
             'AP_TEST_TOOLS' => TOOLS, 'AP_TEST_TRACE' => File.join(@root, 'trace') }
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def run_zsh(body)
    prefix = <<~'SH'
      source "$AP_TEST_TOOLS/SetupFlutterPlatform.zsh"
      AP_PROJECT="$AP_TEST_PROJECT" AP_FLUTTER="$AP_TEST_SDK/bin/flutter"
      PE_RUN_DIR="$AP_TEST_RUN"
      pe_log() { print -r -- "$*" >&2; }
      pe_event() { printf '%s\n' "$*" >> "$AP_TEST_TRACE"; }
      sf_file_stamp() { [[ -e "$1" ]] || { print absent; return; }; /usr/bin/stat -f '%d:%i:%m:%z' "$1"; /usr/bin/shasum -a 256 "$1"; }
    SH
    Open3.capture3(@env, '/bin/zsh', '-c', prefix + body)
  end

  def test_explicit_components_are_read_without_running_project
    out, err, status = run_zsh('ap_read_requirements && printf "%s\n" "$AP_API" "$AP_BUILD" "$AP_NDK" "$AP_CMAKE"')
    assert status.success?, err
    assert_equal %w[36 36.0.0 28.2.13676358 3.22.1], out.lines.map(&:strip)
  end

  def test_flutter_extension_kotlin_typed_defaults
    File.write(@build, "android { compileSdk = flutter.compileSdkVersion\n ndkVersion = flutter.ndkVersion }\n")
    directory = File.join(@sdk, 'packages/flutter_tools/gradle/src/main/kotlin')
    FileUtils.mkdir_p(directory)
    File.write(File.join(directory, 'FlutterExtension.kt'), 'val compileSdkVersion: Int = 36; val ndkVersion: String = "28.2.13676358"')
    out, err, status = run_zsh('ap_read_requirements && printf "%s\n" "$AP_API" "$AP_NDK"')
    assert status.success?, err
    assert_equal %w[36 28.2.13676358], out.lines.map(&:strip)
  end

  def test_unresolved_flutter_ndk_stops_instead_of_installing_guess
    File.write(@build, 'ndkVersion = flutter.ndkVersion')
    _, err, status = run_zsh('ap_read_requirements')
    refute status.success?
    assert_includes err, '无法解析'
  end

  def test_comments_do_not_override_active_versions
    File.write(@build, "// compileSdk = 99\n/* ndkVersion = \"99.9.999\" */\ncompileSdkVersion 35\n")
    out, err, status = run_zsh('ap_read_requirements && print -r -- "$AP_API|$AP_NDK"')
    assert status.success?, err
    assert_equal '35|', out.strip
  end

  def test_dynamic_native_versions_remain_pending_selection
    File.write(@build, 'android { compileSdk = rootProject.ext.api; ndkVersion = versions.ndk; externalNativeBuild { cmake { version = versions.cmake } } }')
    out, err, status = run_zsh('ap_read_requirements && print -r -- "$AP_DYNAMIC_NDK|$AP_DYNAMIC_CMAKE"')
    assert status.success?, err
    assert_equal '1|1', out.strip
  end

  def test_component_version_metadata_is_read_as_data
    properties = File.join(@run, 'source.properties')
    File.write(properties, "Pkg.Revision=36.0.0\nAndroidVersion.ApiLevel=36\n")
    out, err, status = run_zsh('ap_package_value "$PE_RUN_DIR/source.properties" Pkg.Revision')
    assert status.success?, err
    assert_equal '36.0.0', out
  end

  def test_sdk_property_merge_preserves_other_keys_and_backups
    config = File.join(@project, 'android/local.properties')
    original = "sdk.dir=/old\nflutter.sdk=/existing\ncustom=value\n"
    File.write(config, original)
    sdk = File.join(@root, 'Android SDK')
    FileUtils.mkdir_p(sdk)
    out, err, status = run_zsh('ANDROID_SIM_SDK="${AP_TEST_SDK:h}/Android SDK"; ap_write_sdk_config')
    assert status.success?, out + err
    text = File.read(config)
    assert_includes text, 'flutter.sdk=/existing'
    assert_includes text, 'custom=value'
    assert_includes text, 'Android\ SDK'
    assert_equal original, File.read(File.join(@run, 'before/android-local.properties'))
    assert_includes File.read(@env['AP_TEST_TRACE']), 'platforms.android.config platforms.android 项目SDK路径 succeeded'
  end

  def test_symbolic_local_config_is_preserved
    external = File.join(@root, 'external')
    File.write(external, 'keep')
    File.symlink(external, File.join(@project, 'android/local.properties'))
    _, _, status = run_zsh('ap_check_project')
    refute status.success?
    assert_equal 'keep', File.read(external)
  end

  def test_health_checks_skip_already_installed_components
    sdk = File.join(@root, 'Android SDK')
    %w[platform-tools/adb build-tools/36.0.0/aapt2 cmake/3.22.1/bin/cmake].each do |entry|
      target = File.join(sdk, entry)
      FileUtils.mkdir_p(File.dirname(target)); File.write(target, 'fixture'); FileUtils.chmod(0o755, target)
    end
    %w[platforms/android-36/android.jar ndk/28.2.13676358/source.properties].each do |entry|
      target = File.join(sdk, entry); FileUtils.mkdir_p(File.dirname(target)); File.write(target, 'fixture')
    end
    _, err, status = run_zsh(<<~'SH')
      ap_read_requirements || exit $?
      ANDROID_SIM_SDK="${AP_TEST_SDK:h}/Android SDK"
      android_install_package() { print unexpected-install >> "$AP_TEST_TRACE"; return 41; }
      pe_run_logged() { print "health $*" >> "$AP_TEST_TRACE"; }
      ap_install_packages
    SH
    assert status.success?, err
    trace = File.read(@env['AP_TEST_TRACE'])
    refute_includes trace, 'unexpected-install'
    assert_includes trace, 'platforms.android.native platforms.android NDK / CMake succeeded'
  end

  def test_module_source_has_no_install_or_project_write
    _, err, status = run_zsh('true')
    assert status.success?, err
    assert_empty Dir.children(@run)
    refute File.exist?(@env['AP_TEST_TRACE'])
  end

  def test_license_exit_zero_without_acceptance_is_still_attention
    fake = File.join(@root, 'sdkmanager')
    File.write(fake, "#!/bin/zsh\nprint '7 of 7 SDK package licenses not accepted.'\n")
    FileUtils.chmod(0o755, fake)
    @env['AP_TEST_MANAGER'] = fake
    _, err, status = run_zsh('ANDROID_SIM_SDKMANAGER="$AP_TEST_MANAGER"; ANDROID_SIM_SDK="$AP_TEST_SDK"; LOG_FILE="$PE_RUN_DIR/android.log"; ap_review_licenses')
    assert_equal 3, status.exitstatus, err
    trace = File.read(@env['AP_TEST_TRACE'])
    assert_includes trace, 'attention'
    refute_includes trace, 'succeeded'
  end

  def test_license_acceptance_uses_official_result
    fake = File.join(@root, 'sdkmanager')
    File.write(fake, "#!/bin/zsh\nprint 'All SDK package licenses accepted.'\n")
    FileUtils.chmod(0o755, fake)
    @env['AP_TEST_MANAGER'] = fake
    _, err, status = run_zsh('ANDROID_SIM_SDKMANAGER="$AP_TEST_MANAGER"; ANDROID_SIM_SDK="$AP_TEST_SDK"; LOG_FILE="$PE_RUN_DIR/android.log"; ap_review_licenses')
    assert status.success?, err
    assert_includes File.read(@env['AP_TEST_TRACE']), 'Android许可证 succeeded'
  end
end
