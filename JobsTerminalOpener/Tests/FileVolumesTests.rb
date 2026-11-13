# frozen_string_literal: true
# 使用真实 zsh / Darwin 无覆盖发布与临时文件，不调用 Finder 或 Terminal.app。
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
require 'minitest/autorun'
require 'open3'
require 'pty'
require 'timeout'
require 'tmpdir'

class FileVolumesTests < Minitest::Test
  PROJECT = File.expand_path('..', __dir__)
  SCRIPT = File.join(PROJECT, 'Scripts/FileVolumes.zsh')

  def setup
    @root = File.realpath(Dir.mktmpdir('jobs-volumes-'))
    @source = File.join(@root, "中文 @ 文件 ' $(touch INJECTED).bin")
    File.binwrite(@source, (0..255).to_a.pack('C*') * 19)
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def run_action(*args)
    output = +''
    status = nil
    PTY.spawn({ 'TMPDIR' => "#{@root}/", 'NO_COLOR' => '1' }, '/bin/zsh', SCRIPT, *args) do |reader, writer, pid|
      writer.write("\n")
      begin
        Timeout.timeout(20) { loop { output << reader.readpartial(4096) } }
      rescue Errno::EIO, EOFError
        # PTY 正常结束。
      end
      _, status = Process.wait2(pid)
    end
    [output, status]
  end

  def chunks
    Dir.glob("#{@source}.chunks/*").sort
  end

  def test_roundtrip_preserves_sources_and_sorts_by_numeric_volume
    original = File.binread(@source)
    output, status = run_action('split', @source, '--limit-bytes', '500')
    assert status.success?, output
    assert_equal original, File.binread(@source)
    assert_operator chunks.count, :>=, 2
    assert chunks.all? { |path| File.size(path) <= 500 }
    output, status = run_action('merge', *chunks.reverse)
    assert status.success?, output
    assert_equal original, File.binread(File.join("#{@source}.chunks", File.basename(@source)))
    assert_equal chunks.count, 11 # 10 分卷加合并文件；ceil(4864/10)=487。
    refute File.exist?(File.join(@root, 'INJECTED'))
  end

  def test_invalid_selection_rejects_missing_duplicate_mixed_and_empty
    [[['x@1of3', 'a'], ['x@3of3', 'b']],
     [['x@1of2', 'a'], ['x@01of2', 'b']],
     [['x@1of2', 'a'], ['y@2of2', 'b']],
     [['x@1of2', ''], ['x@2of2', 'b']]].each_with_index do |items, i|
      dir = File.join(@root, i.to_s)
      FileUtils.mkdir_p(dir)
      paths = items.map { |name, body| File.join(dir, name).tap { |path| File.write(path, body) } }
      output, status = run_action('merge', *paths)
      refute status.success?, output
      refute File.exist?(File.join(dir, 'x'))
      assert paths.all? { |path| File.file?(path) }
    end
  end

  def test_no_overwrite_or_nested_publication_when_destination_exists
    FileUtils.mkdir_p("#{@source}.chunks")
    File.write(File.join("#{@source}.chunks", 'keep'), 'owned')
    output, status = run_action('split', @source, '--limit-bytes', '500')
    refute status.success?, output
    assert_equal ['keep'], Dir.children("#{@source}.chunks")
  end

  def test_publish_exclusive_primitive_rejects_existing_directory_and_symlink
    definitions = File.read(SCRIPT).sub(/fv_main "\$@"\s*\z/, '')
    %w[directory symlink].each do |kind|
      stage = File.join(@root, "stage-#{kind}")
      target = File.join(@root, "target-#{kind}")
      FileUtils.mkdir_p(stage)
      File.write(File.join(stage, 'part'), 'new')
      kind == 'directory' ? FileUtils.mkdir_p(target) : File.symlink(stage, target)
      output, status = Open3.capture2e('/bin/zsh', '-c', definitions + "\nfv_publish \"$1\" \"$2\"", '--', stage, target)
      refute status.success?, output
      assert File.file?(File.join(stage, 'part'))
      assert_empty Dir.children(target) if kind == 'directory'
    end
  end

  def test_concurrent_publications_have_exactly_one_winner
    definitions = File.read(SCRIPT).sub(/fv_main "\$@"\s*\z/, '')
    script = File.join(@root, 'publish.zsh')
    File.write(script, definitions + "\nfv_publish \"$1\" \"$2\"\n")
    target = File.join(@root, 'shared-result')
    sources = 2.times.map do |i|
      File.join(@root, "race-#{i}").tap do |path|
        Dir.mkdir(path)
        File.write(File.join(path, 'part'), i.to_s)
      end
    end
    children = sources.map do |stage|
      Process.spawn('/bin/zsh', script, stage, target, out: File::NULL, err: File::NULL)
    end
    states = children.map { |pid| Process.wait2(pid)[1] }
    assert_equal 1, states.count(&:success?)
    assert_equal ['part'], Dir.children(target)
    assert_equal 1, sources.count { |path| File.directory?(path) }
  end

  def test_does_not_scan_unselected_neighbours_and_existing_merge_output_is_preserved
    a = File.join(@root, 'x@1of2'); b = File.join(@root, 'x@2of2')
    File.write(a, 'left'); File.write(b, 'right')
    File.write(File.join(@root, 'other@1of1'), 'untouched')
    output, status = run_action('merge', b, a)
    assert status.success?, output
    assert_equal 'leftright', File.read(File.join(@root, 'x'))
    output, status = run_action('merge', a, b)
    refute status.success?, output
    assert_equal 'leftright', File.read(File.join(@root, 'x'))
    assert_equal 'untouched', File.read(File.join(@root, 'other@1of1'))
  end

  def test_symlinks_and_noninteractive_invocation_are_rejected
    link = File.join(@root, 'link')
    File.symlink(@source, link)
    output, status = run_action('split', link, '--limit-bytes', '500')
    refute status.success?, output
    output, status = Open3.capture2e('/bin/zsh', SCRIPT, 'split', @source, '--limit-bytes', '500', stdin_data: "\n")
    refute status.success?, output
    refute File.exist?("#{@source}.chunks")
  end
