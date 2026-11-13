# frozen_string_literal: true
# 只用临时假 SDK 验证首次初始化的实时进度，不下载、安装或修改真实缓存。
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

require 'fileutils'
require 'json'
require 'minitest/autorun'
require 'open3'
require 'shellwords'
require 'tmpdir'

class SdkDownloadProgressTests < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)
  FILTERS = %w[JobsFlutterDoctor/Scripts/InspectFlutterProject.zsh JobsFlutterCodegen/Scripts/GenerateFlutterCode.zsh
               JobsFlutterTools/Scripts/Tools/InspectFlutterProject.zsh JobsFlutterTools/Scripts/Tools/GenerateFlutterCode.zsh].freeze
  MANAGERS = %w[JobsFlutterVersionMgr/Scripts/ManageFlutterVersion.zsh JobsFlutterTools/Scripts/Tools/ManageFlutterVersion.zsh].freeze
  INSPECTORS = %w[JobsFlutterSdkInspector/Scripts/InspectFlutterSdkVersion.zsh JobsFlutterTools/Scripts/Tools/InspectFlutterSdkVersion.zsh].freeze

  def setup
    @root = Dir.mktmpdir('jobs-sdk-progress-')
    @log = File.join(@root, 'action.log')
    @machine = File.join(@root, 'machine.json')
    @fake = File.join(@root, 'fake flutter 中文')
    File.write(@log, '')
    File.write(@fake, <<~'ZSH')
      #!/bin/zsh
      printf 'Downloading Dart 25%%\r' >&2
      if [[ -n "${FIXTURE_RELEASE:-}" ]]; then
        while [[ ! -f "$FIXTURE_RELEASE" ]]; do /bin/sleep 0.1; done
      else
        /bin/sleep "${FIXTURE_DELAY:-0.2}"
      fi
      printf '100%%\rcomplete-no-newline' >&2
      printf '{"frameworkVersion":"3.99.1"}\n'
      exit "${FIXTURE_RESULT:-0}"
    ZSH
    File.chmod(0o700, @fake)
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def library(relative)
    File.read(File.join(ROOT, relative)).sub(/^main "\$@"\s*\z/, '')
  end

  def capture(relative, body, environment = {})
    Open3.capture3({ 'NO_COLOR' => '1' }.merge(environment), '/bin/zsh', '-f', '-c', library(relative) + "\n" + body)
  end

  def inspector_body
    <<~ZSH
      FSI_LOG_FILE=#{@log.shellescape}
      FSI_MACHINE_FILE=#{@machine.shellescape}
      fsi_probe_with_timeout #{@fake.shellescape} 10
    ZSH
  end

  def test_ansi_filters_stream_carriage_return_before_newline_and_preserve_split_escapes
    FILTERS.each do |relative|
      release = File.join(@root, 'release-filter')
      FileUtils.rm_f(release)
      body = <<~'ZSH'
        { printf '\033[3'; /bin/sleep 0.1; printf '1m25%%\r\033[0m'; while [[ ! -f "$FIXTURE_RELEASE" ]]; do /bin/sleep 0.1; done; printf '\344\270'; /bin/sleep 0.1; printf '\255文尾部'; } | strip_ansi_text
      ZSH
      Open3.popen3({ 'FIXTURE_RELEASE' => release }, '/bin/zsh', '-f', '-c', library(relative) + "\n" + body) do |input, output, errors, process|
        input.close
        first = ''
        begin
          assert IO.select([output], nil, nil, 10), "buffered CR progress: #{relative}"
          first = output.readpartial(4096)
          assert_includes first, "25%\r", relative
          assert process.alive?, relative
        ensure
          File.write(release, '')
        end
        assert_equal "25%\r中文尾部".b, (first + output.read).b, relative
        assert process.value.success?, errors.read
      end
    end
  end

  def test_osc_titles_do_not_swallow_download_lines_between_them
    FILTERS.each do |relative|
      body = <<~'ZSH'
        { printf '\033]0;first\033'; /bin/sleep 0.1; printf '\\\nDownloading SDK 25%%\r\n\033]0;second\033\\\nDone\n'; } | strip_ansi_text
      ZSH
      output, errors, result = capture(relative, body)
      assert result.success?, errors
      assert_equal "\nDownloading SDK 25%\r\n\nDone\n", output, relative
    end
  end

  def test_version_manager_keeps_machine_json_separate_and_preserves_failure
    MANAGERS.each do |relative|
      [0, 7].each do |code|
        body = <<~ZSH
          FM_FVM=#{@fake.shellescape}
          FM_RUN_DIR=#{@root.shellescape}
          LOG_FILE=#{@log.shellescape}
          fm_capture_flutter_version
        ZSH
        output, errors, result = capture(relative, body, 'FIXTURE_RESULT' => code.to_s)
        assert_equal code, result.exitstatus, errors
        assert_equal '3.99.1', JSON.parse(output)['frameworkVersion']
        assert_equal output.b, File.binread(File.join(@root, 'flutter-machine.json'))
        assert_includes errors, "25%\r100%\rcomplete-no-newline"
        assert_includes File.read(@log), "25%\r100%\rcomplete-no-newline"
      end
    end
  end

  def test_inspectors_stream_sdk_bootstrap_and_keep_parseable_machine_file
    INSPECTORS.each do |relative|
      [0, 7].each do |code|
        output, errors, result = capture(relative, inspector_body, 'FIXTURE_RESULT' => code.to_s)
        assert_equal code, result.exitstatus, errors
        assert_equal '3.99.1', JSON.parse(output)['frameworkVersion']
        assert_equal output.b, File.binread("#{@machine}.raw")
        assert_includes errors, "25%\r100%\rcomplete-no-newline"
        assert_includes File.read(@log), "25%\r100%\rcomplete-no-newline"
      end
    end
  end

  def test_inspector_exposes_live_stderr_before_sdk_exits
    INSPECTORS.each do |relative|
      release = File.join(@root, 'release-inspector')
      FileUtils.rm_f(release)
      Open3.popen3({ 'FIXTURE_RELEASE' => release }, '/bin/zsh', '-f', '-c', library(relative) + "\n" + inspector_body) do |input, output, errors, process|
        input.close
        begin
          assert IO.select([errors], nil, nil, 8), relative
          assert_includes errors.readpartial(4096), "Downloading Dart 25%\r"
          assert process.alive?, relative
        ensure
          File.write(release, '')
        end
        output.read
        errors.read
        assert process.value.success?, relative
      end
    end
  end

  def test_system_flutter_homebrew_install_preserves_tty_and_user_cancel_code
    [0, 130].each do |code|
      File.write(@fake, <<~'ZSH')
        #!/bin/zsh
        [[ -t 1 && "$*" == 'install --cask flutter' ]] || exit 81
        printf 'Flutter Cask 25%%\r100%%\n'
        exit "${FIXTURE_RESULT:-0}"
      ZSH
      body = <<~ZSH
        SF_PROJECT=#{@root.shellescape}
        PE_RUN_DIR=#{@root.shellescape}
        PE_LOG_FILE=#{@log.shellescape}
        PJ_BREW=#{@fake.shellescape}
        PJ_BREW_PREFIX=#{@root.shellescape}
        pe_select() { PE_SELECTION=install; }
        pj_find_brew() { return 0; }
        sf_probe_flutter() { return 0; }
        sf_prepare_system_flutter
      ZSH
      source = "source #{File.join(ROOT, 'JobsFlutterTools/Scripts/Tools/ProjectEnvironment.zsh').shellescape}\n" +
               "source #{File.join(ROOT, 'JobsFlutterTools/Scripts/Tools/SetupFlutterProject.zsh').shellescape}\n"
      output, errors, result = Open3.capture3({ 'FIXTURE_RESULT' => code.to_s }, '/bin/zsh', '-f', '-c', source + "\n" + body, stdin_data: "y\n")
      assert_equal code, result.exitstatus, output + errors
      assert_includes output, "Flutter Cask 25%\r100%"
      assert_includes File.read(@log), 'Flutter Cask 25%'
    end
  end

  def test_inspector_timeout_remains_bounded
    INSPECTORS.each do |relative|
      output, errors, result = capture(relative, inspector_body.sub(' 10', ' 0'), 'FIXTURE_DELAY' => '3')
      assert_equal 124, result.exitstatus, errors
      assert_includes output, 'SDK 版本查询超时'
    end
  end
end
