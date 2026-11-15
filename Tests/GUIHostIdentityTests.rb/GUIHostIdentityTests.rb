# frozen_string_literal: true
# Jobs：临时原生 CLI 代替面板，验证稳定 App 身份、标准签名和外置缓存，不打开 GUI 或更改授权。
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
require 'digest'

class GUIHostIdentityTests < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)
  HELPER = File.join(ROOT, 'Scripts/FinderManagerGUI.zsh')
  ICON = File.join(ROOT, 'Scripts/【MacOS】AppDeployment.zsh/Resources/JobsFinderManager.icns')

  def fixture
    Dir.mktmpdir('jobs-gui-host-') do |directory|
      directory = File.realpath(directory)
      package = File.join(directory, 'package 中文')
      cache = File.join(directory, 'external cache')
      FileUtils.mkdir_p([File.join(package, 'Scripts'), cache])
      FileUtils.mkdir_p(File.dirname(source_icon(package)))
      FileUtils.cp(ICON, source_icon(package))
      File.write(File.join(package, 'Scripts/SelectFinderExtensionFeatures.swift'), '// fixture source')
      entry = File.join(package, 'Scripts/ManageFinderExtensions.zsh')
      File.write(entry, '# never executed')
      binary = File.join(cache, 'SelectFinderExtensionFeatures')
      compile_native(directory, binary, 'original')
      File.utime(Time.now + 60, Time.now + 60, binary)
      yield directory, package, cache, entry, binary
    end
  end

  def compile_native(directory, binary, version)
    source = File.join(directory, 'main.swift')
    File.write(source, <<~SWIFT)
      import Foundation
      print("VERSION=#{version}")
      print("BUNDLE=\\(Bundle.main.bundleURL.path)")
      print("EXECUTABLE=\\(CommandLine.arguments[0])")
      print("RESPONSIBLE=\\(ProcessInfo.processInfo.environment["JOBS_FINDER_RESPONSIBLE_APP"] ?? "")")
      for argument in CommandLine.arguments.dropFirst() {
          print("ARG=\\(argument)")
      }
    SWIFT
    output, result = Open3.capture2e('/usr/bin/xcrun', 'swiftc', source, '-o', binary)
    assert result.success?, output
  end

  def launch(cache, entry)
    code = File.read(HELPER) + <<~'ZSH'
      jobs_manager_launch_error() { print -u2 -r -- "$1|${2:-}"; return 1; }
      jobs_launch_finder_manager_gui "$1" 'path_copier,file-create' uninstall 1
    ZSH
    Open3.capture3({ 'JOBS_FINDER_MANAGER_CACHE_DIR' => cache, 'JOBS_FINDER_INSTALL_LOCATION' => 'applications', 'JOBS_FINDER_CLEANUP_BUILD_PRODUCTS' => '0' }, '/bin/zsh', '-f', '-c', code, 'fixture', entry)
  end

  def source_icon(package)
    File.join(package, 'Scripts/【MacOS】AppDeployment.zsh/Resources/JobsFinderManager.icns')
  end

  def change_icon_representation_order(path)
    contents = File.binread(path)
    assert_equal 'icns', contents[0, 4]
    assert_equal contents.bytesize, contents[4, 4].unpack1('N')
    chunks = []
    offset = 8
    while offset < contents.bytesize
      length = contents[offset + 4, 4].unpack1('N')
      assert_operator length, :>=, 8
      chunks << contents[offset, length]
      offset += length
    end
    assert_operator chunks.size, :>, 1
    changed = contents[0, 8] + chunks.reverse.join
    refute_equal contents, changed
    File.binwrite(path, changed)
  end

  def test_native_host_has_stable_identity_standard_signature_and_reuses_identical_binary
    fixture do |_directory, package, cache, entry, binary|
      output, errors, result = launch(cache, entry)
      assert result.success?, output + errors
      app = File.join(cache, 'Jobs右键菜单管理面板.app')
      executable = File.join(app, 'Contents/MacOS/JobsFinderManager')
      assert_includes output, "BUNDLE=#{app}"
      assert_includes output, "EXECUTABLE=#{executable}"
      assert_includes output, "RESPONSIBLE=#{app}"
      assert_equal ['--manager', entry, '--action', 'uninstall', '--install-location', 'applications', '--no-cleanup-build-products', '--scope', 'path_copier,file-create'], output.lines.grep(/^ARG=/).map { |line| line.chomp.delete_prefix('ARG=') }
      values = { 'CFBundleIdentifier' => 'com.jobs.finderextensions.managementpanel', 'CFBundleName' => 'Jobs右键菜单管理面板', 'CFBundleDisplayName' => 'Jobs右键菜单管理面板', 'CFBundleExecutable' => 'JobsFinderManager', 'CFBundleIconFile' => 'JobsFinderManager.icns' }
      values.each do |key, value|
        actual, result = Open3.capture2e('/usr/libexec/PlistBuddy', '-c', "Print :#{key}", File.join(app, 'Contents/Info.plist'))
        assert result.success?, actual
        assert_equal value, actual.strip
      end
      actual, result = Open3.capture2e('/usr/bin/codesign', '--verify', '--deep', '--strict', app)
      assert result.success?, actual
      actual, result = Open3.capture2e('/usr/bin/codesign', '--display', '--verbose=4', app)
      assert result.success?, actual
      assert_includes actual, 'Signature=adhoc'
      assert_includes actual, 'Identifier=com.jobs.finderextensions.managementpanel'
      assert_equal Digest::SHA256.file(binary).hexdigest, File.read(File.join(app, 'Contents/Resources/BinarySource.sha256')).strip
      assert_equal File.binread(source_icon(package)), File.binread(File.join(app, 'Contents/Resources/JobsFinderManager.icns'))
      assert_equal Digest::SHA256.file(source_icon(package)).hexdigest, File.read(File.join(app, 'Contents/Resources/IconSource.sha256')).strip
      inode = File.stat(executable).ino
      modified = File.mtime(executable)
      output, errors, result = launch(cache, entry)
      assert result.success?, output + errors
      assert_equal inode, File.stat(executable).ino, 'unchanged native binary keeps the existing App'
      assert_equal modified, File.mtime(executable)
      refute File.exist?(File.join(package, 'work')), 'bundle source remains read only with an external cache'
      assert_empty Dir.glob(File.join(cache, '.JobsFinderManagerHost.*'))
    end
  end

  def test_icon_only_change_rebuilds_host_without_changing_binary
    fixture do |_directory, package, cache, entry, binary|
      _, errors, result = launch(cache, entry)
      assert result.success?, errors
      app = File.join(cache, 'Jobs右键菜单管理面板.app')
      icon = source_icon(package)
      old_app = File.stat(app).ino
      binary_hash = Digest::SHA256.file(binary).hexdigest
      change_icon_representation_order(icon)
      output, errors, result = launch(cache, entry)
      assert result.success?, output + errors
      refute_equal old_app, File.stat(app).ino, 'an icon update replaces the cache App even when the binary is unchanged'
      assert_equal binary_hash, Digest::SHA256.file(binary).hexdigest
      assert_includes output, 'VERSION=original'
      assert_equal binary_hash, File.read(File.join(app, 'Contents/Resources/BinarySource.sha256')).strip
      assert_equal File.binread(icon), File.binread(File.join(app, 'Contents/Resources/JobsFinderManager.icns'))
      assert_equal Digest::SHA256.file(icon).hexdigest, File.read(File.join(app, 'Contents/Resources/IconSource.sha256')).strip
      assert_empty Dir.glob(File.join(cache, '.JobsFinderManagerHost.*'))
    end
  end

  def test_legacy_host_without_icon_is_upgraded_on_launch
    fixture do |_directory, package, cache, entry, binary|
      code = File.read(HELPER) + "\njobs_manager_prepare_gui_app \"$1\" \"$2\"\n"
      _, errors, result = Open3.capture3('/bin/zsh', '-f', '-c', code, 'fixture', binary, cache)
      assert result.success?, errors
      app = File.join(cache, 'Jobs右键菜单管理面板.app')
      refute File.exist?(File.join(app, 'Contents/Resources/JobsFinderManager.icns'))
      _, errors, result = launch(cache, entry)
      assert result.success?, errors
      assert_equal File.binread(source_icon(package)), File.binread(File.join(app, 'Contents/Resources/JobsFinderManager.icns'))
      actual, verified = Open3.capture2e('/usr/bin/codesign', '--verify', '--deep', '--strict', app)
      assert verified.success?, actual
    end
  end

  def test_missing_invalid_or_linked_icon_preserves_existing_host
    fixture do |_directory, package, cache, entry, _binary|
      _, errors, result = launch(cache, entry)
      assert result.success?, errors
      app = File.join(cache, 'Jobs右键菜单管理面板.app')
      icon = source_icon(package)
      original = File.binread(icon)
      previous_app = File.stat(app).ino
      FileUtils.rm(icon)
      [nil, 'invalid icon', :link].each do |variant|
        FileUtils.rm_f(icon)
        File.binwrite(icon, variant) if variant.is_a?(String)
        File.symlink(ICON, icon) if variant == :link
        _, errors, result = launch(cache, entry)
        refute result.success?, variant.inspect
        assert_includes errors, '缺少有效的随包管理面板图标'
        assert_equal previous_app, File.stat(app).ino
        assert_equal original, File.binread(File.join(app, 'Contents/Resources/JobsFinderManager.icns'))
      end
      assert_empty Dir.glob(File.join(cache, '.JobsFinderManagerHost.*'))
    end
  end

  def test_icon_update_signing_failure_preserves_previous_host
    fixture do |_directory, package, cache, entry, binary|
      _, errors, result = launch(cache, entry)
      assert result.success?, errors
      app = File.join(cache, 'Jobs右键菜单管理面板.app')
      old_icon = File.binread(File.join(app, 'Contents/Resources/JobsFinderManager.icns'))
      previous_app = File.stat(app).ino
      change_icon_representation_order(source_icon(package))
      code = File.read(HELPER) + <<~'ZSH'
        jobs_manager_sign_gui_app() { print -u2 simulated-icon-signing-failure; return 23; }
        jobs_manager_prepare_gui_app "$1" "$2" "$3"
      ZSH
      _, errors, result = Open3.capture3('/bin/zsh', '-f', '-c', code, 'fixture', binary, cache, source_icon(package))
      assert_equal 23, result.exitstatus, errors
      assert_equal previous_app, File.stat(app).ino
      assert_equal old_icon, File.binread(File.join(app, 'Contents/Resources/JobsFinderManager.icns'))
      actual, verified = Open3.capture2e('/usr/bin/codesign', '--verify', '--deep', '--strict', app)
      assert verified.success?, actual
      assert_empty Dir.glob(File.join(cache, '.JobsFinderManagerHost.*'))
    end
  end

  def test_signing_failure_preserves_previous_host_and_its_valid_signature
    fixture do |directory, _package, cache, entry, binary|
      _, errors, result = launch(cache, entry)
      assert result.success?, errors
      app = File.join(cache, 'Jobs右键菜单管理面板.app')
      executable = File.join(app, 'Contents/MacOS/JobsFinderManager')
      before = Digest::SHA256.file(executable).hexdigest
      inode = File.stat(executable).ino
      compile_native(directory, binary, 'changed')
      code = File.read(HELPER) + <<~'ZSH'
        jobs_manager_sign_gui_app() { print -u2 simulated-signing-failure; return 23; }
        jobs_manager_prepare_gui_app "$1" "$2"
      ZSH
      _, errors, result = Open3.capture3('/bin/zsh', '-f', '-c', code, 'fixture', binary, cache)
      assert_equal 23, result.exitstatus, errors
      assert_includes errors, 'simulated-signing-failure'
      assert_equal before, Digest::SHA256.file(executable).hexdigest
      assert_equal inode, File.stat(executable).ino
      actual, verified = Open3.capture2e('/usr/bin/codesign', '--verify', '--deep', '--strict', app)
      assert verified.success?, actual
      assert_empty Dir.glob(File.join(cache, '.JobsFinderManagerHost.*'))
    end
  end

  def test_foreign_same_named_app_is_not_overwritten
    fixture do |_directory, _package, cache, _entry, binary|
      app = File.join(cache, 'Jobs右键菜单管理面板.app')
      FileUtils.mkdir_p(File.join(app, 'Contents'))
      marker = File.join(app, 'Contents/Info.plist')
      File.write(marker, '<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>org.other.app</string></dict></plist>')
      before = File.binread(marker)
      code = File.read(HELPER) + "\njobs_manager_prepare_gui_app \"$1\" \"$2\"\n"
      _, errors, result = Open3.capture3('/bin/zsh', '-f', '-c', code, 'fixture', binary, cache)
      refute result.success?
      assert_includes errors, '拒绝覆盖非自有管理 App'
      assert_equal before, File.binread(marker)
    end
  end
end
