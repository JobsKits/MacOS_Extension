# Created by Jobs on 2026年10月19日，星期一。
# 仅隔离执行路径解析、自述和转发；不运行真实提取、安装或 Finder 注册。
require 'minitest/autorun'
require 'open3'
require 'tmpdir'

class ExtractionShellTests < Minitest::Test
  SCRIPT = File.expand_path('../Scripts/ExtractFlutterDependencies.zsh', __dir__)

  def run_functions(code, *arguments, input: '')
    Dir.mktmpdir('jobs-extraction-shell-') do |directory|
      source = File.read(SCRIPT).sub(/^main "\$@"\s*\z/, '')
      fixture = File.join(directory, 'fixture.zsh')
      File.write(fixture, source + "\n" + code)
      Open3.capture2e({ 'NO_COLOR' => '1' }, '/bin/zsh', '-f', fixture, *arguments, stdin_data: input)
    end
  end

  def test_plain_quoted_and_dragged_paths_are_data
    paths = [
      ['/tmp/中文 空格 新目录', '/tmp/中文 空格 新目录'],
      ['/tmp/中文\\ 空格\\ 新目录 ', '/tmp/中文 空格 新目录'],
      ["'/tmp/目录 with space'", '/tmp/目录 with space'],
      ['"/tmp/目录 with space"', '/tmp/目录 with space'],
      ['~/Desktop/new', File.join(Dir.home, 'Desktop/new')],
      ['/tmp/$(touch marker);`id`', '/tmp/$(touch marker);`id`']
    ]
    paths.each do |raw, expected|
      output, result = run_functions(<<~'ZSH', raw)
        normalize_path_input "$1"
        print -r -- "$REPLY"
      ZSH
      assert result.success?, output
      assert_equal expected, output.strip
    end
  end

  def test_multiple_dragged_paths_stop
    output, result = run_functions(<<~'ZSH', "'/tmp/one path' '/tmp/two path'")
      LOG_FILE=/dev/null
      normalize_path_input "$1"
    ZSH
    refute result.success?
    assert_includes output, '一次只接受一个目录'
  end

  def test_intro_eof_and_nonempty_cancel_before_any_write
    ['', "no\n", " \n"].each do |input|
      output, result = run_functions(<<~'ZSH', input: input)
        show_script_intro_and_wait
        print -r -- 'unexpected-business'
      ZSH
      assert result.success?, output
      assert_includes output, '提取 Flutter 第三方依赖'
      refute_includes output, 'unexpected-business'
      refute_includes output, "\e["
    end
  end

  def test_enter_continues
    output, result = run_functions(<<~'ZSH', input: "\n")
      show_script_intro_and_wait
      print -r -- 'business-ready'
    ZSH
    assert result.success?, output
    assert_includes output, 'business-ready'
  end

  def test_empty_destination_uses_desktop_and_preserves_project_argument
    Dir.mktmpdir('中文 Flutter ') do |project|
      File.write(File.join(project, 'pubspec.yaml'), "name: fixture\n")
      output, result = run_functions(<<~'ZSH', project, input: "\n")
        LOG_FILE=/dev/null
        read_project_and_destination "$1"
        print -r -- "PROJECT=$PROJECT_PATH"
        print -r -- "DESTINATION=$DESTINATION_PATH"
      ZSH
      assert result.success?, output
      assert_includes output, "PROJECT=#{File.realpath(project)}"
      desktop, = Open3.capture2('/usr/bin/osascript', '-e', 'POSIX path of (path to desktop folder)')
      assert_includes output, "DESTINATION=#{desktop.strip}"
    end
  end

  def test_engine_failure_survives_tee
    Dir.mktmpdir('jobs-dart-failure-') do |directory|
      fake = File.join(directory, 'fake-dart')
      File.write(fake, "#!/bin/zsh\nprint -r -- engine-failed\nexit 23\n")
      File.chmod(0755, fake)
      output, result = run_functions(<<~'ZSH', fake)
        setopt PIPE_FAIL
        LOG_FILE=/dev/null
        DART_EXECUTABLE="$1"
        run_extraction
      ZSH
      assert_equal 23, result.exitstatus, output
      assert_includes output, 'engine-failed'
      refute_includes output, '✔ 完成'
    end
  end
end
