# Created by Jobs on 2026年10月28日，星期三。
# 在临时目录验证拖入路径、快照识别、确认门禁及失败码，不操作真实项目。
require 'minitest/autorun'
require 'open3'
require 'tmpdir'
require 'shellwords'

class DependencyImportShellTests < Minitest::Test
  TOOLS = File.expand_path(ENV.fetch('JOBS_TEST_TOOLS_DIR', '../Scripts/Tools'), __dir__)
  SCRIPT = File.join(TOOLS, 'ImportFlutterDependencies.zsh')

  def run_functions(code, *arguments, input: '')
    Dir.mktmpdir('jobs-dependency-import-shell-') do |directory|
      fixture = File.join(directory, 'fixture.zsh')
      source = File.read(SCRIPT).sub(/^main "\$@"\s*\z/, '')
      File.write(fixture, source + "\nLOG_FILE=/dev/null\n" + code)
      Open3.capture2e({ 'NO_COLOR' => '1' }, '/bin/zsh', '-f', fixture, *arguments, stdin_data: input)
    end
  end

  def test_paths_are_single_data_values
    [
      ['/tmp/中文 文件夹', '/tmp/中文 文件夹'],
      ['/tmp/中文\\ 文件夹 ', '/tmp/中文 文件夹'],
      ["'/tmp/中文 文件夹' ", '/tmp/中文 文件夹'],
      ['"/tmp/中文 文件夹"', '/tmp/中文 文件夹'],
      ['~/Desktop/依赖', File.join(Dir.home, 'Desktop/依赖')],
      ['/tmp/$(touch marker);`id`', '/tmp/$(touch marker);`id`']
    ].each do |raw, expected|
      output, result = run_functions('normalize_path_input "$1"; print -r -- "$REPLY"', raw)
      assert result.success?, output
      assert_equal expected, output.strip
    end
    output, result = run_functions('normalize_path_input "$1"', "'/tmp/one' '/tmp/two'")
    refute result.success?, output
    assert_includes output, '一次只接受一个目录'
  end

  def test_existing_paths_accept_pasted_boundary_whitespace_and_preserve_real_names
    Dir.mktmpdir('jobs-import-unicode-') do |directory|
      plain = File.join(directory, 'snapshot')
      spaced = File.join(directory, "依赖 目录")
      trailing = plain + ' '
      [plain, spaced, trailing].each { |path| Dir.mkdir(path) }
      [
        [plain + ' ', plain],
        [plain + "\u00a0", plain],
        ["\u202f#{plain}\u202f", plain],
        ["'#{spaced}'\u00a0", spaced],
        ["\"#{spaced}\"\u202f", spaced],
        [spaced + "\u00a0", spaced],
        [spaced + ' ', spaced],
        [trailing, trailing],
        [Shellwords.escape(trailing) + "\u00a0", trailing],
        [Shellwords.escape(trailing) + "\u00a0 ", trailing]
      ].each do |raw, expected|
        # plain+空格也是实际存在的目录，必须优先保留它的真实文件名。
        expected = trailing if raw == plain + ' '
        output, result = run_functions('normalize_path_input "$1"; print -r -- "$REPLY"', raw)
        assert result.success?, output
        assert_equal expected, output.delete_suffix("\n")
      end
    end
  end

  def test_intro_cancels_before_business
    ['', "no\n", " \n"].each do |input|
      output, result = run_functions('show_script_intro_and_wait; print unexpected-business', input: input)
      assert result.success?, output
      assert_includes output, '导入 Flutter 第三方依赖'
      refute_includes output, 'unexpected-business'
      refute_includes output, "\e["
    end
  end

  def test_bad_snapshot_reprompts_and_quoted_drag_is_accepted
    Dir.mktmpdir('中文 项目 ') do |project|
      File.write(File.join(project, 'pubspec.yaml'), "name: fixture\n")
      snapshot = File.join(project, '依赖 快照')
      Dir.mkdir(snapshot)
      Dir.mkdir(File.join(snapshot, 'packages'))
      File.write(File.join(snapshot, 'manifest.json'), '{}')
      output, result = run_functions(<<~'ZSH', project, input: "/tmp/not-an-export\n'#{snapshot}' \n")
        read_project_and_source "$1"
        print -r -- "PROJECT=$PROJECT_PATH"
        print -r -- "SOURCE=$SOURCE_PATH"
      ZSH
      assert result.success?, output
      assert_includes output, '不是依赖导出目录'
      assert_includes output, "PROJECT=#{File.realpath(project)}"
      assert_includes output, "SOURCE=#{File.realpath(snapshot)}"
    end
  end

  def test_empty_dependency_input_reprompts_until_a_directory_is_supplied
    Dir.mktmpdir('jobs-import-empty-') do |project|
      File.write(File.join(project, 'pubspec.yaml'), "name: fixture\n")
      snapshot = File.join(project, '依赖 快照')
      Dir.mkdir(snapshot)
      Dir.mkdir(File.join(snapshot, 'packages'))
      File.write(File.join(snapshot, 'manifest.json'), '{}')
      output, result = run_functions(<<~'ZSH', project, input: "\n\u00a0\n\u202f\n'#{snapshot}'\n")
        read_project_and_source "$1"
        print -r -- "SOURCE=$SOURCE_PATH"
      ZSH
      assert result.success?, output
      assert_equal 3, output.scan('尚未输入依赖目录').length, output
      assert_includes output, "SOURCE=#{File.realpath(snapshot)}"
    end
  end

  def test_empty_dependency_input_followed_by_eof_exits_without_business
    Dir.mktmpdir('jobs-import-eof-') do |project|
      File.write(File.join(project, 'pubspec.yaml'), "name: fixture\n")
      output, result = run_functions('read_project_and_source "$1"; print unexpected-business', project, input: "\n\n")
      assert result.success?, output
      assert_equal 2, output.scan('尚未输入依赖目录').length, output
      refute_includes output, 'unexpected-business'
    end
  end

  def test_symlink_snapshot_and_eof_do_not_continue
    Dir.mktmpdir('jobs-import-link-') do |directory|
      project = File.join(directory, 'project')
      snapshot = File.join(directory, 'snapshot')
      Dir.mkdir(project)
      Dir.mkdir(snapshot)
      Dir.mkdir(File.join(snapshot, 'packages'))
      File.write(File.join(snapshot, 'manifest.json'), '{}')
      File.write(File.join(project, 'pubspec.yaml'), "name: fixture\n")
      link = File.join(directory, 'link')
      File.symlink(snapshot, link)
      output, result = run_functions('read_project_and_source "$1"; print unexpected-business', project, input: "#{link}\n\n")
      assert result.success?, output
      assert_includes output, '不是依赖导出目录'
      refute_includes output, 'unexpected-business'
    end
  end

  def test_validation_failure_preserves_exit_and_never_confirms
    Dir.mktmpdir('jobs-import-engine-') do |engine_directory|
      File.write(File.join(engine_directory, 'ImportFlutterDependencies.dart'), 'print invalid-snapshot; exit 23')
      output, result = run_functions(<<~'ZSH', engine_directory)
        setopt PIPE_FAIL
        DART_EXECUTABLE=/bin/zsh
        SCRIPT_DIR="$1"
        validate_import
        print unexpected-confirmation
      ZSH
      assert_equal 23, result.exitstatus, output
      assert_includes output, 'invalid-snapshot'
      refute_includes output, 'unexpected-confirmation'
    end
  end

  def test_only_exact_yes_writes_and_failed_import_is_not_success
    ['', "\n", "yes\n", "NO\n"].each do |input|
      output, result = run_functions('DART_EXECUTABLE=/usr/bin/false; confirm_and_import', input: input)
      assert result.success?, output
      refute_includes output, '导入完成'
    end
    output, result = run_functions(<<~'ZSH', input: "YES\n")
      setopt PIPE_FAIL
      DART_EXECUTABLE=/usr/bin/false
      confirm_and_import
    ZSH
    refute result.success?, output
    assert_includes output, '导入未完成'
    refute_includes output, '✔ 导入完成'
  end
end
