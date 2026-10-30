# frozen_string_literal: true
#
# InstallerTests.rb
# JobsFileCreator
#
# Created by Jobs on 2026年10月29日，星期四.
#
# 复制后台管理器到临时目录，硬替换全部系统写命令，不运行真实扩展管理。

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
    source = File.read(File.expand_path('../Scripts/ManageExtension.zsh', __dir__))
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
