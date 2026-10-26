# frozen_string_literal: true
# 假官方 CLI 与临时实例覆盖真实诊断 / 修复链，不操作用户模拟器或系统扩展。

require 'minitest/autorun'
require 'open3'
require 'tmpdir'
require 'fileutils'
require 'json'
require 'pty'
require 'timeout'

class RepairHarmonySimulatorTests < Minitest::Test
  ROOT = File.expand_path('..', __dir__)
  SCRIPT = File.join(ROOT, 'Scripts/RepairHarmonySimulator.zsh')

  def setup
    @root = File.realpath(Dir.mktmpdir('jobs-harmony-repair-'))
    @instance = File.join(@root, 'instances/JobsHarmony_Test')
    @sdk = File.join(@root, 'tools/sdk')
    @emulator = File.join(@root, 'tools/emulator/Emulator')
    @calls = File.join(@root, 'calls')
    FileUtils.mkdir_p([@instance, File.dirname(@emulator), File.join(@sdk, 'default/openharmony/toolchains')])
    File.write(config, "name=JobsHarmony_Test\nsdkPath=#{@sdk}\nkeep=value\n")
    File.write(File.join(@instance, 'userdata.img'), 'existing userdata')
    write_executable(@emulator, fake_emulator)
    write_executable(File.join(@sdk, 'default/openharmony/toolchains/hdc'), "#!/bin/zsh\n[[ \"$1\" == -v ]] && { print 'HDC 3.1'; exit 0; }\nexit 44\n")
    @uname = File.join(@root, 'uname')
    write_executable(@uname, "#!/bin/zsh\n[[ \"$1\" == -s ]] && print Darwin || print arm64\n")
    @ps = File.join(@root, 'ps')
    write_executable(@ps, "#!/bin/zsh\nprint -r -- \"${JOBS_TEST_PS:-/sbin/launchd}\"\n")
    source = File.read(SCRIPT).gsub('/usr/bin/uname', shell_word(@uname)).gsub('/bin/ps', shell_word(@ps))
    source = source.gsub('/bin/sleep 2', '/usr/bin/true')
    @script = File.join(@root, 'repair.zsh')
    File.write(@script, source)
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def test_check_is_read_only_and_accepts_official_bool_state
    before = File.binread(config)
    output, result = run_script('--check')
    assert result.success?, output
    assert_includes output, 'isRunning=false'
    assert_includes output, 'SDK / HDC 版本检测通过'
    refute_match(/-start|-stop|-delete|-config/, calls)
    assert_equal before, File.binread(config)
    assert_empty Dir.glob(File.join(@root, 'JobsHarmonySimulatorRepairer.*'))
    assert_empty backups
  end

  def test_unknown_state_rejects_all_operations
    output, result = run_script('--check', environment: { 'JOBS_TEST_UNKNOWN_STATE' => '1' })
    refute result.success?, output
    assert_includes output, '实例 JSON 结构未知'
    refute_match(/-start|-stop/, calls)
  end

  def test_duplicate_names_and_path_identity_fail_closed
    output, result = run_script('--check', environment: { 'JOBS_TEST_DUPLICATE' => '1' })
    refute result.success?, output
    File.write(config, "name=Another\nsdkPath=#{@sdk}\n")
    output, result = run_script('--check')
    refute result.success?, output
    assert_includes output, 'name 与官方清单不一致'
  end

  def test_empty_official_instance_list_is_diagnostic_failure
    output, result = run_script('--check', environment: { 'JOBS_TEST_EMPTY' => '1' })
    refute result.success?, output
    assert_includes output, '没有官方登记的本地实例'
    refute_match(/-start|-stop/, calls)
  end

  def test_noninteractive_and_unknown_flags_do_not_mutate_or_query
    output, result = run_script('--repair')
    refute result.success?, output
    assert_includes output, '可交互终端'
    assert_equal '', calls
    output, result = run_script('--check', '--yes')
    assert_equal 2, result.exitstatus
    assert_includes output, '未知参数'
    assert_equal '', calls
  end

  def test_explicit_bad_tool_never_falls_back
    output, result = run_script('--check', environment: { 'HARMONY_EMULATOR_BIN' => File.join(@root, 'missing') })
    refute result.success?, output
    assert_includes output, '不是可执行文件'
    assert_equal '', calls
  end

  def test_coldboot_stops_running_instance_then_checks_false_and_true
    output, result = run_script('--repair', '--name', 'JobsHarmony_Test', input: "\n2\nYES\n", interactive: true,
                                environment: { 'JOBS_TEST_RUNNING' => 'true' })
    assert result.success?, output
    assert_includes calls, '-stop|JobsHarmony_Test'
    assert_includes calls, '-start|JobsHarmony_Test|-bootMode|coldboot'
    assert_operator calls.index('-stop|'), :<, calls.index('-start|')
    assert_includes output, '已验证所选实例 isRunning=true'
    refute_includes calls, 'reset'
    assert_equal 'existing userdata', File.read(File.join(@instance, 'userdata.img'))
  end

  def test_stopped_instance_coldboot_does_not_issue_stop
    output, result = run_script('--repair', '--name', 'JobsHarmony_Test', input: "\n2\nYES\n", interactive: true)
    assert result.success?, output
    refute_includes calls, '-stop|'
    assert_includes calls, '-start|JobsHarmony_Test|-bootMode|coldboot'
  end

  def test_stop_failure_never_starts
    output, result = run_script('--repair', '--name', 'JobsHarmony_Test', input: "\n2\nYES\n", interactive: true,
                                environment: { 'JOBS_TEST_RUNNING' => 'true', 'JOBS_TEST_STOP_FAIL' => '1' })
    assert_equal 7, result.exitstatus
    assert_includes output, '未继续启动'
    refute_includes calls, '-start|'
  end

  def test_stop_readback_still_running_never_starts
    output, result = run_script('--repair', '--name', 'JobsHarmony_Test', input: "\n2\nYES\n", interactive: true,
                                environment: { 'JOBS_TEST_RUNNING' => 'true', 'JOBS_TEST_STOP_STUCK' => '1' })
    refute result.success?, output
    assert_includes output, 'isRunning=false'
    refute_includes calls, '-start|'
  end

  def test_unsupported_coldboot_does_not_stop_instance
    output, result = run_script('--repair', '--name', 'JobsHarmony_Test', input: "\n2\nYES\n", interactive: true,
                                environment: { 'JOBS_TEST_NO_BOOT_MODE' => '1', 'JOBS_TEST_RUNNING' => 'true' })
    refute result.success?, output
    refute_includes calls, '-stop|'
    refute_includes calls, '-start|'
  end

  def test_cancel_coldboot_never_starts_or_stops
    output, result = run_script('--repair', '--name', 'JobsHarmony_Test', input: "\n2\nno\n", interactive: true)
    assert result.success?, output
    assert_includes output, '已取消重启'
    refute_match(/-start|-stop/, calls)
  end

  def test_instance_recreated_during_confirmation_is_rejected
    output, result = run_script('--repair', '--name', 'JobsHarmony_Test', input: "\n2\nYES\n", interactive: true,
                                environment: { 'JOBS_TEST_REPLACE_UUID' => '1', 'JOBS_TEST_RUNNING' => 'true' })
    refute result.success?, output
    assert_includes output, '实例 UUID'
    refute_match(/-start|-stop/, calls)
  end

  def test_sdk_repair_preserves_full_backup_and_unrelated_content
    original = "name=JobsHarmony_Test\nsdkPath=/missing/sdk\nkeep=value\n"
    File.write(config, original)
    output, result = run_script('--repair', '--name', 'JobsHarmony_Test', input: "\n3\nYES\n", interactive: true)
    assert result.success?, output
    assert_includes File.read(config), "sdkPath=#{@sdk}"
    assert_includes File.read(config), 'keep=value'
    assert_equal 1, backups.length
    assert_equal original, File.read(File.join(backups.first, 'instance/config.ini'))
    assert_equal 'existing userdata', File.read(File.join(backups.first, 'instance/userdata.img'))
    refute_match(/-start|-stop|-delete/, calls)
  end

  def test_sdk_repair_refuses_running_instance_and_linked_content
    File.write(config, "name=JobsHarmony_Test\nsdkPath=/missing/sdk\n")
    output, result = run_script('--repair', '--name', 'JobsHarmony_Test', input: "\n3\nYES\n", interactive: true,
                                environment: { 'JOBS_TEST_RUNNING' => 'true' })
    refute result.success?, output
    assert_includes output, '仍在运行'
    assert_empty backups
    File.symlink('/etc/hosts', File.join(@instance, 'linked'))
    output, result = run_script('--repair', '--name', 'JobsHarmony_Test', input: "\n3\nYES\n", interactive: true)
    refute result.success?, output
    assert_includes output, '实例含符号链接'
    assert_empty backups
    assert_includes File.read(config), 'sdkPath=/missing/sdk'
  end

  def test_missing_sdk_is_reported_without_any_automatic_download
    File.write(config, "name=JobsHarmony_Test\nsdkPath=/missing/sdk\n")
    output, result = run_script('--check')
    refute result.success?, output
    assert_includes output, 'SDK 路径缺失'
    refute_match(/-start|-stop|-install/, calls)
    assert_empty backups
  end

  def test_sdk_path_with_newline_is_never_written
    File.write(config, "name=JobsHarmony_Test\nsdkPath=/missing/sdk\nkeep=value\n")
    original = File.read(config)
    alternate = File.join(@root, "tool\ninvalid")
    FileUtils.mv(File.join(@root, 'tools'), alternate)
    output, result = run_script('--repair', '--name', 'JobsHarmony_Test', input: "\n3\nYES\n", interactive: true,
                                environment: { 'HARMONY_EMULATOR_BIN' => File.join(alternate, 'emulator/Emulator') })
    refute result.success?, output
    assert_equal original, File.read(config)
    assert_empty backups
  end

  def test_config_change_during_sdk_probe_is_preserved
    File.write(config, "name=JobsHarmony_Test\nsdkPath=/missing/sdk\nkeep=value\n")
    count_path = File.join(@root, 'hdc-count')
    probe = <<~RUBY_SCRIPT
      #!/usr/bin/ruby
      count_path=#{count_path.inspect}
      count=File.exist?(count_path) ? File.read(count_path).to_i : 0
      count+=1
      File.write(count_path,count.to_s)
      if count>=3
        File.open(#{config.inspect},'a') { |f| f.puts('# concurrent DevEco change') }
      end
      puts 'HDC 3.1'
    RUBY_SCRIPT
    write_executable(File.join(@sdk, 'default/openharmony/toolchains/hdc'), probe)
    output, result = run_script('--repair', '--name', 'JobsHarmony_Test', input: "\n3\nYES\n", interactive: true)
    refute result.success?, output
    assert_includes output, '发布前配置内容已改变'
    assert_includes File.read(config), '# concurrent DevEco change'
    assert_includes File.read(config), 'sdkPath=/missing/sdk'
    assert_equal 1, backups.length
  end

  private

  def config
    File.join(@instance, 'config.ini')
  end

  def backups
    Dir.glob(File.join(@root, 'instances/.JobsHarmony_Test.jobs-repair-backup.*'))
  end

  def calls
    File.exist?(@calls) ? File.read(@calls) : ''
  end

  def write_executable(path, content)
    File.write(path, content)
    File.chmod(0o700, path)
  end

  def shell_word(value)
    "'#{value.gsub("'") { "'\\''" }}'"
  end

  def run_script(*arguments, input: '', interactive: false, environment: {})
    env = { 'HOME' => File.join(@root, 'home'), 'TMPDIR' => "#{@root}/", 'NO_COLOR' => '1',
            'HARMONY_EMULATOR_BIN' => @emulator, 'JOBS_TEST_INSTANCE' => @instance,
            'JOBS_TEST_CALLS' => @calls, 'JOBS_TEST_STATE' => File.join(@root, 'running') }.merge(environment)
    return Open3.capture2e(env, '/bin/zsh', '-f', @script, *arguments, stdin_data: input) unless interactive

    output = +''
    status = nil
    Timeout.timeout(30) do
      PTY.spawn(env, '/bin/zsh', '-f', @script, *arguments) do |reader, writer, pid|
        writer.write(input)
        begin
          loop { output << reader.readpartial(4096) }
        rescue EOFError, Errno::EIO
          _, status = Process.wait2(pid)
        end
      end
    end
    [output.force_encoding(Encoding::UTF_8), status]
  end

  def fake_emulator
    <<~'CLI'
      #!/usr/bin/ruby
      require 'json'
      File.open(ENV.fetch('JOBS_TEST_CALLS'),'a') { |f| f.puts(ARGV.join('|')) }
      running = File.exist?(ENV['JOBS_TEST_STATE']) ? File.read(ENV['JOBS_TEST_STATE']) : ENV.fetch('JOBS_TEST_RUNNING','false')
      case ARGV.first
      when '-help'
        puts '-list -details -imageList -start -stop'
        puts '-bootMode coldboot snapshot reset' unless ENV['JOBS_TEST_NO_BOOT_MODE']=='1'
      when '-list'
        count_path=ENV.fetch('JOBS_TEST_STATE')+'.queries'
        count=File.exist?(count_path) ? File.read(count_path).to_i+1 : 1
        File.write(count_path,count.to_s)
        if ENV['JOBS_TEST_EMPTY']=='1'
          puts '[Empty]'
        else
          state = ENV['JOBS_TEST_UNKNOWN_STATE']=='1' ? 'unknown' : running=='true'
          uuid=ENV['JOBS_TEST_REPLACE_UUID']=='1'&&count>=3 ? 'recreated-uuid' : 'fixture-uuid'
          rows=[{name:'JobsHarmony_Test',instancePath:ENV.fetch('JOBS_TEST_INSTANCE'),deviceType:'phone',isRunning:state,uuid:uuid,'os.osVersion'=>'HarmonyOS 6.0'}]
          rows << rows.first.dup if ENV['JOBS_TEST_DUPLICATE']=='1'
          puts JSON.generate(rows)
        end
      when '-imageList'
        puts JSON.generate([{deviceType:'phone',osVersion:'HarmonyOS 6.0',releaseType:'Release',downloaded:true}])
      when '-stop'
        exit 7 if ENV['JOBS_TEST_STOP_FAIL']=='1'
        File.write(ENV.fetch('JOBS_TEST_STATE'),'false') unless ENV['JOBS_TEST_STOP_STUCK']=='1'
        puts 'Stopped'
      when '-start'
        File.write(ENV.fetch('JOBS_TEST_STATE'),'true')
        puts 'Started'
      else
        exit 99
      end
    CLI
  end
end
