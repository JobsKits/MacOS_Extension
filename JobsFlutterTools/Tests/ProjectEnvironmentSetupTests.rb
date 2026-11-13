# frozen_string_literal: true
# 假SDK/网络与临时工程验证选择、版本门禁、校验回退和流程停止，不操作真实环境。
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
require 'shellwords'
require 'digest'
require 'json'
require 'pty'

class ProjectEnvironmentSetupTests < Minitest::Test
  TOOLS = File.expand_path('../Scripts/Tools', __dir__)

  def setup
    @root = File.realpath(Dir.mktmpdir('flutter-environment-fixture-'))
    @project = File.join(@root, '中文 Project $(touch INJECTED)')
    @bin = File.join(@root, 'bin')
    @home = File.join(@root, 'home')
    @jdk = File.join(@root, 'Java Home')
    @sdk = File.join(@root, 'Flutter SDK')
    @run = File.join(@root, 'temp')
    @trace = File.join(@root, 'trace')
    FileUtils.mkdir_p([@project, @bin, @home, @run, File.join(@project, 'android/gradle/wrapper'), File.join(@project, 'lib')])
    File.write(File.join(@project, 'pubspec.yaml'), "name: fixture\ndependencies:\n  flutter:\n    sdk: flutter\n")
    File.write(File.join(@project, 'android/gradle/wrapper/gradle-wrapper.jar'), 'fixture wrapper jar')
    write_script(File.join(@project, 'android/gradlew'), <<~'SH')
      printf 'wrapper|%s|%s\n' "$*" "$JAVA_HOME" >> "$ET_TRACE"
      test "${ET_WRAPPER_FAIL:-0}" = 0 || exit 45
      printf 'Gradle 8.14\n'
    SH
    write_script(File.join(@jdk, 'bin/java'), "print -u2 'openjdk version \"17.0.17\"'")
    write_script(File.join(@jdk, 'bin/javac'), "print -u2 'javac 17.0.17'")
    write_script(File.join(@bin, 'chrome'), "print 'Google Chrome fixture'")
    write_script(File.join(@sdk, 'bin/cache/dart-sdk/bin/dart'), "print -u2 'Dart SDK version: 3.13.7 (stable)'")
    write_script(File.join(@sdk, 'bin/flutter'), <<~'ZSH')
      print -r -- "flutter|$*|$JAVA_HOME" >> "$ET_TRACE"
      case "$1" in
        --version)
          if [[ "${ET_BOOTSTRAP_MESSAGES:-0}" == 1 ]]; then
            if [[ ! -f "$ET_BOOTSTRAP_STATE" ]]; then
              print -u2 'Downloading Dart SDK and Flutter tools...'
              : > "$ET_BOOTSTRAP_STATE"
            fi
            if [[ "${2:-}" != --machine ]]; then
              print 'Flutter 3.47.8 · Dart 3.13.7'
              exit 0
            fi
          fi
          print '{"frameworkVersion":"3.47.8"}' ;;
        pub) [[ "${ET_PUB_FAIL:-0}" == 0 ]] || exit 42; print '{}' > .flutter-plugins-dependencies ;;
        build) [[ "${ET_BUILD_FAIL:-0}" == 0 ]] || exit 46 ;;
        precache) exit 0 ;;
        doctor) print '[✓] Flutter'; print "    • Java binary at: $JAVA_HOME/bin/java"; [[ "${ET_DOCTOR_FAIL:-0}" == 0 ]] || print '[!] Android SDK missing' ;;
        devices) print '[{"id":"fixture","name":"fixture","targetPlatform":"android-arm64"}]' ;;
        *) exit 91 ;;
      esac
    ZSH
    FileUtils.ln_s(File.join(@sdk, 'bin/flutter'), File.join(@bin, 'flutter'))
    distribution = File.join(@root, 'archive/gradle-8.14/bin/gradle')
    write_script(distribution, <<~'ZSH')
      print -r -- "gradle|$*|$JAVA_HOME|$PWD" >> "$ET_TRACE"
      [[ "${ET_GRADLE_FAIL:-0}" == 0 ]] || { print 'invalid project configuration'; exit 43; }
      [[ -f ../.flutter-plugins-dependencies ]] || { print 'flutter dependencies missing'; exit 44; }
      print 'BUILD SUCCESSFUL'
    ZSH
    @archive = File.join(@root, 'gradle.zip')
    _, err, status = Open3.capture3('/usr/bin/zip', '-qr', @archive, 'gradle-8.14', chdir: File.join(@root, 'archive'))
    raise err unless status.success?
    @sha = Digest::SHA256.file(@archive).hexdigest
    write_wrapper
    write_script(File.join(@bin, 'curl'), <<~'ZSH')
      [[ "$1" != --version ]] || { print 'curl fixture'; exit 0; }
      target="" url="${@[-1]}"
      while (( $# )); do
        if [[ "$1" == --output ]]; then target="$2"; shift 2; else shift; fi
      done
      print -r -- "curl|$url" >> "$ET_TRACE"
      if [[ "${ET_PRIMARY_FAIL:-0}" == 1 && "$url" == *services.gradle.org* ]]; then print -u2 'curl: (22) The requested URL returned error: 404'; exit 22; fi
      if [[ "$url" == *.sha256 ]]; then print -rn -- "$ET_SHA" > "$target";
      elif [[ "${ET_BAD_ZIP:-0}" == 1 ]]; then print bad > "$target";
      else /bin/cp "$ET_ARCHIVE" "$target"; fi
    ZSH
    write_script(File.join(@bin, 'fzf'), <<~'ZSH')
      [[ "$1" != --version ]] || { print '0.66 fixture'; exit 0; }
      rows="$(cat)"
      index=1
      [[ ! -f "$ET_SELECT_STATE" ]] || index="$(cat "$ET_SELECT_STATE")"
      choices=("${(@s:,:)ET_CHOICES}")
      chosen="${choices[index]}"
      print -r -- "fzf|$index|$chosen|$rows" >> "$ET_TRACE"
      print $((index + 1)) > "$ET_SELECT_STATE"
      [[ "$chosen" != cancel ]] || exit 130
      [[ "$chosen" != left ]] || { print left; print ''; exit 0; }
      while IFS= read -r row; do
        [[ "${row%%$'\t'*}" == "$chosen" ]] || continue
        print ''; print -r -- "$row"; exit 0
      done <<< "$rows"
      exit 2
    ZSH
    @env = { 'HOME' => @home, 'TMPDIR' => @run, 'PATH' => "#{@bin}:/usr/bin:/bin:/usr/sbin:/sbin", 'JAVA_HOME' => @jdk,
             'NO_COLOR' => '1', 'TERM' => 'dumb', 'GRADLE_OPTS' => nil, 'CHROME_EXECUTABLE' => File.join(@bin, 'chrome'), 'ET_TRACE' => @trace, 'ET_ARCHIVE' => @archive,
             'ET_SHA' => @sha, 'ET_SELECT_STATE' => File.join(@root, 'selection'), 'ET_CHOICES' => 'system,system,official,path,current' }
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def write_script(path, body)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "#!/bin/zsh\n#{body}\n")
    FileUtils.chmod(0o755, path)
  end

  def write_wrapper(version: '8.14', checksum: @sha, url: nil)
    @wrapper = File.join(@project, 'android/gradle/wrapper/gradle-wrapper.properties')
    File.write(@wrapper, "distributionUrl=#{url || "https\\://services.gradle.org/distributions/gradle-#{version}-bin.zip"}\n#{checksum ? "distributionSha256Sum=#{checksum}\n" : ''}")
  end

  def shell(code, env: {})
    prefix = %w[ProjectEnvironment.zsh ManageProjectJava.zsh DownloadProjectGradle.zsh SetupFlutterProject.zsh WrapperDistributionCache.zsh].map { |f| "source #{File.join(TOOLS, f).shellescape}" }.join("\n")
    Open3.capture3(@env.merge(env), '/bin/zsh', '-c', "#{prefix}\n#{code}", chdir: @project)
  end

  def interactive(env: {}, input: "\n\n", sdk_only: true)
    output = +''
    status = nil
    arguments = ['/bin/zsh', File.join(TOOLS, 'SetupFlutterProject.zsh'), '--project', @project]
    arguments << '--sdk-only' if sdk_only
    PTY.spawn(@env.merge(env), *arguments) do |reader, writer, pid|
      writer.write(input)
      writer.flush
      begin
        loop { output << reader.readpartial(4096) }
      rescue EOFError, Errno::EIO
      end
      _, status = Process.wait2(pid)
    end
    [output.force_encoding('UTF-8'), status]
  end

  def trace
    File.exist?(@trace) ? File.read(@trace) : ''
  end

  def test_source_is_pure_and_redacts_urls
    out, err, status = shell('pe_log "https://name:password@example.com/a?secret=1"')
    assert status.success?, err
    assert_includes out, 'https://[REDACTED]@example.com/a?[REDACTED]'
    refute File.exist?(@trace)
    assert_empty Dir.children(@run)
  end

  def test_wrapper_fixed_version_and_java_matrix
    out, err, status = shell("DG_PROJECT=#{@project.shellescape}; dg_read_wrapper || exit $?; print -- \"$DG_VERSION|$DG_TYPE\"; DG_JAVA_MAJOR=17; dg_check_java_compatibility")
    assert status.success?, "#{out}#{err}"
    assert_includes out, '8.14|bin'
    _, _, status = shell('DG_VERSION=8.4; DG_JAVA_MAJOR=21; dg_check_java_compatibility')
    refute status.success?
    _, _, status = shell('DG_VERSION=9.0; DG_JAVA_MAJOR=11; dg_check_java_compatibility')
    refute status.success?
    _, _, status = shell('DG_VERSION=9.8; DG_JAVA_MAJOR=27; dg_check_java_compatibility')
    assert status.success?
  end

  def test_invalid_dynamic_duplicate_and_insecure_wrapper
    ['https://services.gradle.org/distributions/gradle-latest-bin.zip', 'http://services.gradle.org/distributions/gradle-8.14-bin.zip', 'https://user:pass@example.com/gradle-8.14-bin.zip'].each do |url|
      write_wrapper(url: url)
      _, _, status = shell("DG_PROJECT=#{@project.shellescape}; dg_read_wrapper")
      refute status.success?, url
    end
    write_wrapper
    File.open(@wrapper, 'a') { |f| f.puts 'distributionUrl=https://services.gradle.org/distributions/gradle-8.14-bin.zip' }
    _, _, status = shell("DG_PROJECT=#{@project.shellescape}; dg_read_wrapper")
    refute status.success?
    assert_empty trace
  end

  def test_gradle_criteria_conflict_stops_before_network
    File.write(File.join(@project, 'android/gradle/gradle-daemon-jvm.properties'), 'toolchainVersion=21')
    out, _, status = shell("DG_PROJECT=#{@project.shellescape}; dg_resolve_java")
    refute status.success?
    assert_includes out, 'JVM criteria'
    assert_empty trace
  end

  def test_verified_official_fallback_and_cache_reuse
    out, err, status = shell("DG_PROJECT=#{@project.shellescape}; DG_JAVA_HOME=#{@jdk.shellescape}; dg_read_wrapper && pe_initialize_runtime && dg_download_distribution && dg_extract_distribution && dg_download_distribution", env: { 'ET_PRIMARY_FAIL' => '1' })
    assert status.success?, "#{out}#{err}"
    assert_includes trace, 'downloads.gradle.org'
    assert_equal 3, trace.lines.count { |line| line.start_with?('curl|') }
    assert_includes out, '复用已校验分发包'
    refute_includes trace, 'gradle|'
  end

  def test_bad_checksum_never_executes_archive
    # 本例只验证摘要拒绝门禁；持续获取 / 中断由 SDK 重试专测覆盖。
    out, err, status = shell("jobs_sdk_retry() { shift 2; \"$@\"; }; DG_PROJECT=#{@project.shellescape}; dg_read_wrapper && pe_initialize_runtime && dg_download_distribution", env: { 'ET_BAD_ZIP' => '1' })
    refute status.success?, "#{out}#{err}"
    assert_match(/SHA256不匹配|摘要不符/, out)
    refute_includes trace, 'gradle|'
  end

  def test_official_checksum_required_when_wrapper_has_none
    write_wrapper(checksum: nil)
    out, err, status = shell("DG_PROJECT=#{@project.shellescape}; dg_read_wrapper && pe_initialize_runtime && dg_download_distribution")
    assert status.success?, "#{out}#{err}"
    assert_includes trace, '.zip.sha256'
  end

  def test_cross_platform_environment_is_not_silently_applied
    FileUtils.mkdir_p(File.join(@project, '.jobs'))
    File.write(File.join(@project, '.jobs/flutter-environment.json'), JSON.generate(Platform: 'Windows', FlutterPath: 'C:\\Flutter', JavaHome: 'C:\\Java'))
    out, _, status = shell("PE_PROJECT=#{@project.shellescape}; pe_read_environment")
    refute status.success?
    assert_includes out, 'Windows'
  end

  def test_environment_configuration_java_wins_over_old_jenv
    FileUtils.mkdir_p(File.join(@project, '.jobs'))
    File.write(File.join(@project, '.java-version'), 'broken-alias')
    File.write(File.join(@project, '.jobs/flutter-environment.json'), JSON.generate(Platform: 'MacOS', FlutterPath: File.join(@sdk, 'bin/flutter'), JavaHome: @jdk))
    out, err, status = shell("DG_PROJECT=#{@project.shellescape}; PE_PROJECT=\"$DG_PROJECT\"; DG_VERSION=8.14; dg_resolve_java; print -- \"$DG_JAVA_HOME\"")
    assert status.success?, "#{out}#{err}"
    assert_includes out, @jdk
  end

  def test_mode_back_navigation_and_cancel_do_not_write_project
    output, status = interactive(env: { 'ET_CHOICES' => 'system,left,fvm,cancel' }, input: "\n")
    assert_equal 130, status.exitstatus, output
    refute File.exist?(File.join(@project, '.jobs'))
    refute File.exist?(File.join(@project, '.fvmrc'))
    refute_includes trace, 'curl|'
  end

  def test_complete_system_mode_flow_preserves_existing_bindings_and_orders_stages
    File.write(File.join(@project, '.fvmrc'), '{"flutter":"old"}')
    File.write(File.join(@project, '.java-version'), '17')
    File.write(File.join(@project, 'android/local.properties'), "sdk.dir=/keep/android\nflutter.sdk=/old/sdk\n")
    output, status = interactive
    assert status.success?, output
    config = JSON.parse(File.read(File.join(@project, '.jobs/flutter-environment.json')))
    assert_equal 'system', config['FlutterMode']
    assert_equal 'system', config['JavaMode']
    assert_equal @jdk, config['JavaHome']
    assert_equal '{"flutter":"old"}', File.read(File.join(@project, '.fvmrc'))
    assert_equal '17', File.read(File.join(@project, '.java-version'))
    properties = File.read(File.join(@project, 'android/local.properties'))
    assert_includes properties, 'sdk.dir=/keep/android'
    assert_includes properties, 'flutter.sdk='
    assert trace.index('curl|') < trace.index('flutter|pub get')
    assert trace.index('flutter|pub get') < trace.index('gradle|')
    assert_includes trace, "-Dorg.gradle.java.home=#{@jdk}"
    assert_includes output, '尚未实际构建/启动App'
    refute File.exist?(File.join(@project, 'INJECTED'))
  end

  def test_pub_failure_stops_plugin_prewarm
    output, status = interactive(env: { 'ET_PUB_FAIL' => '1' })
    assert_equal 42, status.exitstatus, output
    assert_includes trace, 'flutter|pub get'
    refute_includes trace, 'gradle|'
  end

  def test_non_network_gradle_error_is_not_retried_or_marked_ready
    output, status = interactive(env: { 'ET_GRADLE_FAIL' => '1' })
    assert_equal 43, status.exitstatus, output
    assert_equal 1, trace.lines.count { |line| line.start_with?('gradle|') }
    refute_includes trace, 'flutter|doctor'
  end

  def test_doctor_missing_toolchain_has_distinct_incomplete_status
    output, status = interactive(env: { 'ET_DOCTOR_FAIL' => '1' })
    assert_equal 3, status.exitstatus, "#{output}\n#{trace}"
    assert_includes output, '收尾检查未完全通过'
    assert File.exist?(File.join(@project, '.jobs/flutter-environment.json'))
  end

  def test_check_mode_is_read_only
    out, err, status = Open3.capture3(@env, '/bin/zsh', File.join(TOOLS, 'SetupFlutterProject.zsh'), '--project', @project, '--check')
    assert status.success?, "#{out}#{err}"
    assert_includes out, '只读盘点'
    assert_empty Dir.children(@run)
    assert_empty trace
  end

  def test_system_java_ignores_broken_jenv_declarations
    File.write(File.join(@project, '.java-version'), "not a version\n")
    File.write(File.join(@project, '.jenv-version'), 'legacy')
    output, status = interactive
    assert status.success?, output
    assert_equal "not a version\n", File.read(File.join(@project, '.java-version'))
    assert_equal 'legacy', File.read(File.join(@project, '.jenv-version'))
  end

  def test_cross_platform_environment_can_be_reconfigured_with_backup
    FileUtils.mkdir_p(File.join(@project, '.jobs'))
    previous = JSON.generate(Platform: 'Windows', FlutterPath: 'C:\\Flutter', JavaHome: 'C:\\Java')
    File.write(File.join(@project, '.jobs/flutter-environment.json'), previous)
    output, status = interactive
    assert status.success?, output
    current = JSON.parse(File.read(File.join(@project, '.jobs/flutter-environment.json')))
    assert_equal 'MacOS', current['Platform']
    backup = Dir.glob(File.join(@run, 'JobsFlutterEnvironment.*/before/flutter-environment.json')).first
    assert_equal previous, File.read(backup)
  end

  def test_full_web_flow_skips_broken_android_and_never_claims_actual_run
    FileUtils.mkdir_p(File.join(@project, 'web'))
    File.write(File.join(@project, 'lib/main.dart'), 'void main() {}')
    File.write(@wrapper, 'broken wrapper data')
    File.write(File.join(@project, 'android/gradle/gradle-daemon-jvm.properties'), 'toolchainVersion=21')
    output, status = interactive(sdk_only: false, env: { 'ET_CHOICES' => 'web,system,official,path,0,prepare' })
    assert_equal 3, status.exitstatus, "#{output}\n#{trace}"
    assert_includes trace, 'flutter|precache --web'
    assert_includes trace, 'flutter|pub get'
    assert_includes trace, 'flutter|build web --debug --target lib/main.dart'
    assert_operator trace.index('flutter|pub get'), :<, trace.index('flutter|build web')
    assert trace.lines.none? { |line| line.start_with?('flutter|run ', 'flutter|install ') }
    refute_includes trace, 'curl|'
    refute_includes trace, 'gradle|'
    refute_includes output, '实际启动验证通过'
    config = JSON.parse(File.read(File.join(@project, '.jobs/flutter-environment.json')))
    assert_equal 'none', config['JavaMode']
    assert_equal '', config['JavaHome']
    refute_includes trace, '|current|'
  end

  def test_missing_android_in_sdk_only_is_not_fatal
    FileUtils.remove_entry(File.join(@project, 'android'))
    output, status = interactive(env: { 'ET_CHOICES' => 'system,official,path' })
    assert status.success?, output
    assert_includes trace, 'flutter|pub get'
    refute_includes trace, 'curl|'
    refute File.exist?(File.join(@project, 'android'))
  end

  def test_no_java_environment_record_can_be_reused_without_installing_java
    FileUtils.mkdir_p(File.join(@project, '.jobs'))
    File.write(File.join(@project, '.jobs/flutter-environment.json'), JSON.generate(
      Platform: 'MacOS', FlutterPath: File.join(@sdk, 'bin/flutter'), JavaMode: 'none', JavaHome: ''
    ))
    out, err, status = shell("PE_PROJECT=#{@project.shellescape}; pe_read_environment && print -- \"$PE_CONFIG_FLUTTER|$PE_CONFIG_JAVA\"")
    assert status.success?, out + err
    assert_includes out, File.join(@sdk, 'bin/flutter')
    assert_empty trace
  end

  def test_fvm_manager_cancel_stops_even_when_old_sdk_is_healthy
    stub = File.join(@root, 'tools-stub')
    FileUtils.mkdir_p(stub)
    write_script(File.join(stub, 'ManageFlutterVersion.zsh'), "[[ \"${JOBS_FLUTTER_VERSION_CHAINED:-0}\" == 1 ]] && exit 130\nexit 0")
    FileUtils.mkdir_p(File.join(@project, '.fvm'))
    FileUtils.ln_s(@sdk, File.join(@project, '.fvm/flutter_sdk'))
    output, err, status = shell("SF_PROJECT=#{@project.shellescape}; SF_FLUTTER_MODE=fvm; PE_TOOLS_DIR=#{stub.shellescape}; pe_select() { PE_SELECTION=configure; }; sf_prepare_flutter")
    assert_equal 130, status.exitstatus, "#{output}#{err}"
    refute_includes trace, 'flutter|'
  end

  def test_fzf_left_with_no_match_still_returns_previous_level
    fake = File.join(@bin, 'fzf-left')
    write_script(fake, "cat >/dev/null\nprint left\nexit 1")
    _, _, status = shell("PE_FZF=#{fake.shellescape}; pe_select choice $'one\\tOne'")
    assert_equal 10, status.exitstatus
  end

  def test_ignoring_term_task_is_killed_after_timeout_grace
    fake = File.join(@bin, 'hang')
    write_script(fake, "trap '' TERM\nwhile true; do /bin/sleep 10; done")
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    output, err, status = shell("PE_RUN_DIR=#{@run.shellescape}; PE_LOG_FILE=#{File.join(@run, 'timeout.log').shellescape}; SF_PROJECT=#{@project.shellescape}; SF_COMMAND_TIMEOUT=1 sf_run_diagnostic hang #{fake.shellescape}")
    assert_equal 124, status.exitstatus, "#{output}#{err}"
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 8
    assert_includes output, '超过1秒'
  end

  def test_event_version_is_optional_and_retained_at_stage_completion
    events = File.join(@run, 'versions.jsonl')
    output, err, status = shell("pe_event flutter '' Flutter running '' 'Flutter 3.47.8 · Dart 3.13.7'; pe_event flutter '' Flutter succeeded 'done'; pe_event java '' Java pending", env: {'JOBS_FLUTTER_SETUP_EVENTS'=>events})
    assert status.success?, "#{output}#{err}"
    rows = File.readlines(events).map { |line| JSON.parse(line) }
    assert_equal 'Flutter 3.47.8 · Dart 3.13.7', rows[0]['version']
    assert_equal rows[0]['version'], rows[1]['version']
    assert_equal '', rows[2]['version']
  end

  def test_successful_sdk_flow_emits_actual_detected_versions
    events = File.join(@run, 'versions.jsonl')
    File.write(File.join(@project, 'android/settings.gradle.kts'), "// id(\"com.android.application\") version \"99.1.2\"\nplugins { id(\"com.android.application\") version \"8.7.3\" apply false }\n")
    output, status = interactive(env: {'JOBS_FLUTTER_SETUP_EVENTS'=>events})
    assert status.success?, output
    versions = File.readlines(events).map { |line| JSON.parse(line) }.select { |event| event['state']=='succeeded' }.map { |event| [event['id'],event['version']] }.to_h
    assert_equal 'Flutter 3.47.8 · Dart 3.13.7', versions['flutter']
    assert_equal 'Java 17.0.17', versions['java']
    assert_equal 'Gradle 8.14', versions['gradle.wrapper']
    assert_equal 'Gradle 8.14 · AGP 8.7.3', versions['gradle.plugins']
    refute_includes versions['gradle.plugins'], '99.1.2'
  end

  def test_sdk_bootstrap_progress_stays_separate_from_machine_version_and_events
    events = File.join(@run, 'bootstrap-events.jsonl')
    output, err, status = shell(
      "PE_RUN_DIR=#{@run.shellescape}; PE_LOG_FILE=#{File.join(@run, 'bootstrap-audit.log').shellescape}; SF_PROJECT=#{@project.shellescape}; sf_probe_flutter #{File.join(@sdk, 'bin/flutter').shellescape}",
      env: { 'ET_BOOTSTRAP_MESSAGES' => '1', 'ET_BOOTSTRAP_STATE' => File.join(@run, 'bootstrap-completed'),
             'JOBS_FLUTTER_SETUP_EVENTS' => events }
    )
    assert status.success?, output + err
    assert_includes output, 'Downloading Dart SDK and Flutter tools...'
    assert_includes File.read(File.join(@run, 'flutter-bootstrap.log')), 'Downloading Dart SDK and Flutter tools...'
    machine = File.read(File.join(@run, 'flutter-version.log'))
    assert_equal({ 'frameworkVersion' => '3.47.8' }, JSON.parse(machine))
    refute_includes machine, 'Downloading'
    version_calls = trace.lines.select { |line| line.start_with?('flutter|--version') }
    assert_equal 2, version_calls.length
    assert version_calls[0].start_with?('flutter|--version|'), '先用非机器调用完成首次组件下载'
    assert version_calls[1].start_with?('flutter|--version --machine|'), '下载完成后单独读取净JSON'
    sdk_event = File.readlines(events).map { |line| JSON.parse(line) }.find { |event| event['id'] == 'flutter.sdk' }
    assert_equal 'succeeded', sdk_event.fetch('state')
    assert_equal 'Flutter 3.47.8 · Dart 3.13.7', sdk_event.fetch('version')
  end

  def test_fvm_visible_version_comes_from_actual_manager_output
    write_script(File.join(@bin, 'fvm'), "print 'FVM version: 4.0.0'")
    events = File.join(@run, 'fvm-version.jsonl')
    output, err, status = shell("PE_RUN_DIR=#{@run.shellescape}; PE_LOG_FILE=#{File.join(@run, 'audit.log').shellescape}; sf_report_fvm_version", env: {'JOBS_FLUTTER_SETUP_EVENTS'=>events})
    assert status.success?, "#{output}#{err}"
    row = JSON.parse(File.readlines(events).last)
    assert_equal 'flutter.fvm', row['id']
    assert_equal 'FVM 4.0.0', row['version']
  end

  def test_tool_version_parser_ignores_other_component_warning_versions
    file = File.join(@run, 'versions-output.log')
    File.write(file, "Ignoring ffi-1.17.0 because extensions are not built\n1.16.2\n")
    output, err, status = shell("pe_semantic_version #{file.shellescape} pods")
    assert status.success?, err
    assert_equal '1.16.2', output
    File.write(file, "Dart SDK version: 3.12.0\nFVM version: 4.0.0\n")
    output, err, status = shell("pe_semantic_version #{file.shellescape} fvm")
    assert status.success?, err
    assert_equal '4.0.0', output
  end
end
