# frozen_string_literal: true
# Jobs：用真实分发脚本与临时假业务核对代码片段入口；不安装菜单或访问用户片段仓库。

require 'minitest/autorun'
require 'open3'
require 'tmpdir'
require 'fileutils'
require 'pty'
require 'json'
require 'digest'

class IOSToolsCodeSnippetsTests < Minitest::Test
  ROOT = File.expand_path('..', __dir__)
  TOOLS = File.join(ROOT, 'JobsIOSTools/Scripts/Tools')
  DISPATCHER = File.join(TOOLS, 'DispatchIOSTools.zsh')
  SCRIPT = '【MacOS】⚙️双击安装JobsCodeSnippets.command'

  def test_plan_accepts_direct_ios_project_and_rejects_plain_directory_or_unknown_action
    Dir.mktmpdir('jobs-snippets-menu-') do |directory|
      project = File.join(directory, "项目 space '$;\n名称")
      FileUtils.mkdir_p(project)
      File.write(File.join(project, 'Package.swift'), '// fixture')
      output, status = Open3.capture2e('/bin/zsh', '-f', DISPATCHER, '--plan', 'ios-code-snippets', project)
      assert status.success?, output
      assert_includes output, '✔ 只读计划通过，未运行业务。'
      assert_includes output, SCRIPT
      output, status = Open3.capture2e('/bin/zsh', '-f', DISPATCHER, '--plan', 'ios-code-snippets', directory)
      refute status.success?, output
      assert_includes output, '没有 iOS / CocoaPods 工程标记'
      output, status = Open3.capture2e('/bin/zsh', '-f', DISPATCHER, '--plan', 'unknown-action', project)
      refute status.success?, output
      assert_includes output, '未知动作'
      assert_equal ['Package.swift'], Dir.children(project)
    end
  end

  def test_real_dispatcher_preserves_finder_argument_environment_and_working_directory
    Dir.mktmpdir('jobs-snippets-dispatch-') do |directory|
      tools = File.join(directory, '工具 space')
      project = File.join(directory, "项目 space '$;\n名称")
      capture = File.join(directory, 'received.bin')
      FileUtils.mkdir_p([tools, project])
      File.write(File.join(project, 'Podfile'), '# fixture')
      FileUtils.cp(DISPATCHER, File.join(tools, 'DispatchIOSTools.zsh'))
      File.write(File.join(tools, SCRIPT), <<~'ZSH')
        #!/bin/zsh
        /usr/bin/printf '%s\0' "$@" "$JOBS_IOS_PROJECT_DIR" "$PWD" > "$JOBS_TEST_CAPTURE"
      ZSH
      transcript = +''
      PTY.spawn({'JOBS_TEST_CAPTURE' => capture}, '/bin/zsh', '-f', File.join(tools, 'DispatchIOSTools.zsh'), 'ios-code-snippets', project) do |read, _write, pid|
        begin
          read.each { |line| transcript << line }
        rescue Errno::EIO
          # macOS PTY 结束时可能返回 EIO。
        end
        _, status = Process.wait2(pid)
        assert status.success?, transcript
      end
      assert File.file?(capture), transcript
      physical_project = File.realpath(project)
      assert_equal ['--finder', physical_project, physical_project, physical_project], File.binread(capture).force_encoding(Encoding::UTF_8).split("\0")
      assert_equal ['Podfile'], Dir.children(project)
    end
  end

  def test_bundled_script_matches_manifest_and_independent_source
    manifest = JSON.parse(File.read(File.join(TOOLS, 'SourceManifest.json')))
    rows = manifest.select { |row| row['feature'] == 'ios-code-snippets' }
    assert_equal 1, rows.length
    row = rows.first
    assert_equal SCRIPT, row['file']
    bundled = File.binread(File.join(TOOLS, row.fetch('file')))
    source = File.expand_path(File.join('../../JobsCommand@iOS', row.fetch('source')), ROOT)
    assert File.file?(source), source
    assert_equal File.binread(source), bundled
    assert_equal Digest::SHA256.hexdigest(bundled), row.fetch('bundledSHA256')
    assert_equal Digest::SHA256.file(source).hexdigest, row.fetch('sourceSHA256')
  end
end
