# frozen_string_literal: true
# 真实 zsh/JXA 逻辑隔离回归；Homebrew、fzf、FVM 和 SDK 均用私有假命令，不安装工具。

require 'fileutils'
require 'json'
require 'minitest/autorun'
require 'open3'
require 'tmpdir'

class FlutterVersionCommandTests < Minitest::Test
  SCRIPT = File.expand_path('../Scripts/ManageFlutterVersion.zsh', __dir__)

  def setup
    @root = File.realpath(Dir.mktmpdir('jobs-flutter-command-test-'))
    @project = File.join(@root, "项目 空格 ' $(touch SHOULD_NOT_EXIST)\n第二行")
    @bin = File.join(@root, 'bin')
    @run = File.join(@root, 'run')
    @cache = File.join(@root, 'cache')
    FileUtils.mkdir_p([@project, @bin, @run, @cache])
    @source = File.read(SCRIPT).sub(/^main "\$@"\s*\z/, '')
    # 缺失分支不能逃逸到本机已安装 Homebrew。
    @source = @source.gsub('/opt/homebrew', File.join(@root, 'system-arm')).gsub('/usr/local', File.join(@root, 'system-intel'))
    File.write(File.join(@project, 'pubspec.yaml'), "name: test\ndependencies:\n  flutter:\n    sdk: flutter\n")
    @environment = {
      'HOME' => @root, 'TMPDIR' => @run + '/', 'PATH' => "#{@bin}:/usr/bin:/bin",
      'NO_COLOR' => '1', 'TEST_ROOT' => @root, 'TEST_BIN' => @bin, 'TEST_CACHE' => @cache,
      'TEST_PROJECT' => @project, 'TEST_TRACE' => File.join(@root, 'trace'),
      'TEST_FZF_HEALTHY' => '1', 'TEST_FVM_HEALTHY' => '1', 'TEST_BREW_HEALTHY' => '1'
    }
    write_mock('brew', <<~'ZSH')
      print -r -- "brew|${(j: :)@}" >> "$TEST_TRACE"
      case "$1" in
        --version) [[ "$TEST_BREW_HEALTHY" == 1 || -f "$TEST_ROOT/brew-ready" ]] ;;
        --prefix) print -r -- "$TEST_ROOT" ;;
        config) exit 0 ;;
        list) [[ "$2" == --formula ]] && exit 0; exit 1 ;;
        install|reinstall)
          [[ "${TEST_INSTALL_FAIL:-0}" == 0 ]] || exit 23
          [[ "${TEST_RECHECK_FAIL:-0}" == 0 ]] || exit 0
          /usr/bin/touch "$TEST_ROOT/$2-ready"
          ;;
        *) exit 1 ;;
      esac
    ZSH
    write_mock('fzf', <<~'ZSH')
      if [[ "$1" == --version ]]; then
        [[ "$TEST_FZF_HEALTHY" == 1 || -f "$TEST_ROOT/fzf-ready" ]]
        exit $?
      fi
      print -r -- 'fzf|select' >> "$TEST_TRACE"
      [[ "${TEST_FZF_CANCEL:-0}" == 0 ]] || exit 130
      /usr/bin/head -n 1
    ZSH
    write_mock('fvm', <<~'ZSH')
      print -r -- "fvm|${(j: :)@}" >> "$TEST_TRACE"
      case "$1" in
        --version) [[ "$TEST_FVM_HEALTHY" == 1 || -f "$TEST_ROOT/fvm-ready" ]] ;;
        api) [[ "$*" == *--help* ]] && exit 0; exit 1 ;;
        use)
          if [[ "$2" == --help ]]; then print -r -- '--skip-pub-get'; exit 0; fi
          [[ "${TEST_USE_FAIL:-0}" == 0 ]] || exit 31
          /bin/mkdir -p "$TEST_PROJECT/.fvm" "$TEST_CACHE/$2/bin/cache/dart-sdk/bin"
          /bin/ln -s "$TEST_CACHE/${TEST_LINK_VERSION:-$2}" "$TEST_PROJECT/.fvm/flutter_sdk"
          if [[ "${TEST_FVM_REWRITES_CONFIG:-0}" == 1 ]]; then
            print -r -- "{\"flutter\":\"$2\",\"updateMelosSettings\":false}" > "$TEST_PROJECT/.fvmrc"
          fi
          ;;
        flutter) print -r -- "{\"frameworkVersion\":\"${TEST_ACTUAL_VERSION:-3.29.3}\"}" ;;
        dart) print -r -- 'Dart SDK version: fixture' ;;
        *) exit 1 ;;
      esac
    ZSH
    @bootstrap = <<~'ZSH'
      LOG_FILE="$TEST_ROOT/run/action.log"
      FM_RUN_DIR="$TEST_ROOT/run"
      FM_PROJECT="$TEST_PROJECT"
      FM_BREW="$TEST_BIN/brew"
      FM_BREW_PREFIX="$TEST_ROOT"
      FM_FZF="$TEST_BIN/fzf"
      FM_FVM="$TEST_BIN/fvm"
      FM_CACHE_PATH="$TEST_CACHE"
      FM_CONTEXT_URL='https://github.com/flutter/flutter.git'
      : > "$LOG_FILE"
      fm_confirm_dependency() { fm_log "DEPENDENCY-CONFIRM|$1"; }
    ZSH
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def test_common_yaml_forms_are_accepted_and_misleading_text_is_rejected
    good = ["dependencies:\n  flutter:\n    sdk: flutter # official\n",
            "'dependencies':\n  \"flutter\": {sdk: 'flutter'}\n",
            'dependencies: {flutter: {sdk: flutter}}']
    bad = ["name: dart_only\ndependencies:\n  http: any\n",
           "# dependencies:\n#   flutter:\n#     sdk: flutter\n",
           "description: |\n  dependencies:\n    flutter:\n      sdk: flutter\n",
           "dev_dependencies:\n  flutter_test:\n    sdk: flutter\n",
           "dependencies:\n  example:\n    flutter:\n      sdk: flutter\n",
           "dependencies:\n  flutter:\n    sdk: dart\n",
           "dependencies:\n  flutter:\n    sdk: flutter\ndependencies:\n  http: any\n"]
    good.each_with_index do |contents, index|
      file = write_data("good#{index}.yaml", contents)
      output, status = execute("fm_data pubspec \"$1\"", file)
      assert status.success?, output
      assert_equal 'flutter', output.strip
    end
    bad.each_with_index do |contents, index|
      file = write_data("bad#{index}.yaml", contents)
      output, status = execute("fm_data pubspec \"$1\"", file)
      refute status.success?, "误识别：#{contents}\n#{output}"
    end
  end

  def test_official_release_rows_mark_current_latest_cache_and_deduplicate_architectures
    add_cached_sdk('3.29.3')
    cache = write_json('cache.json', { 'versions' => [{ 'name' => '3.29.3', 'directory' => File.join(@cache, '3.29.3'), 'isSetup' => true }] })
    releases = release_fixture
    releases['releases'] << releases['releases'][0].merge('dart_sdk_arch' => 'x64')
    releases['releases'] << releases['releases'][0].dup
    file = write_json('releases.json', releases)
    output, status = execute('fm_data render "$1" "$2" 3.29.3 stable arm64', file, cache)
    assert status.success?, output
    assert_equal 1, output.lines.length
    assert_includes output, "3.29.3\t2025-04-14\tstable\tarm64"
    %w[当前 已缓存].each { |flag| assert_includes output, flag }
    assert_includes output, '最新 stable'
    refute_includes output, '需要Rosetta'
  end

  def test_malformed_latest_pointer_and_uninitialized_cache_are_not_advertised
    cache = write_json('cache.json', { 'versions' => [{ 'name' => '3.29.3', 'directory' => @cache, 'isSetup' => false }] })
    releases = release_fixture
    releases['current_release']['stable'] = 'b' * 40
    file = write_json('releases.json', releases)
    output, status = execute('fm_data render "$1" "$2" 3.29.3 all arm64', file, cache)
    refute status.success?, output
    output, status = execute('fm_data render - "$1" 3.29.3 cached arm64', cache)
    assert status.success?, output
    assert_empty output.strip
  end

  def test_intel_history_retains_hotfix_versions_and_current_architecture_is_enforced
    releases = release_fixture
    releases['releases'] << { 'version' => '1.12.13+hotfix.9', 'channel' => 'stable', 'hash' => 'c' * 40,
                              'release_date' => '2020-04-18T12:00:00Z', 'dart_sdk_arch' => 'x64' }
    file = write_json('releases.json', releases)
    cache = write_json('cache.json', { 'versions' => [] })
    output, status = execute('fm_data render "$1" "$2" 1.12.13+hotfix.9 stable x64', file, cache)
    assert status.success?, output
    assert_includes output, "1.12.13+hotfix.9\t"
    refute_includes output, '3.29.3'
    output, status = execute('fm_data render "$1" "$2" 3.29.3 stable arm64', file, cache)
    assert status.success?, output
    assert_includes output, "3.29.3\t"
    refute_includes output, '1.12.13+hotfix.9'
  end

  def test_configuration_merge_preserves_fields_and_only_pins_the_target
    config = { 'flutter' => '3.19.0', 'flavors' => { 'production' => '3.19.0' },
               'updateVscodeSettings' => false, 'custom' => { 'keep' => 42 }, 'updateMelosSettings' => true }
    file = write_json('config.json', config)
    original = File.binread(file)
    output, status = execute('fm_data merge "$1" 3.29.3', file)
    assert status.success?, output
    merged = JSON.parse(output)
    assert_equal '3.29.3', merged['flutter']
    assert_equal false, merged['updateMelosSettings']
    %w[flavors updateVscodeSettings custom].each { |key| assert_equal config[key], merged[key] }
    assert_equal original, File.binread(file)
  end

  def test_network_failure_offers_only_initialized_cache_and_stops_when_none_exists
    add_cached_sdk('3.29.3')
    file = write_json('cache.json', { 'versions' => [{ 'name' => '3.29.3', 'directory' => File.join(@cache, '3.29.3'), 'isSetup' => true }] })
    write_mock('curl', 'exit 22')
    commands = <<~'ZSH'
      fm_inspect_api() { /bin/cat "$TEST_ROOT/cache.json"; }
      FM_CURL="$TEST_BIN/curl"
      fm_fetch_versions
      print -r -- "ONLINE=$FM_ONLINE"
    ZSH
    output, status = execute(commands)
    assert status.success?, output
    assert_includes output, '无法确认最新版本'
    assert_includes output, 'ONLINE=0'
    assert_includes File.read(File.join(@run, 'cached.tsv')), '3.29.3'
    File.write(file, '{"versions":[]}')
    output, status = execute(commands)
    refute status.success?, output
    assert_includes output, '没有可供离线选择'
    refute File.exist?(File.join(@project, '.fvmrc'))
  end

  def test_healthy_chain_is_reused_without_package_installation
    output, status = execute('fm_ensure_brew; fm_ensure_fzf; fm_ensure_fvm')
    assert status.success?, output
    refute_match(/brew\|(?:install|reinstall|upgrade|update|cleanup)/, trace)
    refute File.exist?(File.join(@project, '.fvmrc'))
  end

  def test_missing_terminal_tools_are_installed_once_and_rechecked
    output, status = execute('fm_ensure_brew; fm_ensure_fzf; fm_ensure_fvm', env: { 'TEST_FZF_HEALTHY' => '0', 'TEST_FVM_HEALTHY' => '0' })
    assert status.success?, output
    assert_equal 1, trace.scan('brew|install fzf').length
    assert_equal 1, trace.scan('brew|install fvm').length
    assert File.exist?(File.join(@root, 'fzf-ready'))
    assert File.exist?(File.join(@root, 'fvm-ready'))
    refute File.exist?(File.join(@project, '.fvmrc'))
  end

  def test_multiple_missing_layers_are_prepared_in_order
    commands = <<~'ZSH'
      fm_install_brew() { print -r -- 'brew|bootstrap' >> "$TEST_TRACE"; /usr/bin/touch "$TEST_ROOT/brew-ready"; FM_BREW="$TEST_BIN/brew"; FM_BREW_PREFIX="$TEST_ROOT"; }
      fm_ensure_brew
      fm_ensure_fzf
      fm_ensure_fvm
    ZSH
    output, status = execute(commands, env: { 'TEST_BREW_HEALTHY' => '0', 'TEST_FZF_HEALTHY' => '0', 'TEST_FVM_HEALTHY' => '0' })
    assert status.success?, output
    assert_operator trace.index('brew|bootstrap'), :<, trace.index('brew|install fzf')
    assert_operator trace.index('brew|install fzf'), :<, trace.index('brew|install fvm')
  end

  def test_install_failure_and_failed_recheck_stop_before_downstream_sdk_changes
    [{ 'TEST_INSTALL_FAIL' => '1' }, { 'TEST_RECHECK_FAIL' => '1' }].each do |failure|
      File.unlink(File.join(@root, 'trace')) if File.exist?(File.join(@root, 'trace'))
      output, status = execute('fm_ensure_fzf; fm_ensure_fvm', env: failure.merge('TEST_FZF_HEALTHY' => '0'))
      refute status.success?, output
      assert_equal 1, trace.scan('brew|install fzf').length
      refute_includes trace, 'brew|install fvm'
      refute File.exist?(File.join(@project, '.fvmrc'))
    end
  end

  def test_escape_leaves_project_untouched
    write_data('run/cached.tsv', "3.29.3\t未知日期\t本机缓存\t待SDK核验\t离线/最新未知\n")
    output, status = execute('FM_ONLINE=0; fm_select_version', env: { 'TEST_FZF_CANCEL' => '1' })
    assert status.success?, output
    assert_includes output, '已取消'
    refute File.exist?(File.join(@project, '.fvmrc'))
  end

  def test_final_nonempty_confirmation_cancels_before_project_changes
    ["go\n", " \n", "取消\n"].each do |answer|
      output, status = execute(<<~'ZSH', input: answer)
        FM_SELECTED=3.29.3
        fm_confirm_project_change
        fm_prepare_project_config
        fm_apply_and_verify
      ZSH
      assert status.success?, output
      assert_includes output, '已取消'
      refute File.exist?(File.join(@project, '.fvmrc'))
      refute File.exist?(File.join(@project, '.fvm'))
      refute_includes trace, 'fvm|use'
    end
  end

  def test_final_enter_continues_to_install_and_verify_the_selected_version
    output, status = execute(<<~'ZSH', input: "\n")
      FM_SELECTED=3.29.3
      fm_read_effective_context() { return 0; }
      fm_prepare_inspection_config
      fm_confirm_project_change
      fm_prepare_project_config
      fm_apply_and_verify
    ZSH
    assert status.success?, output
    assert_includes trace, 'fvm|use 3.29.3 --skip-pub-get'
    assert_equal '3.29.3', JSON.parse(File.read(File.join(@project, '.fvmrc')))['flutter']
    assert_includes output, '项目 Flutter 已核验'
  end

  def test_final_confirmation_eof_stops_without_project_changes
    output, status = execute('FM_SELECTED=3.29.3; fm_confirm_project_change; fm_prepare_project_config; fm_apply_and_verify')
    refute status.success?, output
    refute File.exist?(File.join(@project, '.fvmrc'))
    refute_includes trace, 'fvm|use'
  end

  def test_explicit_target_config_does_not_overwrite_ancestor_or_other_fields
    parent = File.join(@root, '.fvmrc')
    File.write(parent, "{\"flutter\":\"3.19.0\",\"keep\":true}\n")
    config = { 'flutter' => '3.24.0', 'custom' => 123 }
    File.write(File.join(@project, '.fvmrc'), JSON.generate(config))
    original = File.binread(parent)
    output, status = execute(<<~'ZSH')
      FM_SELECTED=3.29.3
      fm_read_effective_context() { return 0; }
      fm_prepare_inspection_config
      fm_prepare_project_config
    ZSH
    assert status.success?, output
    actual = JSON.parse(File.read(File.join(@project, '.fvmrc')))
    assert_equal '3.29.3', actual['flutter']
    assert_equal 123, actual['custom']
    assert_equal false, actual['updateMelosSettings']
    assert_equal original, File.binread(parent)
    assert_equal config, JSON.parse(File.read(File.join(@run, 'before/.fvmrc')))
    refute File.exist?(File.join(@project, 'SHOULD_NOT_EXIST'))
  end

  def test_success_requires_both_project_link_and_real_sdk_version_to_match
    File.write(File.join(@project, '.fvmrc'), '{"flutter":"3.29.3"}')
    output, status = execute('FM_SELECTED=3.29.3; /bin/cp "$FM_PROJECT/.fvmrc" "$FM_RUN_DIR/next-fvmrc.json"; fm_apply_and_verify')
    assert status.success?, output
    assert_includes trace, 'fvm|use 3.29.3 --skip-pub-get'
    assert_includes output, '项目 Flutter 已核验'
    assert File.symlink?(File.join(@project, '.fvm/flutter_sdk'))
    refute_match(/fvm\|(?:global|upgrade)/, trace)
  end

  def test_fvm_config_serialization_does_not_discard_existing_custom_fields
    File.write(File.join(@project, '.fvmrc'), JSON.generate({ 'flutter' => '3.19.0', 'custom' => { 'keep' => 42 } }))
    output, status = execute(<<~'ZSH', env: { 'TEST_FVM_REWRITES_CONFIG' => '1' })
      FM_SELECTED=3.29.3
      fm_read_effective_context() { return 0; }
      fm_prepare_inspection_config
      fm_prepare_project_config
      fm_apply_and_verify
    ZSH
    assert status.success?, output
    config = JSON.parse(File.read(File.join(@project, '.fvmrc')))
    assert_equal '3.29.3', config['flutter']
    assert_equal({ 'keep' => 42 }, config['custom'])
    assert_equal false, config['updateMelosSettings']
  end

  def test_configuration_changed_during_selection_is_preserved_and_rejected
    path = File.join(@project, '.fvmrc')
    File.write(path, '{"flutter":"3.19.0"}')
    output, status = execute(<<~'ZSH')
      fm_prepare_inspection_config
      print -r -- '{"flutter":"3.24.0","manualEdit":true}' > "$FM_PROJECT/.fvmrc"
      FM_SELECTED=3.29.3
      fm_prepare_project_config
    ZSH
    refute status.success?, output
    assert_includes output, '配置已被修改'
    assert_equal({ 'flutter' => '3.24.0', 'manualEdit' => true }, JSON.parse(File.read(path)))
    refute File.exist?(File.join(@project, '.fvm'))
  end

  def test_cli_rejects_symbolic_link_and_application_package_before_canonicalization
    link = File.join(@root, 'project-link')
    File.symlink(@project, link)
    output, status = execute('fm_validate_invocation --project "$1"', link)
    refute status.success?, output
    package = File.join(@root, 'Fixture.app')
    FileUtils.mkdir_p(package)
    FileUtils.cp(File.join(@project, 'pubspec.yaml'), File.join(package, 'pubspec.yaml'))
    output, status = execute('fm_validate_invocation --project "$1"', package)
    refute status.success?, output
    refute File.exist?(File.join(package, '.fvmrc'))
  end

  def test_fvm_metadata_symlinks_are_rejected_without_writing_their_targets
    FileUtils.mkdir_p(File.join(@project, '.fvm'))
    outside = write_data('outside.txt', 'keep outside unchanged')
    %w[version release fvm_config.json].each do |name|
      link = File.join(@project, '.fvm', name)
      File.symlink(outside, link)
      output, status = execute('fm_check_project_boundaries')
      refute status.success?, output
      assert_includes output, '符号链接'
      assert_equal 'keep outside unchanged', File.read(outside)
      File.unlink(link)
    end
  end

  def test_sdk_mismatch_and_fvm_failure_report_partial_changes_truthfully
    File.write(File.join(@project, '.fvmrc'), '{"flutter":"3.29.3"}')
    output, status = execute('FM_MUTATION_STARTED=1; FM_SELECTED=3.29.3; /bin/cp "$FM_PROJECT/.fvmrc" "$FM_RUN_DIR/next-fvmrc.json"; fm_apply_and_verify', env: { 'TEST_ACTUAL_VERSION' => '3.19.0' })
    refute status.success?, output
    assert_includes output, '实际 SDK 版本不匹配'
    assert_includes output, '无法安全对齐'
    output, status = execute('FM_MUTATION_STARTED=1; FM_SELECTED=3.29.3; /bin/cp "$FM_PROJECT/.fvmrc" "$FM_RUN_DIR/next-fvmrc.json"; fm_apply_and_verify', env: { 'TEST_USE_FAIL' => '1' })
    assert_equal 31, status.exitstatus, output
    assert_includes output, 'fvm use 失败'
    assert_includes output, '配置快照'
  end

  def test_noninteractive_real_entry_stops_without_logs_or_project_writes
    before = Dir.children(@run).sort
    output, status = Open3.capture2e(@environment, '/bin/zsh', '-f', SCRIPT, '--project', @project)
    refute status.success?, output
    assert_includes output, 'TTY'
    assert_equal before, Dir.children(@run).sort
    refute File.exist?(File.join(@project, '.fvmrc'))
  end

  def test_failed_use_restores_previous_config_when_sdk_link_is_untouched
    File.write(File.join(@project, '.fvmrc'), '{"flutter":"3.19.0","keep":true}')
    output, status = execute(<<~'ZSH', env: { 'TEST_USE_FAIL' => '1' })
      FM_SELECTED=3.29.3
      fm_read_effective_context() { return 0; }
      fm_prepare_inspection_config
      fm_prepare_project_config
      fm_apply_and_verify
    ZSH
    refute status.success?, output
    assert_includes output, '已把 .fvmrc 还原'
    assert_equal({ 'flutter' => '3.19.0', 'keep' => true }, JSON.parse(File.read(File.join(@project, '.fvmrc'))))
    refute File.exist?(File.join(@project, '.fvm/flutter_sdk'))
  end

  def test_failed_use_removes_the_config_created_by_this_run
    output, status = execute(<<~'ZSH', env: { 'TEST_USE_FAIL' => '1' })
      FM_SELECTED=3.29.3
      fm_read_effective_context() { return 0; }
      fm_prepare_inspection_config
      fm_prepare_project_config
      fm_apply_and_verify
    ZSH
    refute status.success?, output
    assert_includes output, '已删除本次新建的 .fvmrc'
    refute File.exist?(File.join(@project, '.fvmrc'))
  end

  def test_verification_failure_leaves_an_already_consistent_config_untouched
    File.write(File.join(@project, '.fvmrc'), '{"flutter":"3.19.0"}')
    output, status = execute(<<~'ZSH', env: { 'TEST_ACTUAL_VERSION' => '3.19.0' })
      FM_SELECTED=3.29.3
      fm_read_effective_context() { return 0; }
      fm_prepare_inspection_config
      fm_prepare_project_config
      fm_apply_and_verify
    ZSH
    refute status.success?, output
    assert_includes output, '实际 SDK 版本不匹配'
    assert_includes output, '与 SDK 链接已一致：3.29.3'
    assert_equal '3.29.3', JSON.parse(File.read(File.join(@project, '.fvmrc')))['flutter']
    assert File.symlink?(File.join(@project, '.fvm/flutter_sdk'))
  end

  def test_failed_verification_aligns_config_to_the_real_link_version
    File.write(File.join(@project, '.fvmrc'), '{"flutter":"3.19.0"}')
    add_cached_sdk('3.24.0')
    output, status = execute(<<~'ZSH', env: { 'TEST_ACTUAL_VERSION' => '3.19.0', 'TEST_LINK_VERSION' => '3.24.0' })
      FM_SELECTED=3.29.3
      fm_read_effective_context() { return 0; }
      fm_prepare_inspection_config
      fm_prepare_project_config
      fm_apply_and_verify
    ZSH
    refute status.success?, output
    assert_includes output, '对齐到链接的真实版本：3.24.0'
    assert_equal '3.24.0', JSON.parse(File.read(File.join(@project, '.fvmrc')))['flutter']
  end

  def test_confirmation_reports_whether_the_selected_version_is_cached
    write_json('run/cache.json', { 'versions' => [{ 'name' => '3.29.3', 'directory' => File.join(@cache, '3.29.3'), 'isSetup' => true }] })
    output, status = execute('FM_SELECTED=3.29.3; fm_confirm_project_change', input: "取消\n")
    assert status.success?, output
    assert_includes output, '已在本机缓存'
    write_json('run/cache.json', { 'versions' => [] })
    output, status = execute('FM_SELECTED=3.29.3; fm_confirm_project_change', input: "取消\n")
    assert status.success?, output
    assert_includes output, '未在本机缓存'
  end

  private

  def execute(commands, *args, env: {}, input: '')
    file = File.join(@root, 'fixture.zsh')
    File.write(file, @source + "\n" + @bootstrap + "\n" + commands + "\n")
    Open3.capture2e(@environment.merge(env), '/bin/zsh', '-f', file, *args, stdin_data: input)
  end

  def write_mock(name, body)
    file = File.join(@bin, name)
    File.write(file, "#!/bin/zsh\n" + body + "\n")
    File.chmod(0o700, file)
  end

  def write_data(name, contents)
    file = File.join(@root, name)
    FileUtils.mkdir_p(File.dirname(file))
    File.write(file, contents)
    file
  end

  def write_json(name, contents)
    write_data(name, JSON.generate(contents))
  end

  def add_cached_sdk(version)
    %w[bin/flutter bin/cache/dart-sdk/bin/dart].each do |relative|
      path = File.join(@cache, version, relative)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "#!/bin/zsh\nexit 0\n")
      File.chmod(0o700, path)
    end
  end

  def release_fixture
    { 'current_release' => { 'stable' => 'a' * 40 }, 'releases' => [
      { 'version' => '3.29.3', 'channel' => 'stable', 'hash' => 'a' * 40,
        'release_date' => '2025-04-14T12:00:00Z', 'dart_sdk_arch' => 'arm64' }
    ] }
  end

  def trace
    path = File.join(@root, 'trace')
    File.exist?(path) ? File.read(path) : ''
  end
end
