# frozen_string_literal: true
# Created by Jobs on 2026年10月23日，星期五。
# 用假 Emulator 与真实 zsh / JXA 验证官方命令契约，不下载、安装或操作真实模拟器。

require 'fileutils'
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
    @calls = File.join(@root, 'calls.jsonl')
    File.write(@images, JSON.generate([image('phone'), image('tablet'), image('watch', downloaded: 'false'), image('tv', release: 'Beta')]))
    File.write(@instances, '[]')
    File.write(@bin, <<~'RUBY')
      #!/usr/bin/ruby
      require 'json'
      File.open(ENV.fetch('HS_TEST_CALLS'), 'a') { |file| file.puts(JSON.generate(ARGV)) }
      command = ARGV.first
      case command
      when '-help'
        puts ENV.fetch('HS_TEST_HELP', '-help -create -imageList -list -details -start')
        exit ENV.fetch('HS_TEST_HELP_EXIT', '0').to_i
      when '-imageList'
        puts File.read(ENV.fetch('HS_TEST_IMAGES'))
        exit ENV.fetch('HS_TEST_IMAGES_EXIT', '0').to_i
      when '-list'
        if ENV['HS_TEST_RACE'] && File.readlines(ENV.fetch('HS_TEST_CALLS')).count { |line| JSON.parse(line).first == '-list' } == 2
          File.write(ENV.fetch('HS_TEST_INSTANCES'), JSON.generate([{ name: ENV['HS_TEST_RACE'], deviceType: 'phone', os: { osVersion: 'HarmonyOS 6.0.1(21)' } }]))
        end
        puts File.read(ENV.fetch('HS_TEST_INSTANCES'))
        exit ENV.fetch('HS_TEST_LIST_EXIT', '0').to_i
      when '-create'
        exit ENV['HS_TEST_CREATE_EXIT'].to_i if ENV['HS_TEST_CREATE_EXIT']
        unless ENV['HS_TEST_DONT_CREATE'] == '1'
          records = JSON.parse(File.read(ENV.fetch('HS_TEST_INSTANCES')))
          records = [records] unless records.is_a?(Array)
          records << { 'name' => ARGV[1], 'deviceType' => ARGV[ARGV.index('-deviceType') + 1],
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
    @script = File.join(@root, 'CreateHarmonySimulator.zsh')
    source = File.read(SCRIPT).gsub('/usr/bin/uname', uname).gsub('/usr/sbin/sysctl', sysctl).gsub('/Applications/DevEco', File.join(@root, 'SystemApps/DevEco'))
    File.write(@script, source)
    @library = File.join(@root, 'Library.zsh')
    File.write(@library, source.sub(/^main "\$@"\s*\z/, ''))
    @env = {
      'HOME' => @root, 'TMPDIR' => @run, 'PATH' => '/usr/bin:/bin', 'NO_COLOR' => '1', 'TERM' => 'dumb',
      'HARMONY_EMULATOR_BIN' => @bin, 'DEVECO_STUDIO_HOME' => nil, 'TOOL_HOME' => nil,
      'HS_TEST_IMAGES' => @images, 'HS_TEST_INSTANCES' => @instances, 'HS_TEST_CALLS' => @calls,
      'HS_TEST_LICENSE' => File.join(@root, 'license-response')
    }
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

  def test_no_downloaded_release_images_directs_user_to_device_manager
    File.write(@images, JSON.generate([image('phone', downloaded: 'false'), image('tablet', release: 'Beta')]))
    out, result = interactive('--create', '--no-start')
    refute result.success?, out
    assert_includes out, 'Device Manager'
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
    assert_match(/已验证新建实例：JobsHarmony-phone-\d{8}-\d{6}/, out)
    assert_equal 1, calls.count { |call| call.first == '-create' }
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
    out, result = interactive('--name', 'License', env: { 'HS_TEST_START_EXIT' => '17' }, input: "\n\n\n\nn\n")
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
