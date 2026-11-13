# frozen_string_literal: true
# Created by Jobs on 2026年11月4日，星期三。
# 隔离目录、已有 Node 和假安装器验证工具链准备；不联网、不安装真实软件、不操作系统配置。
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
require 'digest'
require 'json'
require 'minitest/autorun'
require 'open3'
require 'shellwords'
require 'tmpdir'

class ProjectToolchainTests < Minitest::Test
  TOOLS = File.expand_path('../Scripts/Tools', __dir__)
  HELPER = File.join(TOOLS, '【MacOS】工程依赖工具链.zsh/【MacOS】工程依赖工具链.zsh')

  def setup
    @root = File.realpath(Dir.mktmpdir('jobs-project-toolchain-'))
    @project = File.join(@root, 'project 中文')
    @bin = File.join(@root, 'bin')
    @run = File.join(@root, 'run')
    @home = File.join(@root, 'home')
    @tool = File.join(@root, 'DevEco.app/Contents')
    @trace = File.join(@root, 'trace')
    FileUtils.mkdir_p([@project, @bin, @run, @home])
    File.write(File.join(@project, 'package.json'), '{}')
    @node = ['/opt/homebrew/bin/node', '/usr/local/bin/node'].find { |p| File.executable?(p) }
    @npm = @node && File.join(File.dirname(@node), 'npm')
    @env = { 'HOME' => @home, 'PATH' => "#{@bin}:/usr/bin:/bin:/usr/sbin:/sbin", 'PT_TEST_PROJECT' => @project,
             'PT_TEST_RUN' => @run, 'PT_TEST_TOOLS' => TOOLS, 'PT_TEST_HELPER' => HELPER, 'PT_TEST_TRACE' => @trace,
             'PT_TEST_NODE' => @node.to_s, 'PT_TEST_NPM' => @npm.to_s, 'PT_TEST_ROOT' => @root,
             'DEVECO_STUDIO_HOME' => '', 'TOOL_HOME' => '', 'DEVECO_SDK_HOME' => '', 'HOS_SDK_HOME' => '',
             'OHOS_SDK_HOME' => '', 'NODE_HOME' => '', 'JAVA_HOME' => '' }
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def command(path, body)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "#!/bin/zsh\n#{body}\n")
    File.chmod(0o755, path)
  end

  def shell(body, env: {}, input: '')
    bootstrap = <<~'ZSH'
      source "$PT_TEST_TOOLS/ProjectEnvironment.zsh" || exit $?
      source "$PT_TEST_HELPER" || exit $?
      SF_PROJECT="$PT_TEST_PROJECT" PE_RUN_DIR="$PT_TEST_RUN" PE_TOOLS_DIR="$PT_TEST_TOOLS"
      PE_LOG_FILE="$PE_RUN_DIR/environment.log"
      pe_select() { PE_SELECTION="${PT_TEST_CHOICE:-stop}"; }
      jobs_sdk_retry() { shift 2; "$@"; }
      sf_run_diagnostic() {
        local name="$1" result=0; shift
        print -r -- "$name|$*" >> "$PT_TEST_TRACE"
        if [[ "$name" == node-shasums || "$name" == node-download ]]; then
          local destination="" parameter="" previous=""
          for parameter in "$@"; do [[ "$previous" != --output ]] || destination="$parameter"; previous="$parameter"; done
          [[ -n "$destination" ]] || return 97
          if [[ "$name" == node-shasums ]]; then /bin/cp "$PT_TEST_SHASUMS" "$destination"; else /bin/cp "$PT_TEST_ARCHIVE" "$destination"; fi
          return $?
        fi
        [[ "$1" != /usr/bin/curl && "$1" != /usr/bin/open ]] || return 98
        if [[ "$name" == *-install && "${1:A}" == "${PT_TEST_NPM:A}" ]]; then return 98; fi
        (cd "${SF_COMMAND_DIRECTORY:-$SF_PROJECT}" && "$@") > "$PE_RUN_DIR/$name.log" 2>&1 || result=$?
        return "$result"
      }
    ZSH
    Open3.capture3(@env.merge(env), '/bin/zsh', '-f', '-c', bootstrap + body, stdin_data: input)
  end

  def assert_success(result)
    out, err, status = result
    assert status.success?, out + err
    result
  end

  def native_node
    skip '需要已有 Node/npm；测试不安装它们' unless @node && File.executable?(@npm)
    File.symlink(@node, File.join(@bin, 'node'))
    File.symlink(@npm, File.join(@bin, 'npm'))
  end

  def ohos_toolchain
    %w[ets native toolchains].each { |part| FileUtils.mkdir_p(File.join(@tool, 'sdk/default/openharmony', part)) }
    { 'node/bin/node' => "print v22.11.0", 'ohpm/bin/ohpm' => 'print 5.0.0',
      'hvigor/bin/hvigorw' => 'echo 5.0.0', 'sdk/default/openharmony/toolchains/hdc' => 'print 3.1.0',
      'jbr/Contents/Home/bin/java' => 'print 21.0.0' }.each { |p, body| command(File.join(@tool, p), body) }
    FileUtils.mkdir_p(File.join(@project, 'ohos'))
    command(File.join(@bin, 'flutter'), 'print "Harmony HAP build help"')
  end

  def test_native_node_engine_and_version_file_are_checked_without_install
    native_node
    version, = Open3.capture2(@node, '-p', 'process.versions.node')
    major = version.split('.').first
    File.write(File.join(@project, 'package.json'), JSON.generate('engines' => { 'node' => ">=#{major}.0.0 <#{major.to_i + 1}.0.0" }))
    File.write(File.join(@project, '.nvmrc'), version)
    assert_success shell('pt_read_node_requirements "$SF_PROJECT" && pt_probe_node "$(command -v node)"')
    refute File.read(@trace).include?('install')
    File.write(File.join(@project, '.nvmrc'), '1.0.0')
    _, _, status = shell('pt_read_node_requirements "$SF_PROJECT" && pt_probe_node "$(command -v node)"')
    assert_equal 3, status.exitstatus
  end

  def test_locked_package_manager_must_match_lock_type_before_install
    native_node
    File.write(File.join(@project, 'package.json'), '{"packageManager":"yarn@4.9.0"}')
    _, _, status = shell('pt_prepare_web_toolchain "$SF_PROJECT" pnpm-lock.yaml')
    assert_equal 3, status.exitstatus
    refute File.read(@trace).include?(' install ')
  end

  def test_missing_exact_package_manager_is_installed_only_in_user_version_directory_and_verified
    native_node
    File.delete(File.join(@bin, 'npm'))
    command(File.join(@bin, 'npm'), <<~'ZSH')
      [[ "$1" != --version ]] || { print 10.0.0; exit 0; }
      [[ "$1" == install && "$2" == --prefix ]] || exit 90
      /bin/mkdir -p "$3/node_modules/.bin"
      /usr/bin/printf '#!/bin/zsh\nprint 9.15.4\n' > "$3/node_modules/.bin/pnpm"
      /bin/chmod 755 "$3/node_modules/.bin/pnpm"
    ZSH
    File.write(File.join(@project, 'package.json'), '{"packageManager":"pnpm@9.15.4"}')
    assert_success shell('pt_prepare_web_toolchain "$SF_PROJECT" pnpm-lock.yaml; result=$?; print -r -- "$PT_PACKAGE_MANAGER"; exit "$result"', env: { 'PT_TEST_CHOICE' => 'install' })
    installed = File.join(@home, 'Library/Application Support/JobsFlutterTools/package-managers/pnpm/9.15.4/node_modules/.bin/pnpm')
    assert File.executable?(installed)
    trace = File.read(@trace)
    assert_includes trace, 'pnpm@9.15.4'
    refute_includes trace, '--global'
    refute File.exist?(File.join(@project, 'node_modules'))
  end

  def test_install_failure_and_failed_post_install_health_stop_the_chain
    native_node
    File.delete(File.join(@bin, 'npm'))
    command(File.join(@bin, 'npm'), '[[ "$1" != --version ]] || { print 10.0.0; exit 0; }; exit 47')
    File.write(File.join(@project, 'package.json'), '{"packageManager":"pnpm@9.15.4"}')
    _, _, status = shell('pt_prepare_web_toolchain "$SF_PROJECT" pnpm-lock.yaml && touch "$PT_TEST_ROOT/BUSINESS"', env: { 'PT_TEST_CHOICE' => 'install' })
    assert_equal 47, status.exitstatus
    refute File.exist?(File.join(@root, 'BUSINESS'))
    command(File.join(@bin, 'npm'), <<~'ZSH')
      [[ "$1" != --version ]] || { print 10.0.0; exit 0; }
      /bin/mkdir -p "$3/node_modules/.bin"
      /usr/bin/printf '#!/bin/zsh\nprint 99.0.0\n' > "$3/node_modules/.bin/pnpm"
      /bin/chmod 755 "$3/node_modules/.bin/pnpm"
    ZSH
    _, _, status = shell('pt_prepare_web_toolchain "$SF_PROJECT" pnpm-lock.yaml && touch "$PT_TEST_ROOT/BUSINESS"', env: { 'PT_TEST_CHOICE' => 'install' })
    assert_equal 3, status.exitstatus
    refute File.exist?(File.join(@root, 'BUSINESS'))
  end

  def test_cancel_missing_tool_does_not_install_or_start_business
    native_node
    File.write(File.join(@project, '.nvmrc'), '1.0.0')
    _, _, status = shell('pt_prepare_web_toolchain "$SF_PROJECT" pnpm-lock.yaml && touch "$PT_TEST_ROOT/BUSINESS"')
    assert_equal 3, status.exitstatus
    refute File.exist?(File.join(@root, 'BUSINESS'))
    refute File.exist?(File.join(@home, 'Library'))
  end

  def test_ohos_discovers_selected_studio_and_activates_complete_toolchain_in_same_process
    ohos_toolchain
    out, = assert_success shell(<<~'ZSH', env: { 'DEVECO_STUDIO_HOME' => File.dirname(@tool) })
      SF_FLUTTER="$(command -v flutter)"
      pt_prepare_ohos_toolchain || exit $?
      print -r -- "$OHOS_SDK_HOME|$DEVECO_SDK_HOME|$PT_OHPM|$PT_HVIGOR|$SF_JAVA_HOME"
    ZSH
    assert_includes out, File.join(@tool, 'sdk/default/openharmony')
    %w[ohos-node ohpm-version hvigor-version hdc-version ohos-java ohos-sdk].each { |name| assert_includes File.read(@trace), name }
    refute File.exist?(File.join(@home, '.zshrc'))
  end

  def test_ohos_missing_sdk_component_never_executes_package_tools
    ohos_toolchain
    FileUtils.remove_entry(File.join(@tool, 'sdk/default/openharmony/native'))
    _, _, status = shell('SF_FLUTTER="$(command -v flutter)"; pt_prepare_ohos_toolchain && touch "$PT_TEST_ROOT/BUSINESS"', env: { 'DEVECO_STUDIO_HOME' => @tool })
    assert_equal 3, status.exitstatus
    refute File.exist?(@trace)
    refute File.exist?(File.join(@root, 'BUSINESS'))
  end

  def test_ohos_unhealthy_tool_requires_repair_and_does_not_run_business
    ohos_toolchain
    command(File.join(@tool, 'ohpm/bin/ohpm'), 'exit 54')
    _, _, status = shell('SF_FLUTTER="$(command -v flutter)"; pt_prepare_ohos_toolchain && touch "$PT_TEST_ROOT/BUSINESS"', env: { 'DEVECO_STUDIO_HOME' => @tool })
    assert_equal 3, status.exitstatus
    assert_includes File.read(@trace), 'ohpm-version'
    refute_includes File.read(@trace), 'hvigor-version'
    refute File.exist?(File.join(@root, 'BUSINESS'))
  end

  def test_failed_ohos_selection_restores_environment_before_next_root
    ohos_toolchain
    command(File.join(@tool, 'ohpm/bin/ohpm'), 'exit 54')
    out, = assert_success shell(<<~'ZSH', env: { 'DEVECO_STUDIO_HOME' => @tool })
      SF_FLUTTER="$(command -v flutter)"
      original="$PATH"
      PT_OHOS_ROOT="$DEVECO_STUDIO_HOME"
      pt_try_ohos_root
      [[ "$PATH" == "$original" && -z "$DEVECO_SDK_HOME" && -z "$OHOS_SDK_HOME" && -z "$TOOL_HOME" && -z "$SF_JAVA_HOME" ]] || exit 91
      print restored
    ZSH
    assert_includes out, 'restored'
  end

  def test_exact_node_archive_is_checksum_verified_reused_and_does_not_use_brew
    architecture, = Open3.capture2('/usr/bin/uname', '-m')
    architecture = architecture.strip == 'arm64' ? 'arm64' : 'x64'
    folder = "node-v1.2.3-darwin-#{architecture}"
    payload = File.join(@root, 'payload')
    command(File.join(payload, folder, 'bin/node'), 'print v1.2.3')
    command(File.join(payload, folder, 'bin/npm'), 'print 1.0.0')
    archive = File.join(@root, 'node.tar.gz')
    _, _, status = Open3.capture3('/usr/bin/tar', '-czf', archive, '-C', payload, folder)
    assert status.success?
    shasums = File.join(@root, 'SHASUMS256.txt')
    File.write(shasums, "#{Digest::SHA256.file(archive).hexdigest}  #{folder}.tar.gz\n")
    assert_success shell(<<~'ZSH', env: { 'PT_TEST_ARCHIVE' => archive, 'PT_TEST_SHASUMS' => shasums })
      pt_probe_node() {
        [[ -x "$1" && "$("$1" --version)" == v1.2.3 ]] || return 1
        PT_NODE="$1"
      }
      pt_install_node_exact 1.2.3 && pt_install_node_exact 1.2.3
    ZSH
    trace = File.read(@trace)
    assert_equal 1, trace.lines.count { |line| line.start_with?('node-download|') }
    assert_equal 1, trace.lines.count { |line| line.start_with?('node-shasums|') }
    assert File.executable?(File.join(@home, "Library/Caches/JobsFlutterTools/node/v1.2.3/#{architecture}/#{folder}/bin/node"))
    refute_includes trace, 'brew'
  end

  def test_spm_merge_rejects_target_ancestor_link_before_copying_any_file
    source = File.join(@root, 'spm-source')
    target = File.join(@root, 'spm-target')
    external = File.join(@root, 'external')
    FileUtils.mkdir_p([File.join(source, 'nested'), target, external])
    File.write(File.join(source, 'a-first'), 'must stay absent')
    File.write(File.join(source, 'nested/private.swift'), 'private')
    File.symlink(external, File.join(target, 'nested'))
    _, _, status = shell("pt_merge_spm_cache #{source.shellescape} #{target.shellescape}")
    refute status.success?
    assert_empty Dir.children(external)
    refute File.exist?(File.join(target, 'a-first'))
    assert File.symlink?(File.join(target, 'nested'))
  end
end
