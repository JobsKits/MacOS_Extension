# frozen_string_literal: true
# Jobs：仅临时伪 App 与假 GUI 缓存，验证管理资源可脱离源码，不调用安装或登记。
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

class CombinedManagerResourcesTests < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)
  LIBRARY = '【MacOS】联合App管理.zsh'
  DEPLOYMENT = '【MacOS】AppDeployment.zsh'
  PACKAGES = %w[JobsProjectTools JobsPathCopier JobsCommandShortcutCreator JobsFileCreator JobsFileHasher JobsRunAuthorizer JobsRunAuthorizationRevoker JobsIPAResigner JobsDesktopTools JobsFlutterTools JobsTerminalOpener JobsIOSTools].freeze

  def fixture
    Dir.mktmpdir('jobs-combined-manager-') do |directory|
      directory = File.realpath(directory)
      source = File.join(directory, 'source 中文')
      FileUtils.mkdir_p(File.join(source, 'Scripts'))
      FileUtils.cp_r(File.join(ROOT, 'Scripts', LIBRARY), File.join(source, 'Scripts'))
      FileUtils.cp_r(File.join(ROOT, 'Scripts', DEPLOYMENT), File.join(source, 'Scripts'))
      File.write(File.join(source, 'Scripts/ManageFinderExtensions.zsh'), '# full source marker')
      PACKAGES.each { |name| prepare_package(File.join(source, name), name) }
      app = File.join(directory, 'Jobs自定义右键菜单.app')
      FileUtils.mkdir_p(File.join(app, 'Contents/Resources'))
      File.write(File.join(app, 'Contents/Info.plist'), '<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.jobs.finderextensions.manager</string></dict></plist>')
      yield directory, source, app
    end
  end

  def prepare_package(path, contents)
    FileUtils.mkdir_p(File.join(path, 'Scripts/Tools'))
    File.write(File.join(path, 'Scripts/ManageExtension.zsh'), "# #{contents}\n")
    File.write(File.join(path, 'Scripts/Tools/business.zsh'), 'must not be copied')
    FileUtils.cp_r(File.join(ROOT, 'Scripts', DEPLOYMENT), File.join(path, 'Scripts'))
    if File.basename(path) == 'JobsProjectTools'
      File.write(File.join(path, 'Scripts/ManageProjectTools.zsh'), '# project manager')
    elsif File.basename(path) == 'JobsDesktopTools'
      File.write(File.join(path, 'Scripts/ManageDesktopTools.zsh'), '# desktop manager')
    end
  end

  def prepare(source, app)
    library = File.join(source, 'Scripts', LIBRARY, LIBRARY)
    Open3.capture3('/bin/zsh', '-f', '-c', 'source "$1" && jobs_prepare_combined_manager_resources "$2"', 'fixture', library, app)
  end

  def test_full_source_copies_only_management_resources_and_snapshots
    fixture do |_directory, source, app|
      output, errors, status = prepare(source, app)
      assert status.success?, output + errors
      manager = File.join(app, 'Contents/Resources/ManagerRoot')
      assert_equal PACKAGES.sort, Dir.children(manager).grep(/^Jobs/).sort
      PACKAGES.each do |name|
        assert File.file?(File.join(manager, name, 'Scripts/ManageExtension.zsh'))
        refute File.exist?(File.join(manager, name, 'Scripts/Tools'))
      end
      %w[RootWorker PanelSource GuiBootstrap].zip(%w[ManageFinderExtensions.zsh SelectFinderExtensionFeatures.swift FinderManagerGUI.zsh]).each do |snapshot, name|
        assert_equal File.binread(File.join(source, 'Scripts', LIBRARY, 'Resources', "#{snapshot}.txt")), File.binread(File.join(manager, 'Scripts', name))
      end
      assert File.file?(File.join(manager, 'JobsProjectTools/Scripts/ManageProjectTools.zsh'))
      assert File.file?(File.join(manager, 'JobsDesktopTools/Scripts/ManageDesktopTools.zsh'))
    end
  end

  def test_relative_source_path_remains_usable_after_changing_working_directory_in_c_locale
    fixture do |directory, source, app|
      script = <<~'ZSH'
        builtin cd -- "$1" || exit 1
        source ./【MacOS】联合App管理.zsh || exit 2
        builtin cd -- "$2" || exit 3
        jobs_prepare_combined_manager_resources "$3" || exit 4
        [[ "$LC_ALL" == C ]] || exit 5
      ZSH
      output, errors, status = Open3.capture3(
        { 'LC_ALL' => 'C', 'LANG' => 'C' }, '/bin/zsh', '-fuc', script, 'relative-source-fixture',
        File.join(source, 'Scripts', LIBRARY), directory, app
      )
      assert status.success?, "exit=#{status.exitstatus}\n#{output}\n#{errors}"
      assert File.file?(File.join(app, 'Contents/Resources/ManagerRoot/Scripts/ManageFinderExtensions.zsh'))
    end
  end

  def test_entry_locates_resources_after_source_removal_and_uses_external_gui_cache
    fixture do |directory, source, app|
      output, errors, status = prepare(source, app)
      assert status.success?, output + errors
      resources = File.join(app, 'Contents/Resources')
      worker = File.join(resources, 'ManagerRoot/Scripts/ManageFinderExtensions.zsh')
      capture = File.join(directory, 'captured')
      home = File.join(directory, 'home')
      cache = File.join(home, 'Library/Caches/JobsFinderExtensions/Management')
      FileUtils.mkdir_p(cache)
      File.write(worker, <<~'ZSH')
        print -r -- "BUILT=${JOBS_FINDER_BUILT_APP_PATH-unset}" > "$CAPTURE"
        print -r -- "CACHE=$JOBS_FINDER_MANAGER_CACHE_DIR" >> "$CAPTURE"
        print -r -- "LOCALE=$LC_ALL" >> "$CAPTURE"
        printf 'ENTRY:%s\n' "$@" >> "$CAPTURE"
        source "${0:A:h}/FinderManagerGUI.zsh"
        jobs_launch_finder_manager_gui "${0:A}" '' uninstall 1
      ZSH
      binary = File.join(cache, 'SelectFinderExtensionFeatures')
      File.write(binary, "#!/bin/zsh\nprintf 'GUI:%s\\n' \"$@\" >> \"$CAPTURE\"\n")
      File.chmod(0o755, binary)
      File.utime(Time.now + 60, Time.now + 60, binary)
      FileUtils.mv(source, source + '.unavailable')
      environment = { 'HOME' => home, 'CAPTURE' => capture, 'LC_ALL' => 'C', 'LANG' => 'C', 'JOBS_FINDER_BUILT_APP_PATH' => '/developer/source/build/Old.app', 'JOBS_FINDER_CLEANUP_BUILD_PRODUCTS' => '1' }
      output, errors, status = Open3.capture3(environment, '/bin/zsh', File.join(resources, 'ManageInstalledExtensions.zsh'))
      assert status.success?, output + errors
      contents = File.read(capture)
      assert_includes contents, 'BUILT=unset'
      assert_includes contents, 'LOCALE=C'
      assert_includes contents, "CACHE=#{cache}"
      assert_includes contents, "ENTRY:--action\nENTRY:uninstall\nENTRY:--install-location\nENTRY:applications\nENTRY:--gui-session"
      snapshot_worker = contents[/GUI:--manager\nGUI:([^\n]+)/, 1]
      refute_nil snapshot_worker
      assert_match(%r{/JobsFinderManagerSession\.[^/]+/ManagerRoot/Scripts/ManageFinderExtensions\.zsh\z}, snapshot_worker)
      refute_equal worker, snapshot_worker
      refute File.exist?(File.expand_path('../..', snapshot_worker)), 'completed GUI releases its private snapshot'
      assert_includes contents, "GUI:--action\nGUI:uninstall\nGUI:--install-location\nGUI:applications"
      refute_includes contents, '--cleanup-build-products'
      refute File.exist?(File.join(resources, 'ManagerRoot/work'))
      refute_includes contents, '/developer/source'
    end
  end

  def test_running_session_survives_container_removal_and_releases_only_its_snapshot
    fixture do |directory, source, app|
      _, errors, status = prepare(source, app)
      assert status.success?, errors
      resources = File.join(app, 'Contents/Resources')
      worker = File.join(resources, 'ManagerRoot/Scripts/ManageFinderExtensions.zsh')
      capture = File.join(directory, 'session-root')
      release = File.join(directory, 'continue')
      completed = File.join(directory, 'completed')
      session_root = File.join(directory, 'private-sessions')
      FileUtils.mkdir_p(session_root)
      sentinel = File.join(session_root, 'unrelated')
      File.write(sentinel, 'preserved')
      File.write(worker, <<~'ZSH')
        print -r -- "${0:A:h:h}" > "$CAPTURE"
        local_attempt=0
        until [[ -f "$RELEASE" ]]; do
          (( local_attempt += 1 ))
          (( local_attempt < 200 )) || exit 90
          /bin/sleep 0.02
        done
        entries=("${0:A:h:h}"/Jobs*/Scripts/ManageExtension.zsh(N))
        (( ${#entries} == 12 )) || exit 91
        for entry in "${entries[@]}"; do
          [[ -f "$entry" && -r "$entry" ]] || exit 92
        done
        [[ -r "${0:A:h}/SelectFinderExtensionFeatures.swift" && -r "${0:A:h}/FinderManagerGUI.zsh" ]] || exit 93
        print -r -- 'all twelve management units remained readable' > "$COMPLETED"
        exit "${FINAL_STATUS:-0}"
      ZSH
      environment = { 'HOME' => directory, 'TMPDIR' => session_root, 'CAPTURE' => capture, 'RELEASE' => release, 'COMPLETED' => completed }
      Open3.popen3(environment, '/bin/zsh', File.join(resources, 'ManageInstalledExtensions.zsh')) do |input, output, error, waiter|
        input.close
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
        sleep 0.01 until File.file?(capture) || Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        assert File.file?(capture), 'session starts from a complete private snapshot'
        snapshot_manager = File.read(capture).strip
        snapshot = File.dirname(snapshot_manager)
        assert File.directory?(snapshot)
        assert snapshot.start_with?(session_root + '/JobsFinderManagerSession.')
        assert waiter.alive?, 'entry waits for the GUI and worker lifetime'
        FileUtils.remove_entry(app)
        refute File.exist?(app)
        File.write(release, 'continue')
        result = waiter.value
        assert result.success?, output.read + error.read
        assert_equal 'all twelve management units remained readable', File.read(completed).strip
        refute File.exist?(snapshot), 'normal completion removes its private snapshot'
        assert_equal 'preserved', File.read(sentinel)
        assert_empty Dir.glob(File.join(session_root, 'JobsFinderManagerSession.*'))
      end
    end
  end

  def test_independent_package_merges_without_losing_other_installed_managers
    fixture do |directory, source, app|
      _, errors, status = prepare(source, app)
      assert status.success?, errors
      independent = File.join(directory, 'JobsFileCreator')
      prepare_package(independent, 'updated independent copy')
      FileUtils.cp_r(File.join(ROOT, 'Scripts', LIBRARY), File.join(independent, 'Scripts'))
      output, errors, status = prepare(independent, app)
      assert status.success?, output + errors
      manager = File.join(app, 'Contents/Resources/ManagerRoot')
      assert_equal PACKAGES.sort, Dir.children(manager).grep(/^Jobs/).sort
      assert_equal "# updated independent copy\n", File.read(File.join(manager, 'JobsFileCreator/Scripts/ManageExtension.zsh'))
      assert_equal "# JobsPathCopier\n", File.read(File.join(manager, 'JobsPathCopier/Scripts/ManageExtension.zsh'))
      assert File.file?(File.join(manager, 'Scripts', DEPLOYMENT, DEPLOYMENT))
      refute File.exist?(File.join(manager, 'Scripts', DEPLOYMENT, DEPLOYMENT, DEPLOYMENT))
    end
  end

  def test_foreign_container_and_linked_resources_are_rejected
    fixture do |directory, source, app|
      plist = File.join(app, 'Contents/Info.plist')
      File.write(plist, '<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>org.foreign.app</string></dict></plist>')
      _, _, status = prepare(source, app)
      refute status.success?
      refute File.exist?(File.join(app, 'Contents/Resources/ManagerRoot'))
      File.write(plist, '<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.jobs.finderextensions.manager</string></dict></plist>')
      external = File.join(directory, 'external')
      FileUtils.mkdir_p(external)
      File.write(File.join(external, 'sentinel'), 'preserved')
      File.symlink(external, File.join(app, 'Contents/Resources/ManagerRoot'))
      _, _, status = prepare(source, app)
      refute status.success?
      assert_equal 'preserved', File.read(File.join(external, 'sentinel'))
    end
  end

  def test_stage_failure_keeps_previous_manager_root
    fixture do |_directory, source, app|
      _, errors, status = prepare(source, app)
      assert status.success?, errors
      previous = File.join(app, 'Contents/Resources/ManagerRoot/JobsPathCopier/Scripts/ManageExtension.zsh')
      before = File.binread(previous)
      broken = File.join(source, 'JobsPathCopier/Scripts/ManageExtension.zsh')
      FileUtils.rm(broken)
      File.symlink('missing', broken)
      _, _, status = prepare(source, app)
      refute status.success?
      assert_equal before, File.binread(previous)
      assert_empty Dir.glob(File.join(app, 'Contents/Resources/.JobsCombinedManager.*'))
    end
  end
end
