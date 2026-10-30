# frozen_string_literal: true
# 使用真实 zsh / Darwin 无覆盖发布与临时文件，不调用 Finder 或 Terminal.app。
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