end

class FileVolumeTransportTests < Minitest::Test
  PROJECT = File.expand_path('..', __dir__)
  def self.executable
    return @executable if @executable
    @build = Dir.mktmpdir('jobs-volume-transport-')
    @executable = File.join(@build, 'fixture')
    fixture = File.join(@build, 'main.swift')
    File.write(fixture, <<~'SWIFT')
      import Foundation
      let mode = CommandLine.arguments[1]
      let paths = Array(CommandLine.arguments.dropFirst(2))
      let urls = paths.map { URL(fileURLWithPath: $0) }
      var result: [String: Any] = ["merge": FileVolumeSelection.canMerge(urls), "split": FileVolumeSelection.canSplit(urls)]
      if mode == "prepare" {
          let request = try TerminalOpener().prepareFileVolumeRequest(urls: urls, action: .fileMerge)
          result["command"] = request.commandLine
          result["script"] = request.scriptURL!.path
          result["directory"] = request.runtimeDirectoryURL!.path
      }
      print(String(data: try JSONSerialization.data(withJSONObject: result), encoding: .utf8)!)
    SWIFT
    output, status = Open3.capture2e('/usr/bin/swiftc', '-module-cache-path', File.join(@build, 'ModuleCache'),
      File.join(PROJECT, 'JobsTerminalShared/DependencyProjectValidator.swift'),
      File.join(PROJECT, 'JobsTerminalFinderSync/TerminalOpener.swift'), fixture, '-o', @executable)
    raise output unless status.success?
    FileUtils.cp(File.join(PROJECT, 'Scripts/FileVolumes.zsh'), @build)
    Minitest.after_run { FileUtils.remove_entry(@build) }
    @executable
  end

  def setup
    require 'json'
    @root = File.realpath(Dir.mktmpdir('jobs-volume-selection-'))
    @a = File.join(@root, "中文' $()@01of02")
    @b = File.join(@root, "中文' $()@02of02")
    File.write(@a, 'one'); File.write(@b, 'two')
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def invoke(mode, *paths)
    output, status = Open3.capture2e({ 'TMPDIR' => "#{@root}/" }, self.class.executable, mode, *paths)
    assert status.success?, output
    JSON.parse(output)
  end

  def test_selection_policy_requires_single_file_or_exact_complete_group
    assert_equal({ 'merge' => true, 'split' => false }, invoke('predicate', @a, @b))
    assert_equal({ 'merge' => false, 'split' => true }, invoke('predicate', @a))
    assert_equal({ 'merge' => false, 'split' => false }, invoke('predicate', @a, @a))
    File.write(File.join(@root, 'x@1of2'), 'x')
    refute invoke('predicate', @a, File.join(@root, 'x@1of2'))['merge']
    File.truncate(@b, 0)
    refute invoke('predicate', @a, @b)['merge']
    assert_equal({ 'merge' => false, 'split' => false }, invoke('predicate', @root))
    link = File.join(@root, 'link')
    File.symlink(@a, link)
    refute invoke('predicate', link)['split']

  end

  def test_manager_adds_both_leaves_and_removes_one_without_losing_siblings
    source = File.read(File.join(PROJECT, 'Scripts/ManageExtension.zsh'))
    raise 'manager entry point missing' unless source.sub!(/\nmanager_main "\$@"\s*\z/, "\n")
    config = File.join(@root, 'Library/Application Support/JobsTerminalOpener/EnabledFinderMenuFeatures.txt')
    FileUtils.mkdir_p(File.dirname(config))
    File.write(config, 'open,file-content')
    driver = <<~'ZSH'
      manager_parse_options --action install --non-interactive --features file-merge,file-split || exit $?
      manager_validate_existing_configuration || exit $?
      manager_plan_shared_install || exit $?
      manager_save_shared_install || exit $?
      print -r -- "PLAN=$MANAGER_INSTALL_FEATURES"
      MANAGER_REQUESTED_FEATURES=file-merge
      manager_restart_finder() { return 0; }
      manager_plan_shared_removal || exit $?
      print -r -- "PARTIAL=$MANAGER_PARTIAL_REMOVAL"
    ZSH
    output, status = Open3.capture2e({ 'HOME' => @root }, '/bin/zsh', '-fc', source + "\n" + driver)
    assert status.success?, output
    assert_includes output, 'PLAN=open,file-content,file-merge,file-split'
    assert_includes output, 'PARTIAL=1'
    assert_equal 'open,file-content,file-split', File.read(config)
  end

  def test_complete_selection_enters_private_payload_instead_of_terminal_command
    request = invoke('prepare', @b, @a)
    refute_match(/[\r\n]/, request['command'])
    assert_operator request['command'].bytesize, :<, 512
    refute_includes request['command'], File.basename(@a)
    assert_equal 0o600, File.stat(request['script']).mode & 0o777
    assert_equal 0o700, File.stat(request['directory']).mode & 0o777
    payload = File.read(request['script'])
    assert_includes payload, "set -- $'merge'"
    assert_includes payload, File.basename(@a).gsub("'", "\\\\'")
    # 只清除本夹具创建的载体，绝不执行真实 Terminal 派发。
    File.unlink(request['script'])
    Dir.rmdir(request['directory'])
  end
end
