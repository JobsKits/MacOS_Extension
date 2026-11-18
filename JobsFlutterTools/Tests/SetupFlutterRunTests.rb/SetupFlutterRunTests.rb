# frozen_string_literal: true
# 启动配置只作数据解析；假Flutter验证app.started门禁和detach，不操作真实设备。
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
require 'json'
require 'pty'

require_relative '../../../Tests/SourceLayoutHelper.rb/SourceLayoutHelper'

class SetupFlutterRunTests < Minitest::Test
  TOOLS = File.expand_path('../Scripts/Tools', File.dirname(__dir__))
  HELPER = JobsSourceLayout.file(File.join(TOOLS, 'SetupFlutterRun.jxa/SetupFlutterRun.jxa'))

  def setup
    @root = File.realpath(Dir.mktmpdir('flutter-run-composition-'))
    @project = File.join(@root, '项目 with spaces')
    @run = File.join(@root, 'run')
    @bin = File.join(@root, 'bin')
    FileUtils.mkdir_p([File.join(@project, 'lib'), File.join(@project, '.vscode'), File.join(@project, '.run'), @run, @bin])
    File.write(File.join(@project, 'lib/main.dart'), 'void main() {}')
    File.write(File.join(@project, 'pubspec.yaml'), "name: fixture\ndependencies:\n  flutter:\n    sdk: flutter\n")
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def helper(*args)
    Open3.capture3('/usr/bin/osascript', '-l', 'JavaScript', HELPER, *args)
  end

  def shell(code, env: {})
    source = %w[ProjectEnvironment.zsh ManageProjectJava.zsh DownloadProjectGradle.zsh SetupFlutterProject.zsh SetupFlutterRun.zsh].map { |file| "source #{JobsSourceLayout.file(File.join(TOOLS, file)).shellescape}" }.join("\n")
    Open3.capture3(env, '/bin/zsh', '-c', "#{source}\n#{code}")
  end

  def test_jsonc_keeps_url_and_does_not_execute_tasks_or_substitution
    File.write(File.join(@project, '.vscode/launch.json'), <<~JSONC)
      { // comment
        "configurations": [{"name":"调试","type":"dart","request":"launch", "preLaunchTask":"touch INJECTED",
          "program":"${workspaceFolder}/lib/main.dart", "flutterMode":"debug",
          "toolArgs":["--flavor","Test","--dart-define=URL=https://example.com/a//b","--dart-define=TEXT=$(touch INJECTED)",],
        },],
      }
    JSONC
    output, err, status = helper('configs', @project)
    assert status.success?, err
    rows = JSON.parse(output)
    assert_equal 2, rows.length
    assert_includes rows.last['args'], '--dart-define=URL=https://example.com/a//b'
    assert_includes rows.last['args'], '--dart-define=TEXT=$(touch INJECTED)'
    refute File.exist?(File.join(@project, 'INJECTED'))
  end

  def test_xml_run_configuration_reads_quoted_flavor_and_rejects_entities
    File.write(File.join(@project, '.run/test.run.xml'), '<component><configuration name="Test" type="FlutterRunConfigurationType"><option name="additionalArgs" value="--flavor Test --dart-define=&quot;VALUE=hello world&quot; -v"/><option name="filePath" value="$PROJECT_DIR$/lib/main.dart"/></configuration></component>')
    File.write(File.join(@project, '.run/entity.run.xml'), '<!DOCTYPE x [<!ENTITY a SYSTEM "file:///etc/passwd">]><component>&a;</component>')
    output, err, status = helper('configs', @project)
    assert status.success?, err
    rows = JSON.parse(output)
    assert_equal 2, rows.length
    assert_includes rows.last['args'], '--dart-define=VALUE=hello world'
    assert_includes err, '拒绝外部实体'
    refute_includes output, 'root:'
  end

  def test_unknown_flags_and_control_values_not_forwarded
    File.write(File.join(@project, '.vscode/launch.json'), JSON.generate(configurations: [
      { name: 'device override', type: 'dart', toolArgs: ['--device-id', 'another'] },
      { name: 'newline', type: 'dart', toolArgs: ['--dart-define', "KEY=a\n--release"] }
    ]))
    output, err, status = helper('configs', @project)
    assert status.success?, err
    assert_equal 1, JSON.parse(output).length
    assert_includes err, '已跳过'
  end

  def test_device_list_filters_target_platform_and_preserves_real_ids
    file = File.join(@root, 'devices.json')
    File.write(file, JSON.generate([{ id:'iphone', name:'iPhone', targetPlatform:'ios', emulator:true }, { id:'android', name:'Pixel', targetPlatform:'android-arm64' }, { id:'unsupported', targetPlatform:'ios', isSupported:false }, { id:"bad\nid", targetPlatform:'ios' }]))
    output, err, status = helper('devices', file, 'ios')
    assert status.success?, err
    assert_equal "iphone\tiPhone · ios · 模拟器\n", output
  end

  def test_started_requires_real_event_matching_app_start_and_device
    file = File.join(@root, 'machine.log')
    File.write(file, JSON.generate([{event:'app.start',params:{appId:'one',deviceId:'iphone'}}]) + "\n" + JSON.generate([{event:'app.log',params:{message:'app.started'}}]) + "\n")
    output, err, status = helper('started', file, 'iphone')
    assert status.success?, err
    assert_empty output.strip
    File.open(file, 'a') { |f| f.puts JSON.generate([{event:'app.started',params:{appId:'one'}}]) }
    output, _, status = helper('started', file, 'iphone')
    assert status.success?
    assert_equal 'one', output.strip
    output, _, status = helper('started', file, 'android')
    assert status.success?
    assert_empty output.strip
  end

  def test_target_and_define_file_cannot_escape_project
    outside = File.join(@root, 'outside.dart')
    File.write(outside, '')
    output, _, status = shell("SF_PROJECT=#{@project.shellescape}; SR_ARGS=(--target ../outside.dart); sr_validate_arguments")
    refute status.success?, output
    FileUtils.ln_s(outside, File.join(@project, 'lib/link.dart'))
    _, _, status = shell("SF_PROJECT=#{@project.shellescape}; SR_ARGS=(--target lib/link.dart); sr_validate_arguments")
    refute status.success?
  end

  def test_valid_start_detaches_and_marks_actual_run_verified
    output, status, trace = run_fixture('started')
    assert status.success?, output
    assert_includes output, '实际启动验证通过'
    assert_includes trace, 'app.detach'
    assert_equal 1, File.readlines(File.join(@run, 'control.log.launches')).length
    assert_equal 1, output.scan('PREFLIGHT_CHECK').length
    events = File.readlines(File.join(@run, 'events.jsonl')).map { |line| JSON.parse(line) }
    assert events.any? { |event| event['id'] == 'readiness.preflight' && event['state'] == 'succeeded' }
    assert_equal 'succeeded', events.last['state']
  end

  def test_preflight_failure_and_timeout_never_open_run_channel_or_start_flutter
    [1, 124].each do |code|
      output, status, trace = run_fixture('started', preflight_exit: code)
      assert_equal code, status.exitstatus, output
      assert_empty trace
      refute File.exist?(File.join(@run, 'control.log.launches'))
      refute File.exist?(File.join(@run, 'flutter-run.fifo'))
      events = File.readlines(File.join(@run, 'events.jsonl')).map { |line| JSON.parse(line) }
      assert events.any? { |event| event['id'] == 'readiness.preflight' && event['state'] == 'failed' }
      refute events.any? { |event| event['id'] == 'readiness.run' && event['state'] == 'running' }
    end
  end

  def test_final_confirmation_cancel_does_not_check_health_or_start_flutter
    output, status, = run_fixture('started', answer: "cancel\n")
    assert_equal 130, status.exitstatus, output
    refute_includes output, 'PREFLIGHT_CHECK'
    refute File.exist?(File.join(@run, 'control.log.launches'))
    refute File.exist?(File.join(@run, 'flutter-run.fifo'))
  end

  def test_preflight_adapter_preserves_selected_environment_output_and_timeout
    tools = File.join(@root, 'preflight tools')
    resources = File.join(tools, '【MacOS】Flutter运行前体检.zsh')
    FileUtils.mkdir_p(resources)
    File.write(File.join(resources, '【MacOS】Flutter运行前体检.zsh'), <<~'ZSH')
      jobs_flutter_preflight_overview() {
        print -r -- "SELECTED=$PROJECT_PATH|$FLUTTER_BIN|$JAVA_HOME|${PATH%%:*}"
        run_bounded 5 "$LOG_FILE.preflight.probe" /fixture/tool --version
      }
      jobs_flutter_preflight_require() { print -r -- "REQUIRE=$1|$2"; }
    ZSH
    [0, 124].each do |code|
      output, err, status = shell(<<~ZSH)
        PE_TOOLS_DIR=#{tools.shellescape}
        PE_RUN_DIR=#{@run.shellescape}
        SF_PROJECT=#{@project.shellescape}
        SF_FLUTTER=/fixture/sdk/bin/flutter
        SF_JAVA_HOME=/fixture/jdk
        SR_TARGET=ios
        SR_DEVICE=fixture-device
        log() { print OUTER_LOG; }
        run_bounded() { print OUTER_BOUNDED; }
        sf_run_diagnostic() {
          [[ "$SF_COMMAND_TIMEOUT" == 5 && "$2" == /fixture/tool && "$3" == --version ]] || return 73
          print -r -- probe-output > "$PE_RUN_DIR/$1.log"
          return #{code}
        }
        sr_run_preflight
        result=$?
        log
        run_bounded
        exit "$result"
      ZSH
      assert_equal code, status.exitstatus, output + err
      assert_includes output, "SELECTED=#{@project}|/fixture/sdk/bin/flutter|/fixture/jdk|/fixture/jdk/bin"
      assert_includes output, 'OUTER_LOG'
      assert_includes output, 'OUTER_BOUNDED'
      assert_equal "probe-output\n", File.read(File.join(@run, 'run.preflight.probe'))
      if code.zero?
        assert_includes output, 'REQUIRE=ios|fixture-device'
      else
        refute_includes output, 'REQUIRE='
      end
    end
  end

  def test_preflight_adapter_requires_complete_packaged_module
    ['missing', 'incomplete'].each do |kind|
      tools = File.join(@root, "#{kind}-tools")
      if kind == 'incomplete'
        resources = File.join(tools, '【MacOS】Flutter运行前体检.zsh')
        FileUtils.mkdir_p(resources)
        File.write(File.join(resources, '【MacOS】Flutter运行前体检.zsh'), 'jobs_flutter_preflight_overview() { return 0; }')
      end
      output, err, status = shell("PE_TOOLS_DIR=#{tools.shellescape}; sr_run_preflight")
      refute status.success?, output + err
      assert_includes output, '体检模块'
    end
  end

  def test_app_start_only_is_not_launch_success
    output, status, = run_fixture('start-only')
    assert_equal 3, status.exitstatus, output
    refute_includes output, '实际启动验证通过'
    assert_includes output, '实际运行验证未通过'
  end

  def test_build_failure_preserves_real_exit_code
    output, status, = run_fixture('failed')
    assert_equal 42, status.exitstatus, output
    assert_includes output, '实际运行验证未通过'
  end

  def test_fixed_bundler_healthy_reuse_passes_locked_selector
    gemfile = File.join(@project, 'Gemfile')
    File.write(gemfile, "gem 'cocoapods'\n")
    File.write("#{gemfile}.lock", "BUNDLED WITH\n   2.4.22\n")
    trace = File.join(@run, 'bundle-trace')
    bundle = File.join(@bin, 'bundle')
    File.write(bundle, "#!/bin/zsh\nprint -r -- \"$*\" >> #{trace.shellescape}\nprint 'Bundler version 2.4.22'\n")
    FileUtils.chmod(0o755, bundle)
    output, err, status = shell("PE_RUN_DIR=#{@run.shellescape}; PE_LOG_FILE=#{File.join(@run, 'env.log').shellescape}; SF_PROJECT=#{@project.shellescape}; SR_GEMFILE=#{gemfile.shellescape}; sr_ensure_bundler; print -rl -- \"${SR_BUNDLE_COMMAND[@]}\"", env: {'PATH'=>"#{@bin}:/usr/bin:/bin:/usr/sbin:/sbin"})
    assert status.success?, "#{output}#{err}"
    assert_includes File.read(trace), '_2.4.22_ --version'
    assert_includes output, '_2.4.22_'
    refute_includes File.read(trace), 'install'
  end

  def test_missing_fixed_bundler_installs_user_gem_and_rechecks
    gemfile = File.join(@project, 'Gemfile')
    File.write(gemfile, "gem 'cocoapods'\n")
    File.write("#{gemfile}.lock", "BUNDLED WITH\n   2.4.22\n")
    user_gem = File.join(@run, 'gems')
    trace = File.join(@run, 'gem-trace')
    scripts = {
      'bundle'=>"exit 1",
      'ruby'=>"if [[ \"$1\" == -e ]]; then print -r -- #{user_gem.shellescape}; else print 'ruby fixture'; fi",
      'gem'=> <<~ZSH
        [[ "$1" != --version ]] || { print '3.6 fixture'; exit 0; }
        print -r -- "$*" > #{trace.shellescape}
        mkdir -p #{File.join(user_gem, 'bin').shellescape}
        printf '#!/bin/zsh\\nprint "Bundler version 2.4.22"\\n' > #{File.join(user_gem, 'bin/bundle').shellescape}
        chmod 755 #{File.join(user_gem, 'bin/bundle').shellescape}
      ZSH
    }
    scripts.each { |name, body| path=File.join(@bin,name); File.write(path,"#!/bin/zsh\n#{body}\n"); FileUtils.chmod(0o755,path) }
    output, err, status = shell("PE_RUN_DIR=#{@run.shellescape}; PE_LOG_FILE=#{File.join(@run, 'env.log').shellescape}; SF_PROJECT=#{@project.shellescape}; SR_GEMFILE=#{gemfile.shellescape}; sr_ensure_bundler; print -rl -- \"${SR_BUNDLE_COMMAND[@]}\"", env: {'PATH'=>"#{@bin}:/usr/bin:/bin:/usr/sbin:/sbin"})
    assert status.success?, "#{output}#{err}"
    assert_includes File.read(trace), '--version 2.4.22'
    assert_includes File.read(trace), '--user-install'
    assert_includes File.read(trace), '--clear-sources --source https://rubygems.org'
    assert_includes output, File.join(user_gem, 'bin/bundle')
  end

  def test_android_simulator_entry_executes_core_with_real_tty
    tools = File.join(@root, 'simulator-tools')
    FileUtils.mkdir_p(tools)
    wrapper = File.join(tools, 'SetupCreateAndroidSimulator.zsh')
    JobsSourceLayout.copy(JobsSourceLayout.file(File.join(TOOLS, '【MacOS】SetupCreateAndroidSimulator.zsh/【MacOS】SetupCreateAndroidSimulator.zsh')), wrapper)
    trace = File.join(@run, 'simulator-trace')
    File.write(File.join(tools, 'AndroidSdkSupport.zsh'), <<~ZSH)
      show_script_intro_and_wait() {
        [[ -t 0 ]] || exit 81
        print intro >> #{trace.shellescape}
        IFS= read -r answer || exit 130
      }
      android_run_requested_action() { print run >> #{trace.shellescape}; }
    ZSH
    output = +''
    status = nil
    PTY.spawn('/bin/zsh', wrapper) do |reader, writer, pid|
      writer.write("\n"); writer.flush
      begin
        loop { output << reader.readpartial(4096) }
      rescue EOFError, Errno::EIO
      end
      _, status=Process.wait2(pid)
    end
    assert status.success?, output
    assert_equal "intro\nrun\n", File.read(trace)
  end

  def test_bundler_26_rejects_old_path_ruby_and_reuses_compatible_brew_ruby
    gemfile = File.join(@project, 'Gemfile')
    File.write(gemfile, "ruby '>= 3.1.0'\ngem 'cocoapods'\n")
    prefix = File.join(@root, 'brew')
    new_bin = File.join(prefix, 'opt/ruby/bin')
    FileUtils.mkdir_p(new_bin)
    scripts = {
      File.join(@bin, 'ruby')=>"exit 1",
      File.join(@bin, 'gem')=>"print 3.0",
      File.join(new_bin, 'ruby')=>"print -r -- \"$*\" > #{File.join(@run, 'ruby-requirements').shellescape}\nexit 0",
      File.join(new_bin, 'gem')=>"print 3.5"
    }
    scripts.each { |path, body| File.write(path, "#!/bin/zsh\n#{body}\n"); FileUtils.chmod(0o755, path) }
    output, err, status = shell("SR_GEMFILE=#{gemfile.shellescape}; PJ_BREW_PREFIX=#{prefix.shellescape}; sr_select_compatible_ruby 2.6.0; print -r -- \"$SR_RUBY\"", env: {'PATH'=>"#{@bin}:/usr/bin:/bin:/usr/sbin:/sbin"})
    assert status.success?, "#{output}#{err}"
    assert_equal File.join(new_bin, 'ruby'), output.strip
    assert_includes File.read(File.join(@run, 'ruby-requirements')), '3.1 >= 3.1.0'
  end

  def test_real_ruby_gate_checks_version_not_just_executability
    skip 'system Ruby unavailable' unless File.executable?('/usr/bin/ruby') && File.executable?('/usr/bin/gem')
    version, _, probe = Open3.capture3('/usr/bin/ruby', '-e', 'puts RUBY_VERSION')
    skip 'system Ruby unavailable' unless probe.success?
    _, _, status = shell("SR_BUNDLER_MIN_RUBY=3.1; SR_RUBY_REQUIREMENT=''; sr_ruby_compatible /usr/bin/ruby /usr/bin/gem")
    assert_equal Gem::Version.new(version.strip) >= Gem::Version.new('3.1'), status.success?
  end

  def test_large_raw_log_keeps_streamed_start_state_without_size_limit_false_negative
    raw = File.join(@run, 'large.raw.log')
    minimal = File.join(@run, 'machine-events.jsonl')
    File.open(raw, 'wb') do |file|
      34.times { file.write('x' * (1024 * 1024)) }
      file.puts
      file.puts JSON.generate([{event:'app.start',params:{appId:'large-app',deviceId:'iphone'}}])
      file.puts JSON.generate([{event:'app.started',params:{appId:'large-app',observatoryUri:'http://127.0.0.1/?token=raw'}}])
    end
    before = File.size(raw)
    output, err, status = shell("sr_machine_events < #{raw.shellescape} > #{minimal.shellescape}")
    assert status.success?, "#{output}#{err}"
    assert_equal before, File.size(raw)
    assert_operator File.size(minimal), :<, 1024
    output, err, status = helper('started', minimal, 'iphone')
    assert status.success?, err
    assert_equal 'large-app', output.strip
  end

  def test_sr_event_forwards_visible_version_and_retains_it_for_same_node
    events = File.join(@run, 'versions.jsonl')
    output, err, status = shell("sr_event platforms.ios.pods platforms.ios CocoaPods succeeded 'path hidden in tooltip' 'CocoaPods 1.16.2'; sr_event platforms.ios.pods platforms.ios CocoaPods succeeded", env: {'JOBS_FLUTTER_SETUP_EVENTS'=>events})
    assert status.success?, "#{output}#{err}"
    rows = File.readlines(events).map { |line| JSON.parse(line) }
    assert_equal 'CocoaPods 1.16.2', rows.last['version']
  end

  def run_fixture(mode, preflight_exit: 0, answer: "\n")
    flutter = File.join(@bin, 'flutter')
    trace = File.join(@run, 'control.log')
    File.write(flutter, <<~ZSH)
      #!/bin/zsh
      print -r -- RUN >> #{"#{trace}.launches".shellescape}
      [[ '#{mode}' != failed ]] || { print 'Code signing failed'; exit 42; }
      print '[{"event":"app.start","params":{"appId":"app-1","deviceId":"fixture-device"}}]'
      [[ '#{mode}' != start-only ]] || exit 0
      print '[{"event":"app.started","params":{"appId":"app-1","observatoryUri":"http://127.0.0.1:1234/?token=raw-machine-value"}}]'
      IFS= read -r message || exit 45
      print -r -- "$message" > #{trace.shellescape}
      [[ "$message" == *app.detach* ]] || exit 46
    ZSH
    FileUtils.chmod(0o755, flutter)
    events = File.join(@run, 'events.jsonl')
    prefix = %w[ProjectEnvironment.zsh ManageProjectJava.zsh DownloadProjectGradle.zsh SetupFlutterProject.zsh SetupFlutterRun.zsh].map { |file| "source #{JobsSourceLayout.file(File.join(TOOLS, file)).shellescape}" }.join("\n")
    code = "#{prefix}\nsr_run_preflight() { print PREFLIGHT_CHECK; return #{preflight_exit}; }\nPE_RUN_DIR=#{@run.shellescape}; PE_LOG_FILE=#{File.join(@run, 'environment.log').shellescape}; PE_TOOLS_DIR=#{TOOLS.shellescape}; SF_PROJECT=#{@project.shellescape}; SF_FLUTTER=#{flutter.shellescape}; SF_JAVA_HOME=/fixture/jdk; SR_TARGET=ios; SR_DEVICE=fixture-device; SR_ARGS=(--debug --target lib/main.dart); sr_verify_run"
    output = +''
    status = nil
    PTY.spawn({'NO_COLOR'=>'1', 'TERM'=>'dumb', 'JOBS_FLUTTER_SETUP_EVENTS'=>events}, '/bin/zsh', '-c', code) do |reader, writer, pid|
      writer.write(answer)
      writer.flush
      begin
        loop { output << reader.readpartial(4096) }
      rescue EOFError, Errno::EIO
      end
      _, status = Process.wait2(pid)
    end
    [output.force_encoding('UTF-8'), status, File.exist?(trace) ? File.read(trace) : '']
  end
end
