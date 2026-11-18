# frozen_string_literal: true
# Jobs：随包窗口分支不调用编译器；构建脚本只写临时Xcode产物。
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

require_relative '../../../Tests/SourceLayoutHelper.rb/SourceLayoutHelper'

class SetupWindowLauncherTests < Minitest::Test
  ROOT = File.expand_path('..', File.dirname(__dir__))
  def test_prebuilt_window_launches_without_swift_source_or_compiler
    Dir.mktmpdir('jobs-setup-prebuilt-') do |directory|
      directory = File.realpath(directory)
      tools = File.join(directory, 'Tools')
      project = File.join(directory, "工程 ' $ literal")
      FileUtils.mkdir_p([File.join(tools, 'SetupGUIAssets'), project])
      launcher = File.join(tools, 'OpenSetupWindow.zsh')
      # The fixture makes accidental compiler lookup fail explicitly.
      source = File.read(JobsSourceLayout.file(File.join(ROOT, 'Scripts/Tools/【MacOS】OpenSetupWindow.zsh/【MacOS】OpenSetupWindow.zsh'))).gsub('/usr/bin/xcrun', 'unavailable_fixture_compiler').gsub('/usr/bin/xcode-select', 'unavailable_fixture_clt')
      File.write(launcher, source)
      File.write(File.join(tools, 'SetupGUIAssets/terminal.html'), 'fixture')
      binary = File.join(tools, 'JobsFlutterSetup')
      File.write(binary, "#!/bin/zsh\n/usr/bin/printf '%s\\0' \"$@\" > \"$JOBS_TEST_SETUP_ARGS\"\nexit 19\n")
      FileUtils.chmod(0o755, binary)
      args = File.join(directory, 'args')
      out, err, status = Open3.capture3({'PATH'=>'/usr/bin:/bin', 'JOBS_TEST_SETUP_ARGS'=>args}, '/bin/zsh', '-f', launcher, '--project', project)
      assert_equal 19, status.exitstatus, out + err
      assert_equal ['--project', project, '--tools', tools], File.binread(args).force_encoding(Encoding::UTF_8).split("\0")
      refute_includes out + err, 'unavailable_fixture'
      refute File.exist?(File.join(tools, 'SetupProjectWindow.swift'))
    end
  end
  def test_build_phase_runs_after_resource_copy_before_extension_registration_and_does_not_change_skip_gate
    project = File.read(JobsSourceLayout.file(File.join(ROOT, 'JobsFlutterTools.xcodeproj/project.pbxproj')))
    host = project[/01D000000000000000000001 \/\* JobsFlutterTools \*\/ = \{.*?\n\t\t\};/m]
    assert_operator host.index('/* Resources */'), :<, host.index('/* Build Setup Window */')
    assert_operator host.index('/* Build Setup Window */'), :<, host.index('/* Enable Finder Extension */')
    assert_includes project, '$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/Tools/JobsFlutterSetup'
    phase = project[/01D000000000000000000015 \/\* Build Setup Window \*\/ = \{.*?\n\t\t\};/m]
    refute_nil phase
    inputs = phase[/inputPaths = \((.*?)\);/m, 1].scan(/"([^"]+)"/).flatten
    inputs.each do |input|
      assert File.file?(input.sub('$(SRCROOT)', ROOT)), "Xcode build input is missing: #{input}"
    end
    registrar = File.read(JobsSourceLayout.file(File.join(ROOT, 'Scripts/【MacOS@Xcode】EnableFinderExtension.zsh/【MacOS@Xcode】EnableFinderExtension.zsh')))
    assert_includes registrar, 'JOBS_SKIP_FINDER_EXTENSION_BUILD_PHASE'
  end
  def test_real_build_helper_generates_executable_only_inside_fake_xcode_products
    Dir.mktmpdir('jobs-setup-build-') do |directory|
      directory = File.realpath(directory)
      project = File.read(File.join(ROOT, 'JobsFlutterTools.xcodeproj/project.pbxproj'))
      phase = project[/01D000000000000000000015 \/\* Build Setup Window \*\/ = \{.*?\n\t\t\};/m]
      refute_nil phase
      command = JSON.parse(phase[/shellScript = ("(?:\\.|[^"])*");/, 1])
      helper = JobsSourceLayout.file(File.join(ROOT, 'Scripts/【MacOS】BuildSetupWindow.zsh/【MacOS】BuildSetupWindow.zsh'))
      ['源码包装', '发布平铺'].each do |layout|
        src = File.join(directory, "搬移后的工程 ' #{layout}")
        products = File.join(directory, "构建产物 #{layout}")
        resource = 'Fixture.app/Contents/Resources'
        entry = File.join(src, layout == '源码包装' ? helper.delete_prefix(ROOT + '/') : 'Scripts/BuildSetupWindow.zsh')
        FileUtils.mkdir_p([File.join(src, 'Scripts/Tools'), File.join(products, resource, 'Tools'), File.dirname(entry)])
        FileUtils.cp(helper, entry)
        # 执行真实Xcode阶段，避免直接调用helper漏掉工程内的旧挂载路径。
        File.write(File.join(src, 'Scripts/Tools/SetupProjectWindow.swift'), 'print("fixture window")')
        arguments = layout == '源码包装' ? ['/bin/zsh', '-f', '-c', command] : ['/bin/zsh', '-f', entry]
        out, err, status = Open3.capture3({'SRCROOT'=>src, 'TARGET_BUILD_DIR'=>products, 'UNLOCALIZED_RESOURCES_FOLDER_PATH'=>resource, 'TEMP_DIR'=>directory,
          'ARCHS'=>'arm64 x86_64', 'MACOSX_DEPLOYMENT_TARGET'=>'12.0', 'EXPANDED_CODE_SIGN_IDENTITY'=>'-', 'LC_ALL'=>'C'}, *arguments, chdir: directory)
        assert status.success?, "#{layout}: #{out}#{err} (exit #{status.exitstatus})"
        binary = File.join(products, resource, 'Tools/JobsFlutterSetup')
        assert File.executable?(binary)
        refute File.exist?(File.join(src, 'Scripts/Tools/JobsFlutterSetup'))
        out, err, status = Open3.capture3('/usr/bin/lipo', '-archs', binary)
        assert status.success?, out + err
        assert_includes out, 'arm64'
        assert_includes out, 'x86_64'
      end
    end
  end
end
