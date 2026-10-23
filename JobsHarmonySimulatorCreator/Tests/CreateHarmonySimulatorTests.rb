# frozen_string_literal: true
# Created by Jobs on 2026年10月23日，星期五。
# 用假 Emulator 与真实 zsh / JXA 验证官方命令契约，不下载、安装或操作真实模拟器。

require 'fileutils'
require 'digest'
require 'json'
require 'minitest/autorun'
require 'open3'
require 'pty'
require 'shellwords'
require 'timeout'
require 'tmpdir'

class CreateHarmonySimulatorTests < Minitest::Test
  SCRIPT = File.expand_path('../Scripts/CreateHarmonySimulator.zsh', __dir__)

  def setup
    @root = File.realpath(Dir.mktmpdir('jobs-harmony-simulator-'))
    @run = File.join(@root, 'run')
    @bin = File.join(@root, "DevEco 空格 ' $(touch INJECTED) `touch BACKTICK`", 'Emulator')
    FileUtils.mkdir_p([@run, File.dirname(@bin)])
    @images = File.join(@root, 'images.json')
    @instances = File.join(@root, 'instances.json')
    @available = File.join(@root, 'available.json')
    File.write(@available, JSON.generate([image('tv', downloaded: 'false'), image('2in1 Foldable', downloaded: 'false'), image('phone', downloaded: 'false')]))
    FileUtils.mkdir_p(File.join(File.dirname(@bin), 'agreement'))
    %w[HarmonyOS_SDK_Agreement HarmonyOS_Software_Service_Agreement].each { |name| File.write(File.join(File.dirname(@bin), 'agreement', name + '.txt'), 'Official agreement fixture') }
    @calls = File.join(@root, 'calls.jsonl')
    File.write(@images, JSON.generate([image('phone'), image('tablet'), image('watch', downloaded: 'false'), image('tv', release: 'Beta')]))
    File.write(@instances, '[]')
    File.write(@bin, <<~'RUBY')
      #!/usr/bin/ruby
      require 'json'
      require 'fileutils'
      File.open(ENV.fetch('HS_TEST_CALLS'), 'a') { |file| file.puts(JSON.generate(ARGV)) }
      command = ARGV.first
      case command
      when '-help'
        puts ENV.fetch('HS_TEST_HELP', '-help -create -imageList -list -details -start -install -license')
        exit ENV.fetch('HS_TEST_HELP_EXIT', '0').to_i
      when '-imageList'
        if ENV['HS_TEST_NATIVE_EMPTY'] == '1'
          warn 'No images matching the criteria were found.'
          exit ENV.fetch('HS_TEST_IMAGES_EXIT', '0').to_i
        end
        puts File.read(ENV.fetch(ARGV.last == 'false' ? 'HS_TEST_AVAILABLE' : 'HS_TEST_IMAGES'))
        exit ENV.fetch('HS_TEST_IMAGES_EXIT', '0').to_i
      when '-list'
        if ENV['HS_TEST_NATIVE_EMPTY'] == '1'
          puts '[Empty]'
          exit ENV.fetch('HS_TEST_LIST_EXIT', '0').to_i
        end
        if ENV['HS_TEST_RACE'] && File.readlines(ENV.fetch('HS_TEST_CALLS')).count { |line| JSON.parse(line).first == '-list' } == 2
          File.write(ENV.fetch('HS_TEST_INSTANCES'), JSON.generate([{ name: ENV['HS_TEST_RACE'], deviceType: 'phone', os: { osVersion: 'HarmonyOS 6.0.1(21)' } }]))
        end
        puts File.read(ENV.fetch('HS_TEST_INSTANCES'))
        exit ENV.fetch('HS_TEST_LIST_EXIT', '0').to_i
      when '-license'
        abort 'Expected explicit acceptance' unless ARGV == ['-license', 'accept']
        exit ENV.fetch('HS_TEST_LICENSE_EXIT', '0').to_i
      when '-install'
        exit ENV['HS_TEST_INSTALL_EXIT'].to_i if ENV['HS_TEST_INSTALL_EXIT']
        unless ENV['HS_TEST_DONT_INSTALL'] == '1'
          type = ARGV[ARGV.index('-deviceType') + 1]
          version = ARGV[ARGV.index('-osVersion') + 1]
          record = JSON.parse(File.read(ENV.fetch('HS_TEST_AVAILABLE'))).find { |r| r['deviceType'] == type && r['osVersion'] == version }
          abort 'Invalid requested image' unless record
          record['downloaded'] = 'true'
          File.write(ENV.fetch('HS_TEST_IMAGES'), JSON.generate([record]))
        end
      when '-create'
        abort 'The virtual device name can only contain letters, spaces, numbers, underscores (_) and plus sign(+)' unless ARGV[1].match?(/\A[A-Za-z0-9_+ ]+\z/)
        exit ENV['HS_TEST_CREATE_EXIT'].to_i if ENV['HS_TEST_CREATE_EXIT']
        unless ENV['HS_TEST_DONT_CREATE'] == '1'
          records = JSON.parse(File.read(ENV.fetch('HS_TEST_INSTANCES')))
          records = [records] unless records.is_a?(Array)
          directory = File.join(File.dirname(ENV.fetch('HS_TEST_INSTANCES')), 'deployed', ARGV[1])
          FileUtils.mkdir_p(directory)
          File.write(File.join(directory, 'config.ini'), "name=#{ARGV[1]}\nhw.ramSize=4096\n" + ENV.fetch('HS_TEST_SDK_CONFIG', ''))
          records << { 'name' => ARGV[1], 'deviceType' => ARGV[ARGV.index('-deviceType') + 1],
                       'instancePath' => directory,
                       'os' => { 'osVersion' => ENV.fetch('HS_TEST_WRONG_VERSION', ARGV[ARGV.index('-osVersion') + 1]) } }
          File.write(ENV.fetch('HS_TEST_INSTANCES'), JSON.generate(records))
        end
        puts 'Official create fixture returned'
      when '-start'
        puts '官方许可：请自行选择 y/n'
        response = STDIN.gets.to_s.strip
        File.write(ENV.fetch('HS_TEST_LICENSE'), response)
        exit ENV.fetch('HS_TEST_START_EXIT', '0').to_i
      else
        abort 'Unexpected operation: ' + ARGV.inspect
      end
    RUBY
    File.chmod(0o700, @bin)
    uname = File.join(@root, 'uname')
    File.write(uname, "#!/bin/zsh\n[[ \"$1\" != -s ]] || { print -r -- Darwin; exit 0; }\nprint -r -- \"${HS_TEST_ARCH:-arm64}\"\n")
    File.chmod(0o700, uname)
    sysctl = File.join(@root, 'sysctl')
    File.write(sysctl, "#!/bin/zsh\nprint -r -- \"${HS_TEST_TRANSLATED:-0}\"\n")
    File.chmod(0o700, sysctl)
    @open_calls = File.join(@root, 'open.jsonl')
    opener = File.join(@root, 'open-fixture')
    File.write(opener, <<~'RUBY')
      #!/usr/bin/ruby
      require 'json'
      require 'fileutils'
      File.open(ENV.fetch('HS_TEST_OPEN_CALLS'), 'a') { |file| file.puts(JSON.generate(ARGV)) }
      if ENV['HS_TEST_INSTALL_TO']
        FileUtils.mkdir_p(File.dirname(ENV['HS_TEST_INSTALL_TO']))
        FileUtils.cp(ENV.fetch('HS_TEST_INSTALL_FROM'), ENV['HS_TEST_INSTALL_TO'])
      end
      FileUtils.cp(ENV['HS_TEST_READY_IMAGES'], ENV.fetch('HS_TEST_IMAGES')) if ENV['HS_TEST_READY_IMAGES']
      exit ENV.fetch('HS_TEST_OPEN_EXIT', '0').to_i
    RUBY
    File.chmod(0o700, opener)
    package_root = File.join(@root, 'archive-content')
    tool_root = File.join(package_root, 'command-line-tools')
    FileUtils.mkdir_p(File.join(tool_root, 'emulator'))
    FileUtils.cp(@bin, File.join(tool_root, 'emulator', 'Emulator'))
    FileUtils.cp_r(File.join(File.dirname(@bin), 'agreement'), File.join(tool_root, 'emulator'))
    File.write(File.join(tool_root, 'version.txt'), 'fixture 6.1.1.280')
    @archive = File.join(@root, 'tools.zip')
    _out, err, status = Open3.capture3('/usr/bin/zip', '-qr', @archive, 'command-line-tools', chdir: package_root)
    raise err unless status.success?
    @curl_calls = File.join(@root, 'curl.jsonl')
    downloader = File.join(@root, 'curl-fixture')
    File.write(downloader, <<~'RUBY')
      #!/usr/bin/ruby
      require 'json'
      require 'fileutils'
      File.open(ENV.fetch('HS_TEST_CURL_CALLS'), 'a') { |file| file.puts(JSON.generate(ARGV)) }
      exit ENV['HS_TEST_CURL_EXIT'].to_i if ENV['HS_TEST_CURL_EXIT']
      FileUtils.cp(ENV.fetch('HS_TEST_ARCHIVE'), ARGV.fetch(ARGV.index('--output') + 1))
    RUBY
    File.chmod(0o700, downloader)
    @script = File.join(@root, 'CreateHarmonySimulator.zsh')
    source = File.read(SCRIPT).gsub('/usr/bin/uname', uname).gsub('/usr/sbin/sysctl', sysctl).gsub('/usr/bin/open', opener).gsub('in /Applications/DevEco', 'in ' + File.join(@root, 'SystemApps/DevEco'))
    source = source.gsub('/usr/bin/curl', downloader).sub(/^HS_CLT_SIZE=\d+$/, "HS_CLT_SIZE=#{File.size(@archive)}")
                   .sub(/^HS_CLT_SHA256="[^"]+"$/, "HS_CLT_SHA256=\"#{Digest::SHA256.file(@archive).hexdigest}\"")
    File.write(@script, source)
    @library = File.join(@root, 'Library.zsh')
    File.write(@library, source.sub(/^main "\$@"\s*\z/, ''))
    @env = {
      'HOME' => @root, 'TMPDIR' => @run, 'PATH' => '/usr/bin:/bin', 'NO_COLOR' => '1', 'TERM' => 'dumb',
      'HARMONY_EMULATOR_BIN' => @bin, 'DEVECO_STUDIO_HOME' => nil, 'TOOL_HOME' => nil,
      'HARMONY_CLT_ARCHIVE' => nil, 'HS_TEST_ARCHIVE' => @archive, 'HS_TEST_CURL_CALLS' => @curl_calls,
      'HS_TEST_IMAGES' => @images, 'HS_TEST_AVAILABLE' => @available, 'HS_TEST_INSTANCES' => @instances, 'HS_TEST_CALLS' => @calls,
      'HS_TEST_LICENSE' => File.join(@root, 'license-response')
    }
    @env['HS_TEST_OPEN_CALLS'] = @open_calls
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def image(type, downloaded: 'true', release: 'Release')
    { 'SoftWareVersion' => '6.0.0.112', 'deviceType' => type, 'downloaded' => downloaded,
      'osVersion' => 'HarmonyOS 6.0.1(21)', 'releaseType' => release, 'upgradable' => 'false' }
  end

  def calls
    File.file?(@calls) ? File.readlines(@calls).map { |line| JSON.parse(line) } : []
  end

  def invoke(*args, env: {}, input: '')
    Open3.capture3(@env.merge(env), '/bin/zsh', '-f', @script, *args, stdin_data: input, chdir: @root)
  end

  def shell(body, env: {})
    Open3.capture3(@env.merge(env), '/bin/zsh', '-f', '-c', "source #{@library.shellescape}\nsetopt NO_NOMATCH PIPE_FAIL\n" + body, chdir: @root)
  end

  def interactive(*args, env: {}, input: "\n\n\n\n")
    output = +''
    result = nil
    child_pid = nil
    Timeout.timeout(25) do
      PTY.spawn(@env.merge(env), '/bin/zsh', '-f', @script, *args) do |reader, writer, pid|
        child_pid = pid
        writer.write(input)
        begin
          loop { output << reader.readpartial(4096) }
        rescue EOFError, Errno::EIO
          # macOS PTY 在 slave 结束后返回 EIO。
        end
        Process.wait(pid)
        result = $?
      end
    end
    [output.force_encoding('UTF-8').scrub, result]
  rescue Timeout::Error
    Process.kill('TERM', child_pid) if child_pid
    raise "Fixture timed out: #{output}"
  end

  def test_help_is_readonly_and_names_do_not_execute_shell
    out, err, result = invoke('--help')
    assert result.success?, out + err
    assert_includes out, '--check'
    assert_empty calls
    assert_empty Dir.children(@run)
    refute_includes out, "\e["
  end

  def install_sdk_fixture
    sdk = File.join(@root, 'sdk')
    hdc = File.join(sdk, 'default/openharmony/toolchains/hdc')
    FileUtils.mkdir_p(File.dirname(hdc))
    File.write(hdc, "#!/bin/sh\nexit 0\n")
    File.chmod(0o700, hdc)
    sdk
  end

  def test_clt_creation_binds_bundled_sdk_only_to_new_instance
    sdk = install_sdk_fixture
    existing = File.join(@root, 'deployed', 'Existing')
    FileUtils.mkdir_p(existing)
    original = "name=Existing\nsdkPath=/other/sdk\nhw.ramSize=8192\n"
    File.write(File.join(existing, 'config.ini'), original)
    File.write(@instances, JSON.generate([{ name: 'Existing', instancePath: existing }]))
    out, result = interactive('--name', 'TestSdk', '--no-start')
    assert result.success?, out
    assert_equal "name=TestSdk\nhw.ramSize=4096\nsdkPath=#{sdk}\n", File.read(File.join(@root, 'deployed/TestSdk/config.ini'))
    assert_equal original, File.read(File.join(existing, 'config.ini'))
    assert_includes out, '已为新实例配置 CLT SDK'
    refute calls.any? { |call| call.first == '-start' }
  end

  def test_clt_preserves_native_sdk_setting
    install_sdk_fixture
    out, result = interactive('--name', 'TestSdk', '--no-start', env: { 'HS_TEST_SDK_CONFIG' => "sdkPath=/native/sdk\n" })
    assert result.success?, out
    assert_equal "name=TestSdk\nhw.ramSize=4096\nsdkPath=/native/sdk\n", File.read(File.join(@root, 'deployed/TestSdk/config.ini'))
  end

  def test_clt_replaces_empty_legacy_sdk_field
    sdk = install_sdk_fixture
    out, result = interactive('--name', 'TestSdk', '--no-start', env: { 'HS_TEST_SDK_CONFIG' => "harmonyos.sdk.path=\nsdkPath=\n" })
    assert result.success?, out
    assert_equal "name=TestSdk\nhw.ramSize=4096\nsdkPath=#{sdk}\n", File.read(File.join(@root, 'deployed/TestSdk/config.ini'))
  end

  def test_check_with_clt_sdk_is_still_readonly
    install_sdk_fixture
    out, err, result = invoke('--check')
    assert result.success?, out + err
    refute File.exist?(File.join(@root, 'deployed'))
    assert_empty Dir.children(@run)
  end

  def test_check_calls_only_readonly_official_commands_and_filters_images
    out, err, result = invoke('--check')
    assert result.success?, out + err
    assert_equal [['-help'], ['-imageList', '-downloaded', 'true'], ['-list', '-details']], calls
    assert_includes out, 'Release 镜像：2'
    assert_includes out, '未创建、启动或下载'
    assert_empty Dir.children(@run)
  end

  def test_noninteractive_create_stops_before_tool_calls
    out, err, result = invoke('--create', input: "\n")
    refute result.success?, out + err
    assert_includes err, '可交互终端'
    assert_empty calls
    assert_empty Dir.children(@run)
  end

  def test_intel_mac_stops_before_emulator_calls
    out, err, result = invoke('--check', env: { 'HS_TEST_ARCH' => 'x86_64' })
    refute result.success?, out + err
    assert_includes err, 'Intel Mac 不支持'
    assert_empty calls
  end

  def test_rosetta_prompt_requests_a_native_terminal_instead_of_rejecting_apple_silicon
    out, err, result = invoke('--check', env: { 'HS_TEST_ARCH' => 'x86_64', 'HS_TEST_TRANSLATED' => '1' })
    refute result.success?, out + err
    assert_includes err, 'Rosetta'
    refute_includes err, 'Intel Mac 不支持'
    assert_empty calls
  end

  def test_explicit_bad_binary_or_sdk_does_not_fall_back
    [{ 'HARMONY_EMULATOR_BIN' => File.join(@root, 'missing') },
     { 'HARMONY_EMULATOR_BIN' => nil, 'DEVECO_STUDIO_HOME' => File.join(@root, 'missing-app') }].each do |env|
      out, err, result = invoke('--check', env: env)
      refute result.success?, out + err
      assert_empty calls
    end
  end

  def test_explicit_deveco_and_clt_layouts_resolve_their_own_tool
    ['Contents/tools/emulator/Emulator', 'emulator/Emulator'].each do |relative|
      root = File.join(@root, relative.start_with?('Contents') ? 'DevEco.app' : 'CLT')
      path = File.join(root, relative)
      FileUtils.mkdir_p(File.dirname(path))
      FileUtils.cp(@bin, path)
      out, err, result = invoke('--check', env: { 'HARMONY_EMULATOR_BIN' => nil, 'DEVECO_STUDIO_HOME' => root })
      assert result.success?, out + err
      assert_includes out, path
    end
  end

  def test_android_emulator_help_and_unhealthy_help_are_rejected
    [{ 'HS_TEST_HELP' => '-avd -list-avds' }, { 'HS_TEST_HELP' => '-create' }, { 'HS_TEST_HELP_EXIT' => '31' }].each do |env|
      FileUtils.rm_f(@calls)
      out, err, result = invoke('--check', env: env)
      refute result.success?, out + err
      assert_equal [['-help']], calls
      refute_includes out, '已确认官方兼容工具能力'
    end
  end

  def install_candidate(relative, help: nil)
    candidate = File.join(@root, relative)
    FileUtils.mkdir_p(File.dirname(candidate))
    if help
      File.write(candidate, "#!/bin/zsh\nprint -r -- #{help.shellescape}\n")
      File.chmod(0o700, candidate)
    else
      FileUtils.cp(@bin, candidate)
    end
    candidate
  end

  def test_android_in_path_cannot_hide_a_compatible_deveco_app
    install_candidate('android/Emulator', help: '-avd -list-avds')
    official = install_candidate('SystemApps/DevEco Studio.app/Contents/tools/emulator/Emulator')
    out, err, result = invoke('--check', env: { 'HARMONY_EMULATOR_BIN' => nil, 'PATH' => "#{@root}/android:/usr/bin:/bin" })
    assert result.success?, out + err
    assert_includes out, '已排除不兼容候选'
    assert_includes out, "已确认官方兼容工具能力：#{official}"
    assert_equal [['-help'], ['-imageList', '-downloaded', 'true'], ['-list', '-details']], calls
  end

  def test_later_path_entries_are_checked_and_duplicates_are_deduplicated
    install_candidate('android/Emulator', help: '-avd -list-avds')
    official = install_candidate('official/Emulator')
    out, err, result = invoke('--check', env: { 'HARMONY_EMULATOR_BIN' => nil, 'PATH' => "#{@root}/android:#{@root}/official:#{@root}/official:/usr/bin:/bin" })
    assert result.success?, out + err
    assert_includes out, "已确认官方兼容工具能力：#{official}"
    assert_equal 1, calls.count { |call| call == ['-help'] }
  end

  def test_only_android_installs_sdl_tools_and_saves_early_diagnostics
    install_candidate('android/Emulator', help: '-avd -list-avds')
    out, result = interactive('--prepare', env: { 'HARMONY_EMULATOR_BIN' => nil, 'PATH' => "#{@root}/android:/usr/bin:/bin" }, input: "\n")
    assert result.success?, out
    assert_includes out, '未找到支持新建 Harmony 模拟器的 DevEco Emulator'
    assert_includes out, 'HARMONY_EMULATOR_BIN'
    logs = Dir.glob(File.join(@run, 'JobsHarmonySimulator.*', 'CreateHarmonySimulator.log'))
    assert_equal 1, logs.length
    assert_includes File.read(logs.first), '已排除不兼容候选'
    assert_includes out, 'SDL 工具依赖已安装并通过能力复检'
    assert_includes out, '--prepare 已完成'
    assert File.file?(@curl_calls)
    refute File.exist?(@open_calls)
  end

  def test_prepare_healthy_does_not_create_start_or_open_anything
    out, result = interactive('--prepare', input: "\n")
    assert result.success?, out
    assert_includes out, '--prepare 已完成'
    assert_equal [['-help'], ['-imageList', '-downloaded', 'true'], ['-list', '-details']], calls
    refute File.exist?(@open_calls)
  end

  def test_prepare_accepts_a_literal_tool_path_without_executing_shell_content
    out, result = interactive('--prepare', env: { 'HARMONY_EMULATOR_BIN' => File.join(@root, 'missing') },
                              input: "\n2\n#{@bin.shellescape}\n")
    assert result.success?, out
    assert_includes out, '--prepare 已完成'
    refute File.exist?(File.join(@root, 'INJECTED'))
    refute File.exist?(File.join(@root, 'BACKTICK'))
    refute File.exist?(@open_calls)
  end

  def test_download_handoff_keeps_terminal_and_rechecks_newly_installed_app
    installed = File.join(@root, 'SystemApps/DevEco Studio.app/Contents/tools/emulator/Emulator')
    out, result = interactive('--prepare', env: { 'HARMONY_EMULATOR_BIN' => nil, 'DEVECO_STUDIO_HOME' => installed.split('/Contents/').first,
                                                'HS_TEST_INSTALL_FROM' => @bin, 'HS_TEST_INSTALL_TO' => installed }, input: "\n3\n\n")
    assert result.success?, out
    assert_includes out, '终端保留在此'
    assert_includes out, '--prepare 已完成'
    assert_equal [["https://developer.huawei.com/consumer/cn/download/"]], File.readlines(@open_calls).map { |line| JSON.parse(line) }
    assert_empty calls.select { |call| %w[-create -start -install].include?(call.first) }
  end

  def test_enter_only_downloads_default_phone_reviews_license_and_continues_creation
    File.write(@images, '[]')
    out, result = interactive('--name', 'PreparedPhone', '--no-start', input: "\n" * 5)
    assert result.success?, out
    assert_includes out, '已验证新建实例：PreparedPhone'
    assert_includes out, 'Official agreement fixture'
    assert_includes calls, ['-license', 'accept']
    assert_includes calls, ['-install', '-deviceType', 'phone', '-osVersion', 'HarmonyOS 6.0.1(21)', '-force']
    assert_operator calls.index(['-license', 'accept']), :<, calls.index(calls.find { |call| call.first == '-install' })
    refute File.exist?(@open_calls)
    assert_equal 3, calls.count { |call| call.first == '-imageList' }
  end

  def test_image_install_failure_or_zero_exit_without_image_never_creates_or_loops
    [{ 'HS_TEST_INSTALL_EXIT' => '42' }, { 'HS_TEST_DONT_INSTALL' => '1' }, { 'HS_TEST_LICENSE_EXIT' => '43' }].each do |env|
      File.write(@images, '[]')
      FileUtils.rm_f(@calls)
      out, result = interactive('--no-start', env: env, input: "\n" * 4)
      refute result.success?, out
      assert_operator calls.count { |call| call.first == '-install' }, :<=, 1
      assert_empty calls.select { |call| %w[-create -start].include?(call.first) }
    end
  end

  def test_download_and_license_cancellation_never_installs
    ["\nq\n", "\n\nq\n", "\n\n\nq\n"].each do |input|
      File.write(@images, '[]')
      FileUtils.rm_f(@calls)
      out, result = interactive('--prepare', input: input)
      assert result.success?, out
      assert_empty calls.select { |call| %w[-license -install -create -start].include?(call.first) }
    end
  end

  def test_online_image_options_and_invalid_selector_cannot_become_commands
    records = [image('phone', downloaded: 'false').merge('osVersion' => '-delete')]
    out, err, result = shell("hs_json available #{JSON.generate(records).shellescape}")
    refute result.success?, out + err
    assert_includes err, 'Invalid osVersion'
    out, err, result = shell("HS_BIN=#{@bin.shellescape}; hs_choose() { print -r -- evil; }; hs_install_image")
    assert_equal 2, result.exitstatus, out + err
    assert_empty calls.select { |call| %w[-license -install -create -delete].include?(call.first) }
  end

  def test_available_catalog_prefers_phone_and_numeric_newest_version_and_supports_2in1
    records = [image('2in1 Foldable', downloaded: 'false'), image('phone', downloaded: 'false'),
               image('phone', downloaded: 'false').merge('osVersion' => 'HarmonyOS 6.10.0(30)'),
               image('phone', downloaded: 'false').merge('osVersion' => 'HarmonyOS 6.9.0(29)'),
               image('phone', downloaded: 'false', release: 'Beta')]
    out, err, result = shell("hs_json available #{JSON.generate(records).shellescape}")
    assert result.success?, out + err
    assert_includes out.lines.first, 'HarmonyOS 6.10.0(30)'
    assert_includes out, '2in1 Foldable'
    assert_equal 4, out.lines.length
  end

  def test_failed_browser_open_and_bad_path_leave_recovery_available
    out, result = interactive('--prepare', env: { 'HARMONY_EMULATOR_BIN' => File.join(@root, 'missing'), 'HS_TEST_OPEN_EXIT' => '9' },
                              input: "\n3\n2\n/does-not-exist\nq\n")
    assert result.success?, out
    assert_includes out, '自动打开失败'
    assert_includes out, '路径不存在'
    assert_includes out, '已取消环境准备'
    assert_empty calls
  end

  def test_check_never_enters_preparation_or_opens_a_browser
    out, err, result = invoke('--check', env: { 'HARMONY_EMULATOR_BIN' => File.join(@root, 'missing') })
    refute result.success?, out + err
    refute_includes out, 'Harmony 环境准备'
    refute File.exist?(@open_calls)
    assert_empty Dir.children(@run)
    out, err, result = invoke('--check', '--prepare')
    assert_equal 2, result.exitstatus, out + err
  end

  def installed_tools
    Dir.glob(File.join(@root, 'Library/Application Support/JobsHarmonySimulator/clt-*'))
  end

  def test_sdl_install_is_reused_without_network_and_preserves_existing_versions
    out, result = interactive('--prepare', env: { 'HARMONY_EMULATOR_BIN' => nil }, input: "\n")
    assert result.success?, out
    assert_equal 1, installed_tools.length
    download = JSON.parse(File.readlines(@curl_calls).first)
    assert_equal 'https://libsdl.org/harmonyos-devtools/commandline-tools-mac-arm64-6.1.1.280.zip', download.last
    assert_includes download, '=https'
    original = installed_tools.first
    FileUtils.rm_f(@curl_calls)
    out, err, result = invoke('--check', env: { 'HARMONY_EMULATOR_BIN' => nil })
    assert result.success?, out + err
    assert_includes out, original
    refute File.exist?(@curl_calls)
    assert_equal [original], installed_tools
    assert_empty Dir.glob(File.join(File.dirname(original), '.install.*'))
  end

  def test_sdl_local_archive_is_validated_without_download
    out, result = interactive('--prepare', env: { 'HARMONY_EMULATOR_BIN' => nil, 'HARMONY_CLT_ARCHIVE' => @archive }, input: "\n")
    assert result.success?, out
    assert_equal 1, installed_tools.length
    refute File.exist?(@curl_calls)
    assert File.exist?(@archive)
  end

  def test_sdl_corrupt_archive_never_extracts_or_executes_and_cleans_stage
    [File.binread(@archive)[0...-1], File.binread(@archive).sub('PK', 'XX')].each do |bad|
      invalid = File.join(@root, 'bad.zip')
      File.binwrite(invalid, bad)
      out, result = interactive('--prepare', env: { 'HARMONY_EMULATOR_BIN' => nil, 'HARMONY_CLT_ARCHIVE' => invalid }, input: "\n")
      refute result.success?, out
      assert_match(/大小不符|SHA-256 不符/, out)
      assert_empty installed_tools
      assert_empty calls
      assert_empty Dir.glob(File.join(@root, 'Library/Application Support/JobsHarmonySimulator/.install.*'))
      assert File.exist?(invalid)
    end
  end

  def test_sdl_download_failure_stops_and_does_not_open_login_page
    out, result = interactive('--prepare', env: { 'HARMONY_EMULATOR_BIN' => nil, 'HS_TEST_CURL_EXIT' => '28' }, input: "\n")
    refute result.success?, out
    assert_includes out, 'SDL 下载失败'
    assert_empty installed_tools
    assert_empty calls
    refute File.exist?(@open_calls)
  end

  def test_missing_tools_check_is_readonly_and_explicit_bad_path_requires_choice
    out, err, result = invoke('--check', env: { 'HARMONY_EMULATOR_BIN' => nil })
    refute result.success?, out + err
    refute File.exist?(@curl_calls)
    assert_empty installed_tools
    out, result = interactive('--prepare', env: { 'HARMONY_EMULATOR_BIN' => '/missing' }, input: "\nq\n")
    assert result.success?, out
    assert_includes out, '已取消环境准备'
    refute File.exist?(@curl_calls)
  end

  def test_initial_cancel_never_installs_or_creates_logs
    out, result = interactive('--prepare', env: { 'HARMONY_EMULATOR_BIN' => nil }, input: "q\n")
    assert result.success?, out
    assert_includes out, '未安装工具或创建模拟器'
    assert_empty calls
    assert_empty Dir.children(@run)
    refute File.exist?(@curl_calls)
  end

  def test_sdl_incompatible_tool_is_not_published
    out, result = interactive('--prepare', env: { 'HARMONY_EMULATOR_BIN' => nil, 'HS_TEST_HELP' => '-list -start' }, input: "\n")
    refute result.success?, out
    assert_empty installed_tools
    refute_includes out, 'SDL 工具依赖已安装'
  end

  def test_sdl_publish_never_overwrites_or_nests_into_existing_directory
    source = File.join(@root, 'publish-source')
    target = File.join(@root, 'publish-target')
    FileUtils.mkdir_p([source, target])
    File.write(File.join(target, 'keep'), 'existing')
    out, err, result = shell("hs_publish_clt #{source.shellescape} #{target.shellescape}")
    refute result.success?, out + err
    assert_equal ['keep'], Dir.children(target)
    assert Dir.exist?(source)
  end

  def test_incompatible_app_does_not_count_toward_ambiguity
    install_candidate('SystemApps/DevEco Old.app/Contents/tools/emulator/Emulator', help: '-list -start')
    official = install_candidate('SystemApps/DevEco New.app/Contents/tools/emulator/Emulator')
    out, err, result = invoke('--check', env: { 'HARMONY_EMULATOR_BIN' => nil })
    assert result.success?, out + err
    assert_includes out, "已确认官方兼容工具能力：#{official}"
  end

  def test_two_compatible_installations_require_an_explicit_choice
    paths = %w[One Two].map { |name| install_candidate("SystemApps/DevEco #{name}.app/Contents/tools/emulator/Emulator") }
    out, err, result = invoke('--check', env: { 'HARMONY_EMULATOR_BIN' => nil })
    refute result.success?, out + err
    assert_includes err, '2 个兼容'
    paths.each { |candidate| assert_includes out, candidate }
    assert_equal [['-help'], ['-help']], calls
    assert_empty Dir.children(@run)
  end

  def test_explicit_incompatible_emulator_never_falls_back_to_a_good_app
    install_candidate('SystemApps/DevEco Studio.app/Contents/tools/emulator/Emulator')
    bad = install_candidate('android/Emulator', help: '-avd -list-avds')
    out, err, result = invoke('--check', env: { 'HARMONY_EMULATOR_BIN' => bad })
    refute result.success?, out + err
    assert_empty calls
  end

  def test_similar_option_names_are_not_creation_capabilities
    out, err, result = invoke('--check', env: { 'HS_TEST_HELP' => '-createSnapshot -imageListCached' })
    refute result.success?, out + err
    assert_equal [['-help']], calls
  end

  def test_real_emulator_help_accepts_brackets_and_colon_delimiters
    ['Emulator [-create <name>] [-imageList [-downloaded <true/false>]]', "-create: Create a new emulator\n-imageList: List available images"].each do |help|
      out, err, result = invoke('--check', env: { 'HS_TEST_HELP' => help })
      assert result.success?, out + err
      assert_includes out, '只读检查完成'
    end
  end

  def test_real_emulator_empty_responses_are_readonly_empty_lists
    out, err, result = invoke('--check', env: { 'HS_TEST_NATIVE_EMPTY' => '1' })
    assert result.success?, out + err
    assert_includes out, 'Release 镜像：0；已有实例：0'
    assert_empty Dir.children(@run)
    out, result = interactive('--prepare', env: { 'HS_TEST_NATIVE_EMPTY' => '1' }, input: "\n")
    refute result.success?, out
    assert_includes out, '官方没有返回可下载'
    out, err, result = invoke('--check', env: { 'HS_TEST_NATIVE_EMPTY' => '1', 'HS_TEST_IMAGES_EXIT' => '24' })
    assert_equal 24, result.exitstatus, out + err
  end

  def test_invalid_images_and_instance_containers_fail_without_mutations
    [['images', '{"rows":[]}'], ['instances', '{"rows":[]}'], ['images', 'not-json']].each do |kind, contents|
      path = kind == 'images' ? @images : @instances
      snapshot = File.read(path)
      File.write(path, contents)
      out, err, result = invoke('--check')
      refute result.success?, out + err
      assert_empty calls.select { |call| %w[-create -start -install -delete].include?(call.first) }
      assert_empty Dir.children(@run)
      File.write(path, snapshot)
    end
  end

  def test_single_instance_object_and_object_prototype_names_are_valid
    ['__proto__', 'constructor', 'toString'].each do |name|
      File.write(@instances, JSON.generate({ name: name, deviceType: 'phone', os: { osVersion: 'HarmonyOS 6.0.1(21)' } }))
      out, err, result = invoke('--check')
      assert result.success?, out + err
      assert_includes out, '已有实例：1'
    end
  end

  def test_duplicate_instance_names_or_control_characters_are_rejected
    [[{ name: 'same' }, { name: 'same' }], [{ name: "line\nbreak" }]].each do |records|
      File.write(@instances, JSON.generate(records))
      out, err, result = invoke('--check')
      refute result.success?, out + err
      assert_empty calls.select { |call| call.first == '-create' }
    end
  end

  def test_flat_and_nested_os_version_fields_are_supported_but_conflicts_stop
    records = [
      { name: 'Flat', deviceType: 'phone', 'os.osVersion' => 'HarmonyOS 6.0.1(21)' },
      { name: 'Flat', deviceType: 'phone', 'os.osVersion' => 'HarmonyOS 6.0.1(21)', os: { osVersion: 'HarmonyOS 6.0.1(21)' } }
    ]
    records.each do |record|
      body = "hs_json verify #{JSON.generate(record).shellescape} Flat phone #{'HarmonyOS 6.0.1(21)'.shellescape}"
      out, err, result = shell(body)
      assert result.success?, out + err
      assert_equal 'Flat', out.strip
    end
    records.last[:os][:osVersion] = 'conflict'
    out, err, result = shell("hs_json verify #{JSON.generate(records.last).shellescape} Flat phone #{'HarmonyOS 6.0.1(21)'.shellescape}")
    refute result.success?, out + err
    assert_includes err, 'Conflicting'
  end

  def test_missing_images_can_cancel_download_selection
    File.write(@images, JSON.generate([image('phone', downloaded: 'false'), image('tablet', release: 'Beta')]))
    out, result = interactive('--create', '--no-start', input: "\nq\n")
    assert result.success?, out
    assert_includes out, '下载系统镜像'
    assert_includes out, '已取消环境准备'
    assert_empty calls.select { |call| %w[-create -start -install].include?(call.first) }
  end

  def test_numbered_selection_creates_and_verifies_an_exact_unique_name
    out, result = interactive('--create', '--name', 'JobsPhone', '--no-start')
    assert result.success?, out
    assert_includes out, '已验证新建实例：JobsPhone'
    assert_includes calls, ['-create', 'JobsPhone', '-deviceType', 'phone', '-osVersion', 'HarmonyOS 6.0.1(21)']
    assert_equal 3, calls.count { |call| call == ['-list', '-details'] }
    assert_empty calls.select { |call| %w[-start -install -delete -config].include?(call.first) }
    refute File.exist?(File.join(@root, 'INJECTED'))
    refute File.exist?(File.join(@root, 'BACKTICK'))
  end

  def test_default_name_is_generated_and_verified
    out, result = interactive('--create', '--no-start', input: "\n\n\n\n\n")
    assert result.success?, out
    assert_match(/已验证新建实例：JobsHarmony_phone_\d{8}_\d{6}/, out)
    assert_equal 1, calls.count { |call| call.first == '-create' }
  end

  def test_name_policy_rejects_native_invalid_names_before_querying_or_creating
    ['JobsHarmony-phone', ' phone', 'phone ', "phone\n", 'a' * 65, 'phone/escape', 'phone;touch BAD'].each do |name|
      out, err, result = invoke('--check', '--name', name)
      assert_equal 2, result.exitstatus, out + err
      assert_empty calls
    end
    ['JobsHarmony_phone', 'Phone + 1', 'P' * 64].each do |name|
      out, err, result = shell("hs_valid_name #{name.shellescape}")
      assert result.success?, out + err
    end
  end

  def test_default_name_sanitizes_device_type_and_collision_suffix
    File.write(@images, JSON.generate([image('2in1 Foldable')]))
    out, result = interactive('--no-start', input: "\n" * 5)
    assert result.success?, out
    name = calls.find { |call| call.first == '-create' }[1]
    assert_match(/\AJobsHarmony_2in1_Foldable_\d{8}_\d{6}\z/, name)
    source = File.read(@library).gsub('$(/bin/date +%Y%m%d_%H%M%S)', '20261023_123456')
    File.write(@library, source)
    out, err, result = shell("HS_ROWS=($'phone\\tHarmonyOS 6.0.1(21)\\t6.0.0.112'); HS_NAMES=(JobsHarmony_phone_20261023_123456); hs_choose() { print -r -- \"$2\"; }; hs_select_image <<< ''; print -r -- \"$HS_NAME\"")
    assert result.success?, out + err
    assert_includes out, 'JobsHarmony_phone_20261023_123456_1'
  end

  def test_healthy_fzf_uses_the_first_rows_without_inheriting_user_filters
    fzf = File.join(@root, 'fzf')
    File.write(fzf, <<~'ZSH')
      #!/bin/zsh
      [[ "$1" != --version ]] || { print -r -- 'fixture fzf'; exit 0; }
      [[ -z "${FZF_DEFAULT_OPTS+x}${FZF_DEFAULT_COMMAND+x}${FZF_DEFAULT_OPTS_FILE+x}" ]] || exit 45
      IFS= read -r first
      print -r -- "$first"
    ZSH
    File.chmod(0o700, fzf)
    out, result = interactive('--name', 'Fzf', '--no-start', input: "\n\n",
                              env: { 'PATH' => "#{@root}:/usr/bin:/bin", 'FZF_DEFAULT_OPTS' => '--filter=bad', 'FZF_DEFAULT_COMMAND' => 'touch BAD', 'FZF_DEFAULT_OPTS_FILE' => '/bad' })
    assert result.success?, out
    assert_includes out, '已验证新建实例：Fzf'
    refute File.exist?(File.join(@root, 'BAD'))
  end

  def test_existing_name_is_preserved_and_never_created_again
    original = JSON.generate([{ name: 'Keep', deviceType: 'phone', os: { osVersion: 'HarmonyOS 6.0.1(21)' } }])
    File.write(@instances, original)
    out, result = interactive('--name', 'Keep', '--no-start')
    refute result.success?, out
    assert_includes out, '不会覆盖'
    assert_equal original, File.read(@instances)
    assert_empty calls.select { |call| call.first == '-create' }
  end

  def test_case_insensitive_existing_name_is_never_overwritten
    File.write(@instances, JSON.generate([{ name: 'Keep', deviceType: 'phone', os: { osVersion: 'HarmonyOS 6.0.1(21)' } }]))
    out, result = interactive('--name', 'keep', '--no-start')
    refute result.success?, out
    assert_includes out, '不会覆盖'
    assert_empty calls.select { |call| call.first == '-create' }
  end

  def test_confirmation_time_race_is_rechecked_before_create
    out, result = interactive('--name', 'Race', '--no-start', env: { 'HS_TEST_RACE' => 'rACE' })
    refute result.success?, out
    assert_includes out, '名称已被其它操作使用'
    assert_empty calls.select { |call| call.first == '-create' }
    assert_equal 'rACE', JSON.parse(File.read(@instances)).first['name']
  end

  def test_failed_readonly_queries_preserve_failure_codes
    [{ 'HS_TEST_IMAGES_EXIT' => '24' }, { 'HS_TEST_LIST_EXIT' => '25' }].each do |env|
      FileUtils.rm_f(@calls)
      out, err, result = invoke('--check', env: env)
      assert_equal env.values.first.to_i, result.exitstatus, out + err
      assert_empty calls.select { |call| %w[-create -start -install].include?(call.first) }
      assert_empty Dir.children(@run)
    end
  end

  def test_canceling_create_keeps_all_existing_state
    out, result = interactive('--name', 'Cancel', '--no-start', input: "\n\n\nx\n")
    assert result.success?, out
    assert_includes out, '已取消'
    assert_equal '[]', File.read(@instances)
    assert_empty calls.select { |call| call.first == '-create' }
  end

  def test_creation_failure_and_missing_or_mismatched_verification_stop_start
    [{ 'HS_TEST_CREATE_EXIT' => '49' }, { 'HS_TEST_DONT_CREATE' => '1' }, { 'HS_TEST_WRONG_VERSION' => 'other' }].each do |env|
      FileUtils.rm_f(@calls)
      File.write(@instances, '[]')
      out, result = interactive('--name', 'CheckMe', env: env)
      refute result.success?, out
      assert_equal 49, result.exitstatus if env['HS_TEST_CREATE_EXIT']
      refute_includes out, '已验证新建实例'
      assert_empty calls.select { |call| call.first == '-start' || call.first == '-delete' }
    end
  end

  def test_start_keeps_the_official_license_prompt_and_failure_code
    out, result = interactive('--name', 'License', env: { 'HS_TEST_START_EXIT' => '17' }, input: "\n\n\n\n\nn\n")
    assert_equal 17, result.exitstatus, out
    assert_equal 'n', File.read(@env['HS_TEST_LICENSE'])
    assert_includes calls, ['-start', 'License']
    refute calls.flatten.include?('-force')
    assert_includes out, '已验证新建实例：License'
  end

  def test_control_names_and_unknown_parameters_are_readonly_errors
    [['--name'], ['--unknown'], ['--name', "bad\nname"], ['--name', '-force'], ['--name', '../escape']].each do |args|
      out, err, result = invoke('--check', *args)
      assert_equal 2, result.exitstatus, out + err
      assert_empty calls
      assert_empty Dir.children(@run)
    end
  end

  def test_selected_rows_are_exact_members_even_with_a_hostile_fzf
    out, err, result = shell("hs_choose() { print -r -- evil; }; HS_ROWS=($'phone\\tHarmonyOS 6.0.1(21)\\t6.0.0.112'); hs_select_image")
    assert_equal 2, result.exitstatus, out + err
    assert_includes err, '无效设备类型'
    assert_empty calls
  end
end
