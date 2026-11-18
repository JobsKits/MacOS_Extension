# frozen_string_literal: true
#
# InstallerTests.rb
# JobsFileCreator
#
# Created by Jobs on 2026年10月29日，星期四.
#
# 复制后台管理器到临时目录，硬替换全部系统写命令，不运行真实扩展管理。

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

class FileCreatorInstallerTests < Minitest::Test
  SYSTEM_WRITES = %w[/usr/bin/xcodebuild /usr/bin/codesign /usr/bin/open /usr/bin/pluginkit /usr/bin/pkill /usr/bin/killall /bin/sleep].freeze
  LSREGISTER = '/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'

  def setup
    @temporary = File.realpath(Dir.mktmpdir('JobsFileCreator-Installer-'))
    @package = File.join(@temporary, '独立 功能包')
    @script = File.join(@package, 'Scripts/ManageExtension.zsh')
    @calls = File.join(@temporary, 'calls.log')
    @app = File.join(@package, 'work/DerivedData/Build/Products/Debug/JobsFileCreator.app')
    @extension = File.join(@app, 'Contents/PlugIns/JobsFileCreatorFinderSync.appex')
    FileUtils.mkdir_p(File.dirname(@script))
    source = File.read(File.expand_path('../Scripts/【MacOS】ManageExtension.zsh/【MacOS】ManageExtension.zsh', File.dirname(__dir__)))
    (SYSTEM_WRITES + [LSREGISTER]).each do |command|
      raise "fixture did not intercept #{command}" unless source.include?(command)
      replacement = File.join(@temporary, File.basename(command))
      File.write(replacement, stub_source)
      File.chmod(0o700, replacement)
      source = source.gsub(command, replacement)
    end
    (SYSTEM_WRITES + [LSREGISTER]).each do |command|
      raise "unsafe command remains: #{command}" if source.include?(command)
    end
    File.write(@script, source)
    @environment = {
      'TASK_CALLS' => @calls, 'TASK_APP' => @app, 'TASK_EXTENSION' => @extension,
      'TASK_REGISTRATION_COUNT' => File.join(@temporary, 'registration-count'),
      'TMPDIR' => @temporary + '/', 'NO_COLOR' => '1'
    }
  end

  def teardown
    FileUtils.remove_entry(@temporary)
  end

  def run_manager(*arguments, environment: {})
    Open3.capture3(@environment.merge(environment), '/bin/zsh', @script, *arguments)
  end

  def calls
    File.exist?(@calls) ? File.readlines(@calls, chomp: true) : []
  end

  def stub_source
    <<~'SHELL'
      #!/bin/zsh
      name="${0:t}"
      print -r -- "$name $*" >> "$TASK_CALLS"
      case "$name" in
        xcodebuild)
          (( ${TASK_BUILD_STATUS:-0} == 0 )) || exit "$TASK_BUILD_STATUS"
          /bin/mkdir -p "$TASK_APP/Contents" "$TASK_EXTENSION/Contents"
          print -r -- '<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.jobs.filecreator</string></dict></plist>' > "$TASK_APP/Contents/Info.plist"
          print -r -- '<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.jobs.filecreator.findersync</string></dict></plist>' > "$TASK_EXTENSION/Contents/Info.plist"
          ;;
        pluginkit)
          if [[ "$1" == -a ]]; then
            attempt=0
            [[ ! -f "$TASK_REGISTRATION_COUNT" ]] || read -r attempt < "$TASK_REGISTRATION_COUNT"
            attempt=$((attempt + 1))
            print -r -- "$attempt" > "$TASK_REGISTRATION_COUNT"
            if (( attempt == 2 && ${TASK_RETRY_ADD_STATUS:-0} != 0 )); then
              exit "$TASK_RETRY_ADD_STATUS"
            fi
          elif [[ "$*" == '-m -A -D -vv -i com.jobs.filecreator.findersync' ]]; then
            print -r -- "    Path = $TASK_EXTENSION"
            [[ -z "${TASK_EXTRA_EXTENSION:-}" ]] || print -r -- "    Path = $TASK_EXTRA_EXTENSION"
          elif [[ "$*" == '-m -A -v -i com.jobs.filecreator.findersync' ]]; then
            attempt=0
            [[ ! -f "$TASK_REGISTRATION_COUNT" ]] || read -r attempt < "$TASK_REGISTRATION_COUNT"
            case "${TASK_REGISTRATION_MODE:-immediate}" in
              after-retry) (( attempt >= 2 )) || exit 0 ;;
              missing) exit 0 ;;
              disabled) print -r -- "- com.jobs.filecreator.findersync(1)    $TASK_EXTENSION"; exit 0 ;;
              old-path) print -r -- "+ com.jobs.filecreator.findersync(1)    $TASK_EXTENSION-old"; exit 0 ;;
            esac
            print -r -- "+ com.jobs.filecreator.findersync(1)    $TASK_EXTENSION"
          fi
          ;;
      esac
      exit 0
    SHELL
  end

  def install(*extra, environment: {})
    run_manager('--action', 'install', '--features', 'file-create', '--non-interactive', *extra, environment: environment)
  end

  def test_rejected_arguments_stop_before_system_commands
    [
      ['--non-interactive'],
      ['--action', 'unknown', '--non-interactive'],
      ['--features', 'hidden-files-toggle', '--non-interactive', '--action', 'install'],
      ['--features', 'file-create,file-create', '--non-interactive', '--action', 'install'],
      ['--action', 'install', '--non-interactive', '--unexpected']
    ].each do |arguments|
      _output, _error, status = run_manager(*arguments)
      assert_equal 2, status.exitstatus
      assert_empty calls
      refute File.exist?(File.join(@package, 'work'))
    end
  end

  def test_help_is_read_only
    output, _error, status = run_manager('--help')
    assert status.success?
    assert_includes output, '--action install|uninstall'
    assert_empty calls
    refute File.exist?(File.join(@package, 'work'))
  end

  def test_install_verifies_then_registers_exact_product
    output, error, status = install
    assert status.success?, output + error
    assert_equal %w[xcodebuild codesign lsregister open pluginkit pluginkit pluginkit killall], calls.map { |line| line.split.first }
    assert_includes calls, 'codesign --verify --deep --strict ' + @app
    assert_includes calls, 'lsregister -f ' + @app
    assert_includes calls, 'open -gj ' + @app + ' --args --initialize-finder-extension'
    assert_includes calls, 'pluginkit -a ' + @extension
    assert_includes calls, 'pluginkit -e use -i com.jobs.filecreator.findersync'
    assert_includes output, "JOBS_MANAGER_EVENT\tfile-create\tsucceeded"
    refute File.exist?(File.join(@package, 'work/.manager-lock'))
    log = File.read(File.join(@temporary, 'JobsFileCreatorManage.log'))
    assert_includes log, '核心用途'
    assert_includes log, "JOBS_MANAGER_EVENT\tfile-create\tsucceeded"
  end

  def test_skip_restart_leaves_refresh_to_outer_manager
    output, error, status = install('--skip-finder-restart')
    assert status.success?, output + error
    refute calls.any? { |line| line.start_with?('killall ') }
  end

  def test_first_registration_can_be_rediscovered_once_after_a_successful_but_invisible_add
    output, error, status = install(environment: { 'TASK_REGISTRATION_MODE' => 'after-retry' })
    assert status.success?, output + error
    assert_equal 2, calls.count { |line| line == 'pluginkit -a ' + @extension }
    assert_equal 2, calls.count { |line| line == 'pluginkit -e use -i com.jobs.filecreator.findersync' }
    assert_equal ['xcodebuild'], calls.grep(/^xcodebuild /).map { |line| line.split.first }
    assert_includes output, "JOBS_MANAGER_EVENT\tfile-create\tsucceeded"
    refute File.exist?(File.join(@package, 'work/.manager-lock'))
  end

  def test_second_registration_failure_keeps_its_exit_code_and_does_not_claim_success
    output, error, status = install(environment: {
      'TASK_REGISTRATION_MODE' => 'after-retry', 'TASK_RETRY_ADD_STATUS' => '41'
    })
    assert_equal 41, status.exitstatus, output + error
    assert_equal 2, calls.count { |line| line == 'pluginkit -a ' + @extension }
    refute calls.any? { |line| line.start_with?('killall ') }
    assert_includes output, "JOBS_MANAGER_EVENT\tfile-create\tfailed"
    refute_includes output, "JOBS_MANAGER_EVENT\tfile-create\tsucceeded"
    refute File.exist?(File.join(@package, 'work/.manager-lock'))
  end

  def test_missing_disabled_and_old_path_records_never_turn_the_installation_green
    %w[missing disabled old-path].each do |mode|
      FileUtils.rm_f([@calls, @environment['TASK_REGISTRATION_COUNT']])
      output, error, status = install(environment: { 'TASK_REGISTRATION_MODE' => mode })
      refute status.success?, mode + output + error
      assert_equal 2, calls.count { |line| line == 'pluginkit -a ' + @extension }, mode
      assert_includes output, "JOBS_MANAGER_EVENT\tfile-create\tfailed"
      refute_includes output, "JOBS_MANAGER_EVENT\tfile-create\tsucceeded"
      refute calls.any? { |line| line.start_with?('killall ') }, mode
    end
  end

  def test_build_failure_stops_registration_and_releases_lock
    output, _error, status = install(environment: { 'TASK_BUILD_STATUS' => '6' })
    assert_equal 6, status.exitstatus
    assert_equal ['xcodebuild'], calls.map { |line| line.split.first }
    assert_includes output, "JOBS_MANAGER_EVENT\tfile-create\tfailed"
    refute File.exist?(File.join(@package, 'work/.manager-lock'))
  end

  def test_existing_lock_stops_before_system_commands
    lock = File.join(@package, 'work/.manager-lock')
    FileUtils.mkdir_p(lock)
    output, _error, status = install
    assert_equal 1, status.exitstatus
    assert_includes output, '已有管理任务'
    assert_empty calls
    assert File.directory?(lock)
  end

  def test_uninstall_ignores_unowned_paths_and_keeps_app
    output, error, status = install('--skip-finder-restart')
    assert status.success?, output + error
    File.write(@calls, '')
    alien = File.join(@temporary, 'Other.app/Contents/PlugIns/Other.appex')
    FileUtils.mkdir_p(alien)
    output, error, status = run_manager('--action', 'uninstall', '--non-interactive', '--skip-finder-restart',
                                        environment: { 'TASK_EXTRA_EXTENSION' => alien })
    assert status.success?, output + error
    assert_equal 'pluginkit -e ignore -i com.jobs.filecreator.findersync', calls.first
    assert_includes calls, 'pluginkit -r ' + @extension
    assert_includes calls, 'lsregister -u ' + @app
    refute calls.any? { |line| line.include?(alien) || line.start_with?('killall ') }
    assert File.directory?(@app)
    assert File.directory?(alien)
  end

  def test_copied_package_opens_gui_with_only_file_create_scope
    helper = File.join(@package, 'Scripts/FinderManagerGUI.zsh')
    File.write(helper, <<~'ZSH')
      jobs_launch_finder_manager_gui() {
        /usr/bin/printf 'GUI:%s:%s:%s:%s\n' "$1" "$2" "$3" "$4"
      }
    ZSH
    output, error, status = run_manager('--gui-session', '--action', 'uninstall')
    assert status.success?, output + error
    assert_includes output, "GUI:#{@script}:file-create:uninstall:1"
    assert_empty calls
    refute File.exist?(File.join(@package, 'work'))
  end
end
