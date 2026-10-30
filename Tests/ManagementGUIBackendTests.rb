# frozen_string_literal: true
# 管理 GUI 的隔离后端回归：所有扩展业务、桌面启动及编译均由替身承接。
require 'minitest/autorun'
require 'open3'
require 'tmpdir'
require 'fileutils'

class ManagementGUIBackendTests < Minitest::Test
  ROOT = File.expand_path('..', __dir__)
  MANAGER = File.join(ROOT, 'Scripts/ManageFinderExtensions.zsh')
  STANDALONE = %w[JobsFlutterTools JobsIOSTools JobsIPAResigner JobsPathCopier JobsRunAuthorizationRevoker JobsRunAuthorizer JobsTerminalOpener JobsProjectTools JobsDesktopTools JobsFileCreator].freeze

  def definitions(path)
    File.read(path).sub(/^(?:manager_)?main "\$@"\s*\z/, '')
  end

  def execute(source, *arguments, env: {})
    Open3.capture3(env, '/bin/zsh', '-c', source, 'fixture', *arguments)
  end

  def test_root_emits_success_and_failure_for_each_leaf_and_continues_after_failure
    %w[install uninstall].each do |operation|
      output, errors, result = execute(definitions(MANAGER) + <<~'ZSH', operation)
        LOG_FILE=/dev/null
        MANAGEMENT_ACTION="$1"
        parse_feature_selection git-pull,git-rollback,run-authorize,path_copier || exit $?
        ensure_feature_projects_exist() { return 0; }
        install_feature() { printf 'without-newline'; [[ "$1" != run-authorize ]]; }
        uninstall_feature() { printf 'without-newline'; [[ "$1" != run-authorize ]]; }
        if [[ "$MANAGEMENT_ACTION" == uninstall ]]; then uninstall_selected_features; else install_selected_features; fi
        print -r -- "EXIT=$FINAL_EXIT_STATUS"
      ZSH
      assert result.success?, errors
      events = output.lines.grep(/^JOBS_MANAGER_EVENT\t/).map { |line| line.split("\t")[1, 2] }
      assert_equal [['git-pull', 'running'], ['git-rollback', 'running'], ['git-pull', 'succeeded'], ['git-rollback', 'succeeded'], ['run-authorize', 'running'], ['run-authorize', 'failed'], ['path_copier', 'running'], ['path_copier', 'succeeded']], events
      assert_includes output, 'EXIT=1'
    end
  end

  def test_single_package_worker_reports_real_failure_exit_and_uses_gui_leaf_identifier
    path = Dir.glob(File.join(ROOT, 'JobsFlutterTools', 'Scripts/ManageExtension.zsh')).fetch(0)
    output, errors, result = execute(definitions(path) + <<~'ZSH', path)
      ZSH_ARGZERO="$1"
      manager_validate_existing_configuration() { return 0; }
      run_install_operation() { printf 'tail-without-newline'; return 37; }
      manager_main --action install --features flutter-package-ios --non-interactive
    ZSH
    assert_equal 37, result.exitstatus, errors
    events = output.lines.grep(/^JOBS_MANAGER_EVENT\t/).map { |line| line.split("\t")[1, 2] }
    assert_equal [['flutter-package-ios', 'running'], ['flutter-package-ios', 'failed']], events
  end

  def test_all_functional_entrypoints_open_gui_and_never_dispatch_business_by_default
    entries = Dir.glob(File.join(ROOT, 'Jobs*', 'Scripts/ManageExtension.zsh'))
    assert_equal 31, entries.length
    entries.each do |path|
      boundaries = if path.include?('/JobsFileCreator/')
                     <<~'ZSH'
                       manager_main() { main "$@"; }
                       open_management_panel() { print -r -- 'GUI=file-create'; }
                       run_worker() { print -u2 unexpected-worker; return 97; }
                     ZSH
                   else
                     ''
                   end
      output, errors, result = execute(definitions(path) + boundaries + <<~'ZSH', path)
        ZSH_ARGZERO="$1"
        manager_open_gui() { print -r -- "GUI=$MANAGER_UI_SCOPE"; }
        run_install_operation() { print -u2 unexpected-install; return 97; }
        run_uninstall_operation() { print -u2 unexpected-uninstall; return 97; }
        read() { print -u2 unexpected-read; return 97; }
        fzf() { print -u2 unexpected-fzf; return 97; }
        manager_main
      ZSH
      assert result.success?, "#{path}: #{errors}"
      assert_match(/^GUI=.+/, output)
      refute_match(/unexpected-/, output + errors)
    end
  end

  def test_standalone_packages_keep_identical_panel_source_and_launch_support
    STANDALONE.each do |name|
      assert_equal File.binread(File.join(ROOT, 'Scripts', 'SelectFinderExtensionFeatures.swift')), File.binread(File.join(ROOT, name, 'Scripts', 'ManagementPanel.swift')), name
      assert_equal File.binread(File.join(ROOT, 'Scripts', 'FinderManagerGUI.zsh')), File.binread(File.join(ROOT, name, 'Scripts', 'FinderManagerGUI.zsh')), name
    end
  end

  def test_app_bundles_are_text_only_launchers_with_executable_relative_entrypoints
    apps = Dir.glob(File.join(ROOT, '**', '【MacOS】*Finder扩展.app'))
    assert_equal 32, apps.length
    apps.each do |app|
      launcher = File.join(app, 'Contents', 'MacOS', 'LaunchManager')
      assert File.executable?(launcher), app
      assert File.file?(app.sub(/\.app\z/, '.command')), app
      worker = File.join(File.dirname(app), 'Scripts', File.dirname(app) == ROOT ? 'ManageFinderExtensions.zsh' : 'ManageExtension.zsh')
      assert File.file?(worker), app
      output, result = Open3.capture2e('/usr/bin/plutil', '-lint', File.join(app, 'Contents', 'Info.plist'))
      assert result.success?, output
      output, result = Open3.capture2e('/bin/zsh', '-n', launcher)
      assert result.success?, output
      refute_match(/quit.*Terminal|killall.*Terminal|close every/, File.read(launcher))
      assert_includes File.read(launcher), 'tty of targetTab is launchTTY'
      assert_includes File.read(launcher), '(count of processes of targetTab) is 0'
      assert_includes File.read(launcher), 'not busy of targetTab'
    end
  end

  def test_gui_bootstrap_executes_cached_panel_with_worker_scope
    Dir.mktmpdir('jobs-gui-helper-') do |directory|
      scripts = File.join(directory, 'Scripts')
      FileUtils.mkdir_p(scripts)
      FileUtils.mkdir_p(File.join(directory, 'work'))
      File.write(File.join(scripts, 'SelectFinderExtensionFeatures.swift'), '// fixture')
      panel = File.join(directory, 'work', 'SelectFinderExtensionFeatures')
      File.write(panel, "#!/bin/zsh\nprintf '%s\n' \"$@\"\n")
      File.chmod(0o755, panel)
      helper = File.read(File.join(ROOT, 'Scripts', 'FinderManagerGUI.zsh'))
      worker = File.join(scripts, 'ManageFinderExtensions.zsh')
      output, errors, result = execute(helper + <<~'ZSH', worker)
        jobs_manager_launch_error() { print -u2 unexpected-error; return 1; }
        jobs_launch_finder_manager_gui "$1" 'git-pull,run-authorize' uninstall 1
      ZSH
      assert result.success?, errors
      assert_equal ['--manager', worker, '--action', 'uninstall', '--scope', 'git-pull,run-authorize'], output.lines.map(&:chomp)
    end
  end
  def test_actual_launchers_resolve_script_paths_inside_zsh_functions
    Dir.mktmpdir('jobs-launch 中文 ') do |directory|
      Dir.glob(File.join(ROOT, '**', '【MacOS】*Finder扩展.app')).each_with_index do |app, index|
        package = File.join(directory, "功能#{index}")
        local_app = File.join(package, File.basename(app))
        launcher = File.join(local_app, 'Contents', 'MacOS', 'LaunchManager')
        FileUtils.mkdir_p(File.dirname(launcher))
        FileUtils.cp(File.join(app, 'Contents', 'MacOS', 'LaunchManager'), launcher)
        FileUtils.mkdir_p(File.join(package, 'Scripts'))
        worker_name = File.dirname(app) == ROOT ? 'ManageFinderExtensions.zsh' : 'ManageExtension.zsh'
        File.write(File.join(package, 'Scripts', worker_name), "#!/bin/zsh\nprintf '%s\n' \"$@\"\n")
        output, result = Open3.capture2e('/bin/zsh', launcher, '--action', 'uninstall')
        assert result.success?, "#{app}: #{output}"
        assert_equal ['--gui-session', '--action', 'uninstall'], output.lines.map(&:chomp), app
      end
    end
  end

  def test_original_command_entries_only_open_the_full_gui
    entries = Dir.glob(File.join(ROOT, '**', '【MacOS】*Finder扩展.app')).map { |app| app.sub(/\.app\z/, '.command') }
    assert_equal 32, entries.count
    entries.each do |entry|
      source = definitions(entry).gsub('/usr/bin/open', 'fake_open')
      output, errors, result = execute(source + <<~'ZSH', entry)
        ZSH_ARGZERO="$1"
        fake_open() { print -l -r -- "$@"; }
        main
      ZSH
      assert result.success?, "#{entry}: #{errors}"
      assert_equal ['-n', entry.sub(/\.command\z/, '.app'), '--args', '--package-root', File.dirname(entry)], output.lines.map(&:chomp), entry
      refute_match(/--non-interactive|xcodebuild|pluginkit|killall|read /, File.read(entry))
    end
  end

  def test_app_retains_local_action_aliases_as_scoped_gui_selection
    {
      'JobsFlutterTools' => [['--features', 'run,package-android'], 'flutter-run,flutter-package-android'],
      'JobsTerminalOpener' => [['--features', 'file-content'], 'file_content'],
      'JobsIOSTools' => [['--features=ios-code-snippets'], 'ios-code-snippets']
    }.each do |name, (arguments, expected_scope)|
      Dir.mktmpdir('jobs-alias GUI 中文 ') do |directory|
        scripts = File.join(directory, name, 'Scripts')
        FileUtils.mkdir_p(scripts)
        FileUtils.cp(File.join(ROOT, name, 'Scripts/ManageExtension.zsh'), File.join(scripts, 'ManageExtension.zsh'))
        root_scripts = File.join(directory, 'Scripts')
        FileUtils.mkdir_p(root_scripts)
        File.write(File.join(root_scripts, 'ManageFinderExtensions.zsh'), "#!/bin/zsh\nprintf '%s\\n' \"$@\"\n")
        app = Dir.glob(File.join(ROOT, name, '【MacOS】*Finder扩展.app')).fetch(0)
        launcher = File.join(directory, name, File.basename(app), 'Contents/MacOS/LaunchManager')
        FileUtils.mkdir_p(File.dirname(launcher))
        FileUtils.cp(File.join(app, 'Contents/MacOS/LaunchManager'), launcher)
        output, result = Open3.capture2e('/bin/zsh', launcher, *arguments)
        assert result.success?, output
        assert_equal ['--scope', expected_scope, '--action', 'install', '--gui-session'], output.lines.map(&:chomp), name
        source = definitions(launcher) + <<~'ZSH'
          launch_management_error() { print -u2 blocked; return 2; }
          ZSH_ARGZERO="$1"
          shift
          main "$@"
        ZSH
        output, errors, result = execute(source, launcher, '--action', 'uninstall', '--non-interactive')
        assert_equal 2, result.exitstatus, output + errors
        assert_empty output
        assert_includes errors, 'blocked'
      end
    end
  end

  def test_bootstrap_compile_failure_uses_error_dialog_and_preserves_failure_status
    Dir.mktmpdir('jobs-panel-bootstrap-') do |directory|
      FileUtils.mkdir_p(File.join(directory, 'Scripts'))
      File.write(File.join(directory, 'Scripts', 'SelectFinderExtensionFeatures.swift'), '// fixture')
      helper = File.read(File.join(ROOT, 'Scripts', 'FinderManagerGUI.zsh')).gsub('/usr/bin/xcrun', 'fake_compiler')
      output, errors, result = execute(helper + <<~'ZSH', File.join(directory, 'Scripts', 'ManageFinderExtensions.zsh'), env: { 'TMPDIR' => "#{directory}/" })
        fake_compiler() { print -u2 simulated-compiler-error; return 23; }
        jobs_manager_launch_error() { print -r -- "DIALOG=$1|$2"; return 1; }
        jobs_launch_finder_manager_gui "$1" '' install 1
      ZSH
      assert_equal 23, result.exitstatus, errors
      assert_includes output, 'DIALOG='
      assert_includes output, '管理面板编译失败'
      logs = Dir.glob(File.join(directory, 'JobsFinderManagerLaunch.*'))
      assert_equal 1, logs.length
      assert_includes File.read(logs.first), 'simulated-compiler-error'
      refute File.exist?(File.join(directory, 'work', 'SelectFinderExtensionFeatures'))
    end
  end

  def test_changed_panel_source_replaces_stale_cached_binary_without_opening_gui
    Dir.mktmpdir('jobs-panel-source-update-') do |directory|
      scripts = File.join(directory, 'Scripts')
      FileUtils.mkdir_p([scripts, File.join(directory, 'work')])
      source = File.join(scripts, 'SelectFinderExtensionFeatures.swift')
      FileUtils.cp(File.join(ROOT, 'Scripts', 'SelectFinderExtensionFeatures.swift'), source)
      binary = File.join(directory, 'work', 'SelectFinderExtensionFeatures')
      File.write(binary, "#!/bin/zsh\nprint STALE-PANEL\n")
      File.chmod(0o755, binary)
      File.utime(Time.now - 10, Time.now - 10, binary)
      helper = File.read(File.join(ROOT, 'Scripts', 'FinderManagerGUI.zsh')).gsub('/usr/bin/xcrun', 'fake_compiler')
      output, errors, result = execute(helper + <<~'ZSH', File.join(scripts, 'ManageFinderExtensions.zsh'), env: { 'TMPDIR' => "#{directory}/" })
        fake_compiler() {
          [[ "$1" == swiftc && "$2" == -O && "$4" == -o ]] || return 91
          /usr/bin/grep -Fq 'failedStatusClicked' "$3" || return 92
          printf '#!/bin/zsh\nprint REFRESHED-PANEL\nprint -l -r -- "$@"\n' > "$5"
          /bin/chmod 755 "$5"
        }
        jobs_manager_launch_error() { print -u2 unexpected-error; return 1; }
        jobs_launch_finder_manager_gui "$1" 'git-pull' install 1
      ZSH
      assert result.success?, errors
      assert_equal ['REFRESHED-PANEL', '--manager', File.join(scripts, 'ManageFinderExtensions.zsh'), '--action', 'install', '--scope', 'git-pull'], output.lines.map(&:chomp)
      refute_includes File.read(binary), 'STALE-PANEL'
    end
  end
end
