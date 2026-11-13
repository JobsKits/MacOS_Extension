# Created by Jobs on 2026年11月12日，星期四.
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
class SimulatorStartEnvironmentTests < Minitest::Test
  ROOT = File.expand_path('../../..', __dir__)
  PACKAGE = ENV.fetch('JOBS_TEST_SIM_ENV_PACKAGE') { File.join(ROOT, 'JobsFlutterRunner/Scripts/SimulatorCreators/【MacOS】模拟器启动环境.zsh') }
  SCRIPT = File.join(PACKAGE, '【MacOS】模拟器启动环境.zsh')
  def setup
    @tmp = Dir.mktmpdir("jobs-start 中文 '")
    @package = File.join(@tmp, '包')
    FileUtils.cp_r(PACKAGE, @package)
    @log = File.join(@tmp, 'trace')
    @sdk = File.join(@tmp, 'SDK')
    FileUtils.mkdir_p(File.join(@sdk, 'platform-tools'))
    File.write(File.join(@sdk, 'platform-tools/adb'), "#!/bin/zsh\nexit 0\n")
    FileUtils.chmod(0o700, File.join(@sdk, 'platform-tools/adb'))
  end
  def teardown
    FileUtils.remove_entry(@tmp)
  end
  def shell(code)
    Open3.capture3({'HOME'=>@tmp,'NO_COLOR'=>'1','TRACE'=>@log,'SDK'=>@sdk,'ANDROID_HOME'=>nil,'ANDROID_SDK_ROOT'=>nil,'JAVA_HOME'=>nil}, '/bin/zsh','-f','-c', <<~ZSH, chdir: '/tmp')
      source #{File.join(@package, '【MacOS】模拟器启动环境.zsh').shellescape}
      JOBS_SIM_ENV_PACKAGE=#{@package.shellescape}
      LOG_FILE=#{File.join(@tmp,'run.log').shellescape}
      log() { print -r -- "$*"; }
      jobs_sdk_retry() { shift 2; "$@"; }
      run_bounded() {
        local output="$2"
        shift 2
        [[ "$1" == /usr/bin/osascript ]] || { print -u2 "BLOCKED_HOST_COMMAND=$1"; return 99; }
        "$@" > "$output" 2>&1
      }
      #{code}
    ZSH
  end
  def resource(platform, text)
    name="【MacOS】#{platform}工具库.zsh"
    File.write(File.join(@package,'Resources',name,name),text)
  end
  def parse(mode, value, key=nil)
    path=File.join(@tmp,'inventory.json')
    File.write(path,value.is_a?(String) ? value : JSON.generate(value))
    Open3.capture3('/usr/bin/osascript','-l','JavaScript',File.join(PACKAGE,'模拟器实例.jxa'),mode,path,*[key].compact)
  end
  def instance(name='Original', path=nil)
    path ||= File.join(@tmp,name)
    FileUtils.mkdir_p(path)
    config=File.join(path,'config.ini')
    File.write(config,"name=#{name}\nuuid=fixture-uuid\nos.osVersion=HarmonyOS 6.0.1(21)\n") unless File.exist?(config)
    {'name'=>name,'uuid'=>'fixture-uuid','instancePath'=>path,'deviceType'=>'phone','os.osVersion'=>'HarmonyOS 6.0.1(21)','isRunning'=>true,'hw.hdc.port'=>12345}
  end
  def test_official_instance_key_retains_literal_name_path_and_version
    record=instance("My ' $(touch NEVER)",File.join(@tmp,"My ' $(touch NEVER)"))
    out,err,status=parse('rows',[record]); assert status.success?,err
    key=out.split("\t").first
    out,err,status=parse('record',[record],key); assert status.success?,err
    assert_equal [record['name'],record['instancePath'],'phone',record['os.osVersion']].join("\t"),out.strip
    refute File.exist?('/tmp/NEVER')
    changed=record.merge('instancePath'=>'/tmp/replacement')
    _out,_err,status=parse('record',[changed],key); refute status.success?
  end
  def test_malformed_or_duplicate_instances_never_become_rows
    ["not-json",{},[instance,instance],[instance.merge('instancePath'=>'relative')],[instance.merge('name'=>"bad\nname")],[instance.merge('os.osVersion'=>nil)]].each do |data|
      _out,_err,status=parse('rows',data); refute status.success?,data.inspect
    end
    out,err,status=parse('rows','[Empty]'); assert status.success?,err; assert_empty out.strip
  end
  def test_only_stable_launch_component_updates_are_selected
    report=android_report.sub("\nAvailable Updates:","\n cmdline-tools;latest | 20.0-rc1 | Android CLI preview\n platforms;android-38 | 2 | Android API\n system-images;android-38;google_apis;arm64-v8a | 2 | Google Image\n ndk;29 | 2 | NDK\nAvailable Updates:")
    out,err,status=parse('android-updates',report); assert status.success?,err
    assert_equal ['emulator','platform-tools'],out.lines.map(&:strip)
    _out,_err,status=parse('android-updates',report.gsub('36.0','36.0-rc1')); refute status.success?
    _out,_err,status=parse('android-updates','connection failed'); refute status.success?
  end
  def android_report(installed: '35.0', remote: '36.0', platform_installed: '36.0', platform_remote: '36.1', include_updates: true)
    <<~TEXT + (include_updates ? "Available Updates:\n ID | Installed | Available\n -- | --------- | ---------\n emulator | #{installed} | #{remote}\n platform-tools | #{platform_installed} | #{platform_remote}\n" : '')
      Installed packages:
       Path | Version | Description | Location
       ---- | ------- | ----------- | --------
       emulator | #{installed} | Android Emulator | emulator/
       platform-tools | #{platform_installed} | Android SDK Platform-Tools | platform-tools/
      Available Packages:
       Path | Version | Description
       ---- | ------- | -----------
       emulator | #{remote} | Android Emulator
       platform-tools | #{platform_remote} | Android SDK Platform-Tools
    TEXT
  end
  def test_complete_current_android_catalog_reports_no_updates
    report=android_report(installed:'36.0',platform_remote:'36.0',include_updates:false)
    out,err,status=parse('android-updates',report); assert status.success?,err; assert_empty out.strip
    report=report.sub(" platform-tools | 36.0 | Android SDK Platform-Tools | platform-tools/\n",'')
    out,err,status=parse('android-updates',report); assert status.success?,err
    assert_equal 'platform-tools',out.strip
  end
  def test_android_catalog_rejects_truncation_target_schema_and_unverified_versions
    report=android_report
    invalid=[
      "Installed packages:\nAvailable Packages:\n",
      report.sub('emulator | 35.0 | 36.0','emulator | broken'),
      report.sub('emulator | 35.0 | 36.0','emulator | 35.0 | broken'),
      report.sub('emulator | 35.0 | 36.0','emulator | 35.0 | 36.0 | unexpected'),
      report.sub(" emulator | 36.0 | Android Emulator\n",''),
      report.split('Available Updates:').first,
      report.sub(" emulator | 35.0 | 36.0\n",''),
      report.sub('emulator | 35.0 | 36.0','emulator | 34.0 | 36.0'),
      report.sub('emulator | 35.0 | 36.0','emulator | 35.0 | 37.0'),
      report+"Warning: Failed to parse XML repository\n"
    ]
    invalid.each do |catalog|
      out,err,status=parse('android-updates',catalog)
      refute status.success?,catalog; assert_empty out.strip,err
    end
  end
  def android_stub(updates: true, install_code: 0, report: nil, real_retry: false, first_network_failure: false)
    core=File.read(File.join(PACKAGE,'Resources/【MacOS】Android工具库.zsh/【MacOS】Android工具库.zsh'))
    retry_core=core[/# JOBS_SDK_RETRY_BEGIN.*?# JOBS_SDK_RETRY_END/m]
    before=report || android_report(platform_remote:'36.0').sub(" platform-tools | 36.0 | 36.0\n",'')
    current=android_report(installed:'36.0',platform_remote:'36.0',include_updates:false)
    resource('Android', <<~ZSH)
      #{real_retry ? retry_core : 'jobs_sdk_retry() { shift 2; "$@"; }'}
      android_prepare_context() { export JAVA_HOME="$SDK/jdk"; ANDROID_SIM_SDK="$SDK"; ANDROID_SIM_SDKMANAGER=/fixture/sdkmanager; }
      android_initialize_runtime() { print INIT >> "$TRACE"; }
      android_prepare_toolchain() { print PREPARE >> "$TRACE"; }
      android_log() { print -r -- "$*"; print -r -- "$*" >> "$LOG_FILE"; }
      android_ensure_emulator() { print VERIFY_EMULATOR >> "$TRACE"; }
      android_timed() {
        shift
        if [[ "$*" == *--list* ]]; then
          local n=0
          [[ ! -f "$TRACE.count" ]] || n="$(< "$TRACE.count")"
          (( n++ )); print "$n" > "$TRACE.count"
          print LIST >> "$TRACE"
          (( n < 5 )) || return 130
          if [[ #{first_network_failure ? 1 : 0} == 1 && "$n" == 1 ]]; then print 'Warning: Connection reset by peer'; return 0; fi
          if [[ ! -f "$TRACE.updated" && #{updates ? 1 : 0} == 1 ]]; then
            print -r -- #{before.shellescape}
          else
            print -r -- #{current.shellescape}
          fi
          return 0
        fi
        print VERIFY_ADB >> "$TRACE"
      }
      android_install_package() { print -r -- "INSTALL=$1" >> "$TRACE"; : > "$TRACE.updated"; return #{install_code}; }
    ZSH
  end
  def test_android_prepares_updates_verifies_and_returns_real_parent_environment
    android_stub
    out,err,status=shell('jobs_flutter_prepare_simulator_environment android; print "RESULT=$? SDK=$ANDROID_HOME JAVA=$JAVA_HOME"')
    assert status.success?,out+err
    assert_includes out,"RESULT=0 SDK=#{@sdk} JAVA=#{@sdk}/jdk"
    trace=File.read(@log)
    assert_operator trace.index('PREPARE'),:<,trace.index('INSTALL=emulator')
    assert_operator trace.index('INSTALL=emulator'),:<,trace.index('VERIFY_EMULATOR')
    assert_includes trace,'VERIFY_ADB'
    refute_includes trace,'CREATE'
  end
  def test_android_failed_update_never_publishes_environment
    android_stub(install_code: 77)
    out,err,status=shell('jobs_flutter_prepare_simulator_environment android; print "RESULT=$? SDK=${ANDROID_HOME:-unset}"')
    assert status.success?,out+err; assert_includes out,'RESULT=77 SDK=unset'
    refute_includes File.read(@log),'VERIFY_EMULATOR'
  end
  def test_android_healthy_environment_has_no_unnecessary_install
    android_stub(updates: false)
    out,err,status=shell('jobs_flutter_prepare_simulator_environment android; print "RESULT=$?"')
    assert status.success?,out+err; assert_includes out,'RESULT=0'
    refute_includes File.read(@log),'INSTALL='
  end
  def test_android_parent_rejects_malformed_catalog_once_without_install_or_publish
    ["Installed packages:\nAvailable Packages:\n",android_report.sub('emulator | 35.0 | 36.0','emulator | broken')].each do |report|
      FileUtils.rm_f([@log,@log+'.count'])
      android_stub(report:report,real_retry:true)
      out,err,status=shell('JOBS_SDK_RETRY_DELAY=0; JOBS_SDK_RETRY_MAX_DELAY=1; jobs_flutter_prepare_simulator_environment android; print "RESULT=$? SDK=${ANDROID_HOME:-unset}"')
      assert status.success?,out+err;assert_includes out,'RESULT=67 SDK=unset'
      assert_equal '1',File.read(@log+'.count').strip
      trace=File.read(@log);refute_includes trace,'INSTALL=';refute_includes trace,'VERIFY_EMULATOR';refute_includes trace,'VERIFY_ADB'
    end
  end
  def test_android_parent_retries_only_transient_catalog_fetch_then_finishes
    android_stub(updates:false,real_retry:true,first_network_failure:true)
    out,err,status=shell('JOBS_SDK_RETRY_DELAY=0; JOBS_SDK_RETRY_MAX_DELAY=1; jobs_flutter_prepare_simulator_environment android; print "RESULT=$?"')
    assert status.success?,out+err;assert_includes out,'RESULT=0'
    assert_equal '2',File.read(@log+'.count').strip
    refute_includes File.read(@log),'INSTALL='
  end
  def ios_context
    FileUtils.mkdir_p(File.join(@sdk,'usr/bin'))
    %w[simctl xcodebuild].each { |name| p=File.join(@sdk,'usr/bin',name);File.write(p,'fixture');FileUtils.chmod(0o700,p) }
    <<~ZSH
      export DEVELOPER_DIR="$SDK"
      jobs_sim_query() {
        print -r -- "QUERY=$1" >> "$TRACE"
        if [[ "$1" == ios-runtimes ]]; then print '{"runtimes":[{"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-27-0","isAvailable":true}]}' > "$LOG_FILE.simulator-ios-runtimes"; fi
        return 0
      }
      jobs_sim_xcodebuild() { print -r -- "XCODE=$*" >> "$TRACE"; return 0; }
    ZSH
  end
  def test_ios_always_checks_compatible_components_before_reading_devices
    out,err,status=shell(ios_context+'jobs_flutter_prepare_simulator_environment ios; print "RESULT=$?"')
    assert status.success?,out+err; assert_includes out,'RESULT=0'
    trace=File.read(@log)
    assert_includes trace,'XCODE=-runFirstLaunch -checkForNewerComponents'
    assert_operator trace.index('checkForNewerComponents'),:<,trace.index('QUERY=ios-runtimes')
    refute_includes trace,'-downloadPlatform'
  end
  def test_ios_update_authorization_failure_stops_before_inventory
    out,err,status=shell(ios_context+<<~'ZSH')
      jobs_sim_xcodebuild() { print UPDATE_DENIED >> "$TRACE"; return 77; }
      jobs_flutter_prepare_simulator_environment ios
      print "RESULT=$?"
    ZSH
    assert status.success?,out+err; assert_includes out,'RESULT=77'
    refute_includes File.read(@log),'QUERY=ios-runtimes'
  end
  def harmony_stub(replace: false, authorized: true, start_code: 0)
    File.write(File.join(@tmp,'instances'),JSON.generate([instance]))
    resource('Harmony', <<~ZSH)
      HS_BIN=''
      hs_query_output() { /bin/cat "$HOME/instances"; }
      hs_run_command() { print -r -- "START=$*" >> "$TRACE"; #{replace ? 'print -r -- '+JSON.generate([instance.merge('uuid'=>'replacement-uuid')]).shellescape+' > "$HOME/instances";' : ''} return #{start_code}; }
      hs_json() { print -r -- $'127.0.0.1:12345\t/sdk\t/tmp/Original'; }
      hs_created_instance_hdc() { print /fixture/hdc; }
      hs_created_hdc_targets() { print #{authorized ? '127.0.0.1:12345' : '127.0.0.1:54321'}; }
      hs_error() { print -u2 -r -- "$*"; return 1; }
    ZSH
  end
  def test_harmony_wait_accepts_only_the_selected_instance_hdc_target
    harmony_stub
    key,err,status=parse('rows',[instance]);assert status.success?,err;key=key.split("\t").first
    out,err,status=shell("JOBS_SIM_HARMONY_BIN=/fixture/Emulator\nJOBS_SIM_HARMONY_WAIT_SECONDS=0\njobs_flutter_start_harmony_instance #{key.shellescape} #{File.join(@tmp,'receipt').shellescape}; print RESULT=$?")
    assert status.success?,out+err;assert_includes out,'RESULT=0'
    assert_equal '127.0.0.1:12345',File.read(File.join(@tmp,'receipt')).strip
    assert_equal "START=-start Original\n",File.read(@log)
  end
  def test_harmony_changed_instance_unauthorized_or_failed_start_never_returns_another_target
    [{replace:true},{authorized:false},{start_code:7}].each do |options|
      harmony_stub(**options)
      FileUtils.rm_f(File.join(@tmp,'receipt'))
      key,err,status=parse('rows',[instance]);assert status.success?,err;key=key.split("\t").first
      out,err,status=shell("JOBS_SIM_HARMONY_BIN=/fixture/Emulator\nJOBS_SIM_HARMONY_WAIT_SECONDS=0\njobs_flutter_start_harmony_instance #{key.shellescape} #{File.join(@tmp,'receipt').shellescape}; print RESULT=$?")
      assert status.success?,out+err; refute_includes out,'RESULT=0'
      refute File.exist?(File.join(@tmp,'receipt'))
    end
  end
  def test_packaged_libraries_remain_the_same_jobs_tool_core_without_entry_calls
    {'Android'=>'CreateAndroidSimulator.zsh','Harmony'=>'CreateHarmonySimulator.zsh'}.each do |platform,file|
      original=File.read(File.join(ROOT,"Jobs#{platform}SimulatorCreator/Scripts",file))
      core=original[original.index('# JOBS_SDK_RETRY_BEGIN')...original.rindex("\nmain() {")]
      library=File.read(File.join(PACKAGE,'Resources',"【MacOS】#{platform}工具库.zsh","【MacOS】#{platform}工具库.zsh"))
      assert library.end_with?(core),platform
      refute_includes library,'jobs_terminal_style_bootstrap "$0"'
      refute_match(/^main "\$@"$/,library)
    end
  end
  def test_ios_install_wait_opens_official_page_once_and_resumes_in_current_flow
    out,err,status=shell(ios_context+<<~'ZSH')
      integer discovered=0
      jobs_sim_find_xcode() { (( discovered++ )); (( discovered >= 3 )) || return 3; REPLY="$SDK"; }
      jobs_sim_open_xcode_install_page() { print OPEN_OFFICIAL >> "$TRACE"; }
      jobs_sim_install_wait_tick() { print WAIT >> "$TRACE"; }
      jobs_flutter_prepare_simulator_environment ios
      print RESULT=$?
    ZSH
    assert status.success?,out+err;assert_includes out,'RESULT=0'
    trace=File.read(@log);assert_equal 1,trace.scan('OPEN_OFFICIAL').length
    assert_equal 2,trace.scan('WAIT').length
    assert_operator trace.index('WAIT'),:<,trace.index('XCODE=-runFirstLaunch -checkForNewerComponents')
  end
  def test_ios_cancelled_install_or_first_launch_never_runs_following_preparation
    [<<~'ZSH',<<~'ZSH'].each do |code|
      jobs_sim_find_xcode() { return 3; }
      jobs_sim_open_xcode_install_page() { print OPEN >> "$TRACE"; }
      jobs_sim_install_wait_tick() { return 130; }
    ZSH
      jobs_sim_query() { [[ "$1" != ios-first-launch ]] || return 130; }
    ZSH
      FileUtils.rm_f(@log)
      out,err,status=shell(ios_context+code+'jobs_flutter_prepare_simulator_environment ios; print RESULT=$?')
      assert status.success?,out+err;assert_includes out,'RESULT=130'
      refute_includes(File.exist?(@log) ? File.read(@log) : '', 'XCODE=')
    end
  end
  def test_avd_identity_detects_same_name_replacement_but_tolerates_runtime_port_changes
    base=File.join(@tmp,'avds');directory=File.join(base,'Original.avd');FileUtils.mkdir_p(directory)
    File.write(File.join(base,'Original.ini'),"path=#{directory}\n")
    config=File.join(directory,'config.ini');File.write(config,"AvdId=Original\nimage.sysdir.1=system-images/android-37\nhw.hdc.port=10000\n")
    identity=-> { Open3.capture3('/usr/bin/osascript','-l','JavaScript',File.join(PACKAGE,'模拟器实例.jxa'),'avd-identity',base,'Original') }
    first,err,status=identity.call;assert status.success?,err
    File.write(config,"AvdId=Original\nimage.sysdir.1=system-images/android-37\nhw.hdc.port=10001\n")
    second,err,status=identity.call;assert status.success?,err;assert_equal first,second
    File.rename(config,config+'.old');File.write(config,"AvdId=Original\nimage.sysdir.1=system-images/android-37\n")
    third,err,status=identity.call;assert status.success?,err;refute_equal first,third
  end
  def test_avd_identity_respects_explicit_android_directory_precedence
    out,err,status=shell(<<~'ZSH')
      jobs_sim_instance_json() { print -r -- "$2"; }
      unset ANDROID_AVD_HOME ANDROID_EMULATOR_HOME ANDROID_USER_HOME
      jobs_sim_android_avd_identity Original
      ANDROID_USER_HOME=/synthetic/user
      jobs_sim_android_avd_identity Original
      ANDROID_EMULATOR_HOME=/synthetic/emulator
      jobs_sim_android_avd_identity Original
      ANDROID_AVD_HOME=/synthetic/avds
      jobs_sim_android_avd_identity Original
    ZSH
    assert status.success?,out+err
    assert_equal [File.join(@tmp,'.android/avd'),'/synthetic/user/avd','/synthetic/emulator/avd','/synthetic/avds'],out.lines.map(&:strip)
  end

  def test_ios_component_network_failure_retries_only_acquisition_until_success
    core=File.join(PACKAGE,'Resources/【MacOS】Android工具库.zsh/【MacOS】Android工具库.zsh')
    out,err,status=shell(ios_context+"source #{core.shellescape}\n"+<<~'ZSH')
      JOBS_SDK_RETRY_DELAY=0
      JOBS_SDK_RETRY_MAX_DELAY=1
      jobs_sim_xcodebuild() {
        local n=0
        [[ ! -f "$TRACE.count" ]] || n="$(< "$TRACE.count")"
        (( n++ )); print "$n" > "$TRACE.count"
        print -r -- "XCODE=$*" >> "$TRACE"
        (( n >= 3 )) || { print 'Connection reset by peer'; return 1; }
      }
      jobs_flutter_prepare_simulator_environment ios
      print RESULT=$?
    ZSH
    assert status.success?,out+err;assert_includes out,'RESULT=0'
    assert_equal '3',File.read(@log+'.count').strip
    assert_equal 1,File.read(@log).scan('QUERY=ios-runtimes').length
    assert_equal 3,File.read(@log).scan('checkForNewerComponents').length
  end

  def harmony_prepare_stub(state: 'ready', official_code: 0, archive_version: '6.1.1.300')
    FileUtils.mkdir_p([File.join(@sdk,'emulator'),File.join(@sdk,'sdk/default/openharmony/ets'),File.join(@sdk,'sdk/default/openharmony/native'),File.join(@sdk,'sdk/default/openharmony/toolchains')])
    File.write(File.join(@sdk,'version.txt'),state=='ready' ? '6.1.1.300' : '6.1.1.200')
    File.write(File.join(@sdk,'sdk/default/openharmony/toolchains/hdc'),'fixture');FileUtils.chmod(0o700,File.join(@sdk,'sdk/default/openharmony/toolchains/hdc'))
    resource('Harmony', <<~ZSH)
      HS_TOOLS_HOME="$HOME/tools"
      HS_BIN=''
      hs_check_host() { return 0; }
      hs_initialize_log() { HS_LOG="$HOME/harmony.log"; : > "$HS_LOG"; }
      hs_find_emulator() { HS_BIN="$SDK/emulator/Emulator"; print FIND >> "$TRACE"; }
      hs_log() { print -r -- "$*"; print -r -- "$*" >> "$HS_LOG"; }
      hs_error() { print -u2 -r -- "$*"; return 1; }
      hs_check_capabilities() { print CAPABILITY >> "$TRACE"; }
      hs_prepare_tools_only() { print TOOLS >> "$TRACE"; }
      hs_review_licenses() { print LICENSE >> "$TRACE"; }
      hs_query_output() { print '[]'; }
      hs_publish_clt() { print PUBLISH >> "$TRACE"; /bin/mkdir -p "$2"; /bin/cp -R "$1/" "$2/"; }
      hs_install_clt() {
        print INSTALL >> "$TRACE"
        hs_log "Source: $HS_CLT_URL"
        /bin/mkdir -p "$HOME/stage/emulator"
        print -rn -- '#{archive_version}' > "$HOME/stage/version.txt"
        print fixture > "$HOME/stage/emulator/Emulator"
        hs_publish_clt "$HOME/stage" "$HOME/new-clt" || return $?
        HS_BIN="$HOME/new-clt/emulator/Emulator"
      }
    ZSH
    path=File.join(@package,'Resources/【MacOS】鸿蒙官方更新.zsh/【MacOS】鸿蒙官方更新.zsh')
    File.write(path,<<~ZSH)
      jobs_sim_harmony_official_update() { print -r -- "OFFICIAL_CURRENT=$1" >> "$TRACE"; (( #{official_code} == 0 )) || return #{official_code}; print fixture > "$2"; }
      jobs_sim_harmony_official_data() {
        case "$3" in state) print '#{state}' ;; version) print 6.1.1.300 ;; size) print 2000000000 ;; sha256) print aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa ;; url) print 'https://developer.huawei.com/archive.zip?token=SECRET_TEST_TOKEN' ;; esac
      }
    ZSH
  end
  def test_harmony_official_authorization_block_precedes_every_download_or_tool_preparation
    harmony_prepare_stub(official_code:67)
    out,err,status=shell('HARMONY_EMULATOR_BIN="$SDK/emulator/Emulator"; jobs_flutter_prepare_simulator_environment harmony; print RESULT=$?')
    assert status.success?,out+err;assert_includes out,'RESULT=67'
    trace=File.read(@log);assert_includes trace,'OFFICIAL_CURRENT=6.1.1.300'
    refute_includes trace,'INSTALL';refute_includes trace,'TOOLS';refute_includes trace,'LICENSE'
  end
  def test_harmony_official_ready_rechecks_tools_and_license_before_inventory
    harmony_prepare_stub
    out,err,status=shell('HARMONY_EMULATOR_BIN="$SDK/emulator/Emulator"; jobs_flutter_prepare_simulator_environment harmony; print RESULT=$? BIN=$JOBS_SIM_HARMONY_BIN')
    assert status.success?,out+err;assert_includes out,'RESULT=0'
    trace=File.read(@log);assert_operator trace.index('OFFICIAL_CURRENT'),:<,trace.index('TOOLS')
    assert_operator trace.index('TOOLS'),:<,trace.index('LICENSE')
    refute_includes trace,'INSTALL'
  end
  def test_harmony_official_update_is_side_installed_version_checked_and_url_redacted
    harmony_prepare_stub(state:'update')
    out,err,status=shell('HARMONY_EMULATOR_BIN="$SDK/emulator/Emulator"; jobs_flutter_prepare_simulator_environment harmony; print RESULT=$?')
    assert status.success?,out+err;assert_includes out,'RESULT=0'
    assert_includes File.read(@log),'PUBLISH'
    refute_includes out+err+File.read(File.join(@tmp,'harmony.log')),'SECRET_TEST_TOKEN'
    assert_equal '6.1.1.300',File.read(File.join(@tmp,'new-clt/version.txt'))
    assert_equal '6.1.1.200',File.read(File.join(@sdk,'version.txt'))
  end
  def test_harmony_wrong_archive_version_never_publishes_or_reports_readiness
    harmony_prepare_stub(state:'update',archive_version:'6.1.1.200')
    out,err,status=shell('HARMONY_EMULATOR_BIN="$SDK/emulator/Emulator"; jobs_flutter_prepare_simulator_environment harmony; print RESULT=$?')
    assert status.success?,out+err;refute_includes out,'RESULT=0'
    refute_includes File.read(@log),'PUBLISH'
    refute File.exist?(File.join(@tmp,'new-clt'))
  end

end
