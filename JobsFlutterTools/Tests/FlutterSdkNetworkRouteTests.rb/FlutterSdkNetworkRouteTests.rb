# Created by Jobs. All network and SDK commands are fixtures; no external request is made.
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
require 'timeout'
require 'json'

class FlutterSdkNetworkRouteTests < Minitest::Test
  ROOT = File.expand_path('../../..', __dir__)
  MODULE = File.join(ROOT, 'JobsFlutterTools/Scripts/Tools/【MacOS】FlutterSDK网络选路.zsh/【MacOS】FlutterSDK网络选路.zsh')
  ENGINE = 'a' * 40
  KEYS = %w[FLUTTER_STORAGE_BASE_URL PUB_HOSTED_URL HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy NO_PROXY no_proxy CURL_HOME XDG_CONFIG_HOME FLUTTER_PREBUILT_ENGINE_VERSION JOBS_FLUTTER_ROUTE_CACHE_DIR].freeze

  def setup
    @tmp = Dir.mktmpdir('jobs-sdk-network-route-')
    @sdk = File.join(@tmp, 'sdk')
    @curl = File.join(@tmp, 'curl')
    @log = File.join(@tmp, 'route.log')
    @calls = File.join(@tmp, 'curl.calls')
    @count = File.join(@tmp, 'sdk.count')
    @source = File.join(@tmp, 'sdk.source')
    FileUtils.mkdir_p([File.join(@sdk, 'bin/internal'), File.join(@sdk, 'bin/cache')])
    File.write(File.join(@sdk, 'bin/internal/engine.version'), ENGINE + "\n")
    File.write(File.join(@sdk, 'version'), '3.38.4')
    arch, = Open3.capture2('/usr/sbin/sysctl', '-n', 'hw.optional.arm64')
    @arch = arch.strip == '1' ? 'arm64' : 'x64'
    object = "flutter/#{ENGINE}/dart-sdk-darwin-#{@arch}.zip"
    File.write(File.join(@tmp, 'metadata.json'), JSON.generate({ name: object, size: '1000000', md5Hash: 'qqqqqqqqqqqqqqqqqqqqqg==' }))
    archive = "stable/macos/flutter_macos_#{@arch}_3.50.1-stable.zip"
    File.write(File.join(@tmp, 'releases.json'), JSON.generate({ current_release: { stable: 'c' * 40 }, releases: [{ version: '3.50.1', hash: 'c' * 40, dart_sdk_arch: @arch, archive: archive, sha256: '1' * 64 }] }))
    File.write(File.join(@tmp, 'archive_metadata.json'), JSON.generate({ name: "releases/#{archive}", size: '1000000', md5Hash: 'qqqqqqqqqqqqqqqqqqqqqg==' }))
    File.binwrite(File.join(@tmp, 'sample'), 'PK' + ('a' * 262142))
    File.write(@curl, <<~'SH')
      #!/bin/zsh
      output='' headers='' url=''
      while (( $# )); do
        case "$1" in
          --output) output="$2"; shift 2 ;;
          --dump-header) headers="$2"; shift 2 ;;
          --write-out|--range|--proxy|--proto|--proto-redir|--max-filesize|--header|--connect-timeout|--max-time|--max-redirs) shift 2 ;;
          http*) url="$1"; shift ;;
          *) shift ;;
        esac
      done
      print -r -- "$url" >> "$FIXTURE_CURL_CALLS"
      [[ "${FIXTURE_OFFLINE:-0}" != 1 ]] || exit 35
      if [[ "${FIXTURE_GOOGLE_OFFLINE:-0}" == 1 && ( "$url" == *www.googleapis.com* || "$url" == *storage.googleapis.com* ) ]]; then exit 35; fi
      if [[ "$url" == *releases_macos.json* ]]; then /bin/cp "$FIXTURE_ROOT/releases.json" "$output"; exit 0; fi
      if [[ "$url" == https://www.googleapis.com/* && "$url" == *releases%2Fstable* ]]; then /bin/cp "$FIXTURE_ROOT/archive_metadata.json" "$output"; exit 0; fi
      if [[ "$url" == https://www.googleapis.com/* ]]; then
        /bin/cp "$FIXTURE_ROOT/metadata.json" "$output"
        exit 0
      fi
      if [[ "$url" == https://fvm.example.invalid/install.sh ]]; then
        printf '#!/bin/sh\n# fvm fixture installer\n' > "$output"
        printf 'HTTP/1.1 200 OK\r\nContent-Length: 35\r\n\r\n' > "$headers"
        printf '200\t0.05\t1000000\t0.10'
        exit 0
      fi
      /bin/cp "$FIXTURE_ROOT/sample" "$output"
      printf 'HTTP/1.1 206 Partial Content\r\nContent-Range: bytes 0-262143/1000000\r\nETag: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"\r\n\r\n' > "$headers"
      if [[ "${FIXTURE_BAD_MIRROR:-0}" == 1 && "$url" == *storage.flutter-io.cn* ]]; then
        printf '<html>wrong SDK</html>' > "$output"
      fi
      if [[ "$url" == *storage.flutter-io.cn* ]]; then printf '206\t0.05\t4000000\t0.10'; else printf '206\t0.2\t400000\t0.60'; fi
    SH
    File.chmod(0o700, @curl)
    File.write(File.join(@sdk, 'bin/flutter'), <<~'SH')
      #!/bin/zsh
      count=0; [[ ! -f "$FIXTURE_SDK_COUNT" ]] || count=$(<"$FIXTURE_SDK_COUNT")
      (( count++ )); print "$count" > "$FIXTURE_SDK_COUNT"
      print -r -- "${+FLUTTER_STORAGE_BASE_URL}:$FLUTTER_STORAGE_BASE_URL|${+HTTPS_PROXY}:$HTTPS_PROXY" > "$FIXTURE_SDK_SOURCE"
      print -r -- "$JOBS_FLUTTER_ROUTE_RESOLVED_VERSION|$JOBS_FLUTTER_ROUTE_OBJECT_PATH|$JOBS_FLUTTER_ROUTE_EXPECTED_SHA256" > "$FIXTURE_ROOT/sdk.target"
      if [[ "${FIXTURE_FAIL_ONCE:-0}" == 1 && "$count" == 1 ]]; then print 'Connection reset' >> "$FIXTURE_LOG"; exit 9; fi
      if [[ "${FIXTURE_MIRROR_DOWNLOAD_FAILS:-0}" == 1 && "$FLUTTER_STORAGE_BASE_URL" == *storage.flutter-io.cn* ]]; then print 'Connection reset' >> "$FIXTURE_LOG"; exit 9; fi
      print '{"sdk":"ready"}'
      exit "${FIXTURE_SDK_EXIT:-0}"
    SH
    File.chmod(0o700, File.join(@sdk, 'bin/flutter'))
  end

  def teardown
    FileUtils.remove_entry(@tmp)
  end

  def env(extra = {})
    KEYS.to_h { |k| [k, nil] }.merge('HOME' => @tmp, 'TMPDIR' => @tmp + '/', 'NO_COLOR' => '1', 'JOBS_FLUTTER_ROUTE_CURL' => @curl,
      'FIXTURE_ROOT' => @tmp, 'FIXTURE_CURL_CALLS' => @calls, 'FIXTURE_SDK_COUNT' => @count, 'FIXTURE_SDK_SOURCE' => @source, 'FIXTURE_LOG' => @log).merge(extra)
  end

  def code(body, fixture_candidates: true)
    prefix = "source #{MODULE.shellescape}\n"
    prefix += "jfs_route_sdk_is_official() { [[ \"${FIXTURE_PUBLIC_SDK:-1}\" == 1 ]]; }\n" if fixture_candidates
    prefix += "jfs_route_candidates() { JFS_PROXY_MODES=(direct); JFS_PROXY_URLS=(''); JFS_CURL_CONFIG=0; }\n" if fixture_candidates
    prefix + body
  end

  def call_body(once: false)
    "#{once ? 'jobs_flutter_sdk_once' : 'jobs_flutter_sdk_retry'} SDK #{@log.shellescape} #{@sdk.shellescape} 3.38.4 #{File.join(@sdk, 'bin/flutter').shellescape} --version\n"
  end

  def run_code(body, extra = {}, fixture_candidates: true)
    Open3.popen3(env(extra), '/bin/zsh', '-f', '-c', code(body, fixture_candidates: fixture_candidates)) do |input, output, errors, process|
      input.close
      out_reader = Thread.new { output.read }
      err_reader = Thread.new { errors.read }
      begin
        status = Timeout.timeout(8) { process.value }
        [out_reader.value, err_reader.value, status]
      rescue Timeout::Error
        Process.kill('TERM', process.pid) rescue nil
        Timeout.timeout(3) { process.value } rescue nil
        trace = File.exist?(@log) ? File.read(@log)[-2400..-1].to_s : ''
        diagnostics = Dir.glob(File.join(@tmp, '**/*')).select { |p| p.end_with?('.invalid') || p.end_with?('.error') }.first(4).map { |p| File.read(p)[0, 300] }.join("\n")
        raise "Fixture timeout: #{trace} #{diagnostics} #{err_reader.value}"
      ensure
        Process.kill('TERM', process.pid) if process.alive?
      end
    end
  end

  def test_cancelling_retrying_downloader_freezes_parent_before_killing_children
    pids = File.join(@tmp, 'download.pids')
    child = File.join(@tmp, 'fake-curl')
    downloader = File.join(@tmp, 'retrying-downloader')
    File.write(child, "#!/bin/zsh\nprint $$ >> #{pids.shellescape}\ntrap '' TERM\nwhile true; do /bin/sleep 0.1; done\n")
    File.write(downloader, "#!/bin/zsh\nprint $$ >> #{pids.shellescape}\ntrap '' TERM\nwhile true; do #{child.shellescape}; done\n")
    [child, downloader].each { |p| File.chmod(0o700, p) }
    script = code("jobs_flutter_route_prepare() { return 0; }; jobs_flutter_sdk_retry SDK #{@log.shellescape} #{@sdk.shellescape} 3.38.4 #{downloader.shellescape}")
    Open3.popen3(env, '/bin/zsh', '-f', '-c', script) do |input, output, errors, process|
      input.close
      readers = [Thread.new { output.read }, Thread.new { errors.read }]
      begin
        Timeout.timeout(4) { sleep 0.02 until File.exist?(pids) && File.readlines(pids).length >= 2 }
        Process.kill('TERM', process.pid)
        status = Timeout.timeout(4) { process.value }
        assert_equal 143, status.exitstatus, readers[1].value
        recorded = File.readlines(pids).map(&:to_i)
        Timeout.timeout(3) do
          loop do
            live = recorded.select do |pid|
              state, = Open3.capture2('/bin/ps', '-p', pid.to_s, '-o', 'stat=')
              !state.strip.empty? && !state.strip.start_with?('Z')
            end
            break if live.empty?
            sleep 0.02
          end
        end
        sleep 0.05
        assert_equal recorded, File.readlines(pids).map(&:to_i), 'Downloader spawned a new curl after cancellation'
      ensure
        Process.kill('KILL', process.pid) if process.alive?
        File.readlines(pids).map(&:to_i).each { |pid| Process.kill('KILL', pid) rescue nil } if File.exist?(pids)
        readers.each(&:join)
      end
    end
  end

  def fvm_runtime_fixture
    manager = File.join(@tmp, 'text-fvm')
    File.write(manager, "#!/bin/zsh\nexec dart \"$@\"\n")
    File.chmod(0o700, manager)
    File.write(File.join(@sdk, 'bin/internal/shared.sh'), '# fixture shared runtime')
    File.write(File.join(@sdk, 'bin/internal/update_dart_sdk.sh'), '# fixture bootstrap')
    File.write(File.join(@sdk, 'bin/dart'), "#!/bin/zsh\n# shared.sh dispatches this real Flutter shim\nexit 99\n")
    File.chmod(0o700, File.join(@sdk, 'bin/dart'))
    manager
  end

  def test_fvm_aot_or_independent_dart_does_not_bootstrap_an_arbitrary_flutter
    manager = fvm_runtime_fixture
    body = "jobs_flutter_fvm_runtime Runtime #{@log.shellescape} /usr/bin/true"
    out, err, status = run_code(body, 'PATH' => File.join(@sdk, 'bin') + ':' + ENV.fetch('PATH'))
    assert status.success?, err
    assert_empty out
    refute File.exist?(@calls)
    independent = File.join(@tmp, 'independent/bin')
    FileUtils.mkdir_p(independent)
    File.write(File.join(independent, 'dart'), "#!/bin/zsh\nexit 99\n")
    File.chmod(0o700, File.join(independent, 'dart'))
    out, err, status = run_code("jobs_flutter_fvm_runtime Runtime #{@log.shellescape} #{manager.shellescape}", 'PATH' => independent + ':' + ENV.fetch('PATH'))
    assert status.success?, err
    assert_empty out
    refute File.exist?(@count)
  end

  def test_text_fvm_cold_flutter_dart_runtime_routes_before_metadata_and_keeps_stdout_empty
    manager = fvm_runtime_fixture
    body = <<~SH
      jobs_flutter_route_prepare() { print -r -- "$1|$4" >> #{@calls.shellescape}; return 0; }
      jobs_flutter_fvm_runtime Runtime #{@log.shellescape} #{manager.shellescape} || exit $?
      print metadata >> #{File.join(@tmp, 'order').shellescape}
    SH
    out, err, status = run_code(body, 'PATH' => File.join(@sdk, 'bin') + ':' + ENV.fetch('PATH'))
    assert status.success?, err
    assert_empty out
    assert_equal "#{File.realpath(@sdk)}|dart", File.read(@calls).strip
    assert_equal '1', File.read(@count).strip
    assert_includes err, '{"sdk":"ready"}'
    assert_equal "metadata\n", File.read(File.join(@tmp, 'order'))
  end

  def test_text_fvm_with_healthy_native_dart_does_not_probe_or_execute_sdk
    manager = fvm_runtime_fixture
    FileUtils.mkdir_p(File.join(@sdk, 'bin/cache/dart-sdk/bin'))
    File.write(File.join(@sdk, 'bin/cache/dart-sdk/bin/dart'), '# fixture native Dart')
    File.chmod(0o700, File.join(@sdk, 'bin/cache/dart-sdk/bin/dart'))
    File.write(File.join(@sdk, 'bin/cache/engine-dart-sdk.stamp'), ENGINE)
    out, err, status = run_code("jobs_flutter_fvm_runtime Runtime #{@log.shellescape} #{manager.shellescape}", 'PATH' => File.join(@sdk, 'bin') + ':' + ENV.fetch('PATH'))
    assert status.success?, err
    assert_empty out
    refute File.exist?(@calls)
    refute File.exist?(@count)
  end

  def test_cancelled_fvm_runtime_never_queries_manager_metadata
    manager = fvm_runtime_fixture
    meta = File.join(@tmp, 'metadata-was-queried')
    body = <<~SH
      jobs_flutter_route_prepare() { return 130; }
      jfs_fvm_context_fields() { /usr/bin/touch #{meta.shellescape}; }
      jobs_flutter_fvm_install SDK #{@log.shellescape} #{manager.shellescape} stable
    SH
    _out, err, status = run_code(body, 'PATH' => File.join(@sdk, 'bin') + ':' + ENV.fetch('PATH'))
    assert_equal 130, status.exitstatus, err
    refute File.exist?(meta)
    refute File.exist?(@count)
  end

  def test_source_call_under_nounset_preserves_parent_options
    out, err, status = run_code("set -eu\n" + call_body + 'print -r -- "NOUNSET=$options[nounset]"')
    assert status.success?, err
    assert_includes out, 'NOUNSET=on'
  end

  def test_legacy_private_fvm_starts_with_original_git_instead_of_nonexistent_public_archive
    manager = File.join(@tmp, 'fvm')
    File.write(manager, "#!/bin/zsh\nprint -- 'legacy install options'\n")
    File.chmod(0o700, manager)
    body = <<~SH
      jfs_fvm_timed() { "$@"; }
      jfs_fvm_context_fields() { print -r -- $'https://private.example.invalid/flutter.git\t#{@tmp}/versions'; }
      jobs_flutter_sdk_retry() { print -r -- "${JOBS_FLUTTER_ROUTE_MODE}|${JOBS_FLUTTER_ROUTE_LEGACY_FVM_AUTO}|${JOBS_FLUTTER_ROUTE_SOURCE_URL}"; return 130; }
      jobs_flutter_fvm_install SDK #{@log.shellescape} #{manager.shellescape} master
    SH
    out, err, status = run_code(body)
    assert_equal 130, status.exitstatus, err
    assert_includes out, 'git|1|https://private.example.invalid/flutter.git'
    refute File.exist?(@calls)
  end

  def test_legacy_fvm_retry_switches_from_git_to_landed_engine_probe
    FileUtils.rm_f(File.join(@sdk, 'bin/internal/engine.version'))
    body = <<~SH
      jobs_flutter_route_prepare() { print -r -- "$4" >> #{@calls.shellescape}; }
      legacy_once() {
        if [[ ! -f #{@count.shellescape} ]]; then
          print 1 > #{@count.shellescape}
          print '#{ENGINE}' > #{File.join(@sdk, 'bin/internal/engine.version').shellescape}
          return 9
        fi
        return 0
      }
      JOBS_FLUTTER_ROUTE_LEGACY_FVM_AUTO=1 JOBS_FLUTTER_ROUTE_MODE=git jobs_flutter_sdk_retry SDK #{@log.shellescape} #{@sdk.shellescape} master legacy_once
    SH
    _out, err, status = run_code(body)
    assert status.success?, err
    assert_equal %w[git platform], File.readlines(@calls).map(&:strip)
  end

  def test_unrelated_flutter_realm_environment_is_not_a_native_artifact_namespace
    _out, err, status = run_code(call_body, 'FLUTTER_REALM' => 'ignored-native-env')
    assert status.success?, err
    refute_includes File.read(@calls), 'ignored-native-env'
    assert_includes File.read(@calls), "flutter_infra_release/flutter/#{ENGINE}/dart-sdk-darwin-#{@arch}.zip"
  end

  def test_unknown_private_engine_is_not_sent_to_unrequested_public_mirror
    _out, err, status = run_code("JOBS_FLUTTER_ROUTE_PREPARE_ONCE=1 jobs_flutter_route_prepare #{@sdk.shellescape} 3.38.4 #{@log.shellescape}",
      { 'FIXTURE_PUBLIC_SDK' => '0', 'FIXTURE_GOOGLE_OFFLINE' => '1', 'FLUTTER_PREBUILT_ENGINE_VERSION' => 'b' * 40 })
    assert_equal 75, status.exitstatus, err
    refute_includes File.read(@calls), 'storage.flutter-io.cn'
    refute File.exist?(@count)
  end

  def test_broken_local_shell_fails_once
    body = "broken_sdk() { print 'bad substitution' >> #{@log.shellescape}; print x >> #{@count.shellescape}; return 2; }; jobs_flutter_sdk_retry SDK #{@log.shellescape} #{@sdk.shellescape} 3.38.4 broken_sdk"
    _out, err, status = run_code(body)
    assert_equal 2, status.exitstatus, err
    assert_equal 1, File.readlines(@count).length
  end

  def test_prepare_once_returns_to_outer_network_fallback
    _out, err, status = run_code("JOBS_FLUTTER_ROUTE_PREPARE_ONCE=1 jobs_flutter_route_prepare #{@sdk.shellescape} 3.38.4 #{@log.shellescape}", 'FIXTURE_OFFLINE' => '1')
    assert_equal 75, status.exitstatus, err
    assert_includes File.read(@log), '网络不可达'
    refute File.exist?(@count)
  end

  def test_curl_config_is_explicit_and_part_of_cache_identity
    config = File.join(@tmp, 'brew.curlrc')
    File.write(config, "ipv4\n")
    body = "JFS_MODE=dart; JFS_SOURCE_URL=''; jfs_route_candidates; print -r -- MODE=$JFS_PROXY_MODES[1]; JFS_SDK_ROOT=''; JFS_REQUESTED_VERSION=''; JFS_ARCH=arm64; JFS_ENGINE=x; JFS_REALM=''; JFS_SDK_DEFAULT_BASE=''; print -r -- KEY=$(jfs_route_key)"
    out, err, status = run_code(body, { 'JOBS_FLUTTER_ROUTE_CURL_CONFIG' => config }, fixture_candidates: false)
    assert status.success?, err
    assert_includes out, 'MODE=env'
    File.write(config, "ipv6\n")
    changed, = run_code(body, { 'JOBS_FLUTTER_ROUTE_CURL_CONFIG' => config }, fixture_candidates: false)
    refute_equal out[/KEY=(.*)/, 1], changed[/KEY=(.*)/, 1]
  end

  def test_fast_verified_mirror_is_selected_without_parent_environment_changes
    out, err, status = run_code(call_body + 'print -r -- "PARENT_SOURCE_SET=${+FLUTTER_STORAGE_BASE_URL}"')
    assert status.success?, err
    assert_includes File.read(@source), '1:https://storage.flutter-io.cn'
    assert_includes out, 'PARENT_SOURCE_SET=0'
    assert_includes out, '{"sdk":"ready"}'
    assert_includes File.read(@log), '实测指标最高'
  end

  def test_explicit_empty_source_and_proxy_are_preserved
    out, err, status = run_code(call_body, { 'FLUTTER_STORAGE_BASE_URL' => '', 'HTTPS_PROXY' => '' }, fixture_candidates: false)
    assert status.success?, "exit=#{status.exitstatus} #{err} #{out} #{File.exist?(@log) ? File.read(@log) : 'no log'}"
    assert_equal '1:|1:', File.read(@source).strip
    refute_includes File.read(@calls), 'https://storage.flutter-io.cn/'
  end

  def test_healthy_sdk_skips_all_network_probes
    FileUtils.mkdir_p(File.join(@sdk, 'bin/cache/dart-sdk/bin'))
    File.write(File.join(@sdk, 'bin/cache/engine-dart-sdk.stamp'), ENGINE)
    dart = File.join(@sdk, 'bin/cache/dart-sdk/bin/dart')
    File.write(dart, '#!/bin/zsh\nexit 99\n')
    File.chmod(0o700, dart)
    out, err, status = run_code(call_body)
    assert status.success?, "exit=#{status.exitstatus} #{err} #{out} #{File.exist?(@log) ? File.read(@log) : 'no log'}"
    refute File.exist?(@calls)
    assert_includes err, '复用健康环境'
  end

  def test_bad_mirror_body_is_rejected_and_official_is_selected
    out, err, status = run_code(call_body, 'FIXTURE_BAD_MIRROR' => '1')
    assert status.success?, "exit=#{status.exitstatus} #{err} #{out} #{File.exist?(@log) ? File.read(@log) : 'no log'}"
    assert_includes File.read(@source), '1:https://storage.googleapis.com'
  end

  def test_same_task_cache_avoids_new_metadata_and_range_requests
    out, err, status = run_code(call_body + call_body)
    assert status.success?, "exit=#{status.exitstatus} #{err} #{out} #{File.exist?(@log) ? File.read(@log) : 'no log'}"
    assert_equal 3, File.readlines(@calls).length
    assert_equal '2', File.read(@count).strip
    assert_includes err, '无需重复联网测速'
  end

  def test_failed_sdk_acquisition_invalidates_route_and_reprobes
    out, err, status = run_code(call_body, 'FIXTURE_FAIL_ONCE' => '1')
    assert status.success?, "exit=#{status.exitstatus} #{err} #{out} #{File.exist?(@log) ? File.read(@log) : 'no log'}"
    assert_equal '2', File.read(@count).strip
    assert_equal 6, File.readlines(@calls).length
    assert_includes err, '路线缓存失效'
  end

  def test_fast_probe_with_persistent_real_download_failure_rotates_to_another_verified_route
    out, err, status = run_code(call_body, 'FIXTURE_MIRROR_DOWNLOAD_FAILS' => '1')
    assert status.success?, "exit=#{status.exitstatus} #{err} #{out} #{File.exist?(@log) ? File.read(@log) : 'no log'}"
    assert_equal '2', File.read(@count).strip
    assert_includes File.read(@source), 'https://storage.googleapis.com'
    assert_includes err, 'AUTO冷却60秒'
  end

  def test_original_installer_url_is_probed_without_injecting_an_sdk_mirror
    out, err, status = run_code(call_body, 'JOBS_FLUTTER_ROUTE_MODE' => 'source', 'JOBS_FLUTTER_ROUTE_SOURCE_URL' => 'https://fvm.example.invalid/install.sh', 'JOBS_FLUTTER_ROUTE_EXPECTED_TEXT' => 'fvm')
    assert status.success?, "exit=#{status.exitstatus} #{err} #{out} #{File.exist?(@log) ? File.read(@log) : 'no log'}"
    assert_equal ['https://fvm.example.invalid/install.sh'], File.readlines(@calls).map(&:strip)
    assert_includes File.read(@source), '0:|'
  end

  def test_git_probes_only_the_original_repository_and_expected_ref
    git = File.join(@tmp, 'git')
    File.write(git, <<~'SH')
      #!/bin/zsh
      print -r -- "$*" >> "$FIXTURE_ROOT/git.calls"
      printf '%040d\t%s\n' 1 "${@[-1]}"
    SH
    File.chmod(0o700, git)
    out, err, status = run_code(call_body, 'JOBS_FLUTTER_ROUTE_MODE' => 'git', 'JOBS_FLUTTER_ROUTE_SOURCE_URL' => 'https://git.example.invalid/user/fork.git', 'JOBS_FLUTTER_ROUTE_GIT' => git)
    assert status.success?, "exit=#{status.exitstatus} #{err} #{out} #{File.exist?(@log) ? File.read(@log) : 'no log'}"
    refute File.exist?(@calls)
    assert_includes File.read(File.join(@tmp, 'git.calls')), 'https://git.example.invalid/user/fork.git refs/tags/3.38.4'
    assert_includes File.read(@source), '0:|'
  end

  def test_offline_preflight_cancels_without_starting_the_sdk
    Open3.popen3(env('FIXTURE_OFFLINE' => '1'), '/bin/zsh', '-f', '-c', code(call_body)) do |input, output, errors, process|
      input.close
      captured = ''.b
      begin
        Timeout.timeout(5) { captured << errors.readpartial(4096) until captured.include?('没有可验证可用路线'.b) }
        Process.kill('TERM', process.pid)
        status = Timeout.timeout(3) { process.value }
        assert_equal 143, status.exitstatus
        refute File.exist?(@count)
        assert_empty output.read
      ensure
        Process.kill('TERM', process.pid) if process.alive?
      end
    end
  end

  def test_google_offline_still_allows_a_verified_trusted_mirror_sample
    out, err, status = run_code(call_body, 'FIXTURE_GOOGLE_OFFLINE' => '1')
    assert status.success?, "exit=#{status.exitstatus} #{err} #{out} #{File.exist?(@log) ? File.read(@log) : 'no log'}"
    assert_includes File.read(@source), 'https://storage.flutter-io.cn'
    assert_includes err, '官方摘要不可达'
  end

  def test_explicit_private_engine_never_depends_on_a_google_bucket
    File.write(File.join(@sdk, 'bin/internal/engine.version'), 'c' * 40)
    out, err, status = run_code(call_body, 'FLUTTER_STORAGE_BASE_URL' => 'https://private.example.invalid/sdk')
    assert status.success?, "exit=#{status.exitstatus} #{err} #{out} #{File.exist?(@log) ? File.read(@log) : 'no log'}"
    calls = File.read(@calls)
    refute_includes calls, 'googleapis.com'
    assert_includes calls, '/flutter/' + ('c' * 40) + '/dart-sdk-darwin-'
    assert_includes err, '不声明与官方等价'
  end

  def test_native_realm_is_part_of_the_exact_object_path
    File.write(File.join(@sdk, 'bin/cache/engine.realm'), 'native/realm')
    out, err, status = run_code(call_body, 'FLUTTER_REALM' => 'not-the-native-realm', 'FLUTTER_STORAGE_BASE_URL' => 'https://storage.flutter-io.cn', 'FIXTURE_GOOGLE_OFFLINE' => '1')
    assert status.success?, "exit=#{status.exitstatus} #{err} #{out} #{File.exist?(@log) ? File.read(@log) : 'no log'}"
    assert_includes File.read(@calls), 'storage.flutter-io.cn/native/realm/flutter_infra_release/'
    refute_includes File.read(@calls), '/not-the-native-realm/flutter_infra_release/'
  end

  def test_requested_stable_archive_uses_new_current_release_despite_old_warm_sdk
    File.write(File.join(@sdk, 'bin/cache/flutter.version.json'), JSON.generate({ frameworkVersion: '3.38.4', engineRevision: ENGINE }))
    out, err, status = run_code(call_body.sub(' 3.38.4 ', ' stable '), 'JOBS_FLUTTER_ROUTE_MODE' => 'archive')
    assert status.success?, "exit=#{status.exitstatus} #{err} #{out} #{File.exist?(@log) ? File.read(@log) : 'no log'}"
    assert_includes File.read(File.join(@tmp, 'sdk.target')), '3.50.1|flutter_infra_release/releases/stable/macos/'
    assert_includes File.read(@calls), '3.50.1-stable.zip'
  end

  def test_old_framework_metadata_with_another_engine_is_not_identity
    File.write(File.join(@sdk, 'bin/cache/flutter.version.json'), JSON.generate({ frameworkVersion: '1.2.3', engineRevision: 'b' * 40 }))
    out, err, status = run_code("jfs_route_data identity #{@sdk.shellescape} '' #{@arch} ''")
    assert status.success?, err
    refute_includes out, '1.2.3'
    assert_equal ENGINE, out.strip
  end

  def init_sdk_git(origin)
    [ ['/usr/bin/git', 'init', '--quiet', @sdk],
      ['/usr/bin/git', '-C', @sdk, 'symbolic-ref', 'HEAD', 'refs/heads/stable'],
      ['/usr/bin/git', '-C', @sdk, 'config', 'remote.origin.url', origin],
      ['/usr/bin/git', '-C', @sdk, 'config', 'branch.stable.remote', 'origin'],
      ['/usr/bin/git', '-C', @sdk, 'config', 'branch.stable.merge', 'refs/heads/stable'] ].each do |argv|
      _, errors, status = Open3.capture3(*argv)
      raise "Local fixture Git failed: #{errors}" unless status.success?
    end
  end

  def test_private_fork_stable_upgrade_does_not_choose_a_public_archive
    init_sdk_git('https://private.example.invalid/flutter.git')
    body = <<~SH
      jobs_flutter_sdk_retry() { print -r -- "$JOBS_FLUTTER_ROUTE_MODE|$4"; return 130; }
      jobs_flutter_upgrade SDK #{@log.shellescape} #{@sdk.shellescape} '' #{File.join(@sdk, 'bin/flutter').shellescape} upgrade
    SH
    out, err, status = run_code(body)
    assert_equal 130, status.exitstatus, err
    assert_includes out, 'platform|stable'
    refute File.exist?(@calls)
    assert_includes err, '不取公共channel归档'
  end

  def test_missing_engine_private_sdk_uses_only_original_git_route
    init_sdk_git('https://private.example.invalid/flutter.git')
    FileUtils.rm_f(File.join(@sdk, 'bin/internal/engine.version'))
    git = File.join(@tmp, 'git-probe')
    File.write(git, "#!/bin/zsh\nprint -r -- \"$*\" >> \"$FIXTURE_ROOT/git.calls\"\nprintf '%040d\\t%s\\n' 1 \"${@[-1]}\"\n")
    File.chmod(0o700, git)
    out, err, status = run_code(call_body.sub(' 3.38.4 ', " '' "), 'JOBS_FLUTTER_ROUTE_GIT' => git)
    assert status.success?, err + out
    assert_equal '1', File.read(@count).strip
    refute File.exist?(@calls)
    assert_includes File.read(File.join(@tmp, 'git.calls')), 'https://private.example.invalid/flutter.git HEAD'
    assert_includes File.read(@source), '0:|'
    assert_includes err, '制品身份尚未解析'
  end

  def test_missing_private_engine_without_git_keeps_original_command_and_explicit_source
    FileUtils.rm_f(File.join(@sdk, 'bin/internal/engine.version'))
    out, err, status = run_code(call_body + call_body, 'FLUTTER_STORAGE_BASE_URL' => 'https://private.example.invalid/sdk')
    assert status.success?, err + out
    refute File.exist?(@calls)
    assert_equal '2', File.read(@count).strip
    assert_includes File.read(@source), '1:https://private.example.invalid/sdk'
    assert_includes err, '不猜公共stable'
    refute_includes err, '复用健康环境'
  end

  def test_unknown_engine_and_empty_version_never_guess_public_stable
    FileUtils.rm_f(File.join(@sdk, 'bin/internal/engine.version'))
    File.write(File.join(@sdk, 'bin/cache/flutter.version.json'), JSON.generate({ frameworkVersion: 'old-private-version', engineRevision: 'b' * 40 }))
    out, err, status = run_code(call_body.sub(' 3.38.4 ', " '' "))
    assert status.success?, err + out
    refute File.exist?(@calls)
    assert_equal '1', File.read(@count).strip
    assert_includes err, '身份及原Git来源尚未解析'
    refute_includes err, '复用健康环境'
  end

  def test_explicit_private_archive_mode_probes_native_engine_not_public_manifest
    out, err, status = run_code(call_body, 'JOBS_FLUTTER_ROUTE_MODE' => 'archive', 'FLUTTER_STORAGE_BASE_URL' => 'https://private.example.invalid/sdk')
    assert status.success?, err + out
    calls = File.read(@calls)
    assert_includes calls, "private.example.invalid/sdk/flutter_infra_release/flutter/#{ENGINE}/dart-sdk-darwin-"
    refute_includes calls, 'googleapis.com'
    refute_includes calls, 'releases_macos.json'
    refute_includes calls, 'storage.flutter-io.cn'
  end

  def test_business_command_is_executed_only_once
    out, err, status = run_code(call_body(once: true), 'FIXTURE_SDK_EXIT' => '7')
    assert_equal 7, status.exitstatus, err + out
    assert_equal '1', File.read(@count).strip
  end
end
