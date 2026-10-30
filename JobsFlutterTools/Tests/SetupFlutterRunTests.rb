# frozen_string_literal: true
# 启动配置只作数据解析；假Flutter验证app.started门禁和detach，不操作真实设备。
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'shellwords'
require 'json'
require 'pty'

class SetupFlutterRunTests < Minitest::Test
  TOOLS = File.expand_path('../Scripts/Tools', __dir__)
  HELPER = File.join(TOOLS, 'SetupFlutterRun.jxa')

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
    source = %w[ProjectEnvironment.zsh ManageProjectJava.zsh DownloadProjectGradle.zsh SetupFlutterProject.zsh SetupFlutterRun.zsh].map { |file| "source #{File.join(TOOLS, file).shellescape}" }.join("\n")
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
    events = File.readlines(File.join(@run, 'events.jsonl')).map { |line| JSON.parse(line) }
    assert_equal 'succeeded', events.last['state']
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
    FileUtils.cp(File.join(TOOLS, 'SetupCreateAndroidSimulator.zsh'), wrapper)
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

  def run_fixture(mode)
    flutter = File.join(@bin, 'flutter')
    trace = File.join(@run, 'control.log')
    File.write(flutter, <<~ZSH)
      #!/bin/zsh
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
    prefix = %w[ProjectEnvironment.zsh ManageProjectJava.zsh DownloadProjectGradle.zsh SetupFlutterProject.zsh SetupFlutterRun.zsh].map { |file| "source #{File.join(TOOLS, file).shellescape}" }.join("\n")
    code = "#{prefix}\nPE_RUN_DIR=#{@run.shellescape}; PE_LOG_FILE=#{File.join(@run, 'environment.log').shellescape}; PE_TOOLS_DIR=#{TOOLS.shellescape}; SF_PROJECT=#{@project.shellescape}; SF_FLUTTER=#{flutter.shellescape}; SF_JAVA_HOME=/fixture/jdk; SR_DEVICE=fixture-device; SR_ARGS=(--debug --target lib/main.dart); sr_verify_run"
    output = +''
    status = nil
    PTY.spawn({'NO_COLOR'=>'1', 'TERM'=>'dumb', 'JOBS_FLUTTER_SETUP_EVENTS'=>events}, '/bin/zsh', '-c', code) do |reader, writer, pid|
      writer.write("\n")
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
