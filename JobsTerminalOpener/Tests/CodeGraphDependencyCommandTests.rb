# frozen_string_literal: true
# CodeGraph 右键命令隔离回归：只运行提取出的真实脚本，所有安装和建图工具均为临时假命令。

require 'fileutils'
require 'json'
require 'minitest/autorun'
require 'open3'
require 'pty'
require 'timeout'
require 'tmpdir'

class CodeGraphDependencyCommandTests < Minitest::Test
  def setup
    @root = File.realpath(Dir.mktmpdir('jobs-codegraph-test-'))
    @project = File.join(@root, "工程 空格 ' $(touch SHOULD_NOT_EXIST)")
    @bin = File.join(@root, 'bin')
    @logs = File.join(@root, 'logs')
    @templates = File.join(@root, 'templates')
    @brew_prefix = File.join(@root, 'existing-brew')
    @user_brew = File.join(@root, 'user-brew')
    @system_brew = File.join(@root, 'system-brew')
    @trace = File.join(@root, 'trace')
    FileUtils.mkdir_p([@project, @bin, @logs, @templates, @brew_prefix, File.join(@root, 'clt')])
    File.write(File.join(@root, '.zprofile'), "# keep zprofile\n")
    File.write(File.join(@root, '.bash_profile'), "# keep bash profile\n")
    %w[awk cat chmod cmp cp git head ls mkdir mktemp mv rm rmdir sed].each do |name|
      system_path = ["/bin/#{name}", "/usr/bin/#{name}"].find { |path| File.executable?(path) }
      File.symlink(system_path, File.join(@bin, name)) if system_path
    end
    @environment = {
      'PATH' => @bin, 'HOME' => @root, 'TMPDIR' => @logs, 'NO_COLOR' => '1', 'SHELL' => '/bin/zsh',
      'LANG' => 'zh_CN.UTF-8', 'LC_CTYPE' => 'UTF-8',
      'JOBS_HOMEBREW_BIN' => File.join(@bin, 'brew'), 'JOBS_HOMEBREW_INSTALL_PREFIX' => @user_brew,
      'CODEGRAPH_TEST_ROOT' => @root, 'CODEGRAPH_TEST_TRACE' => @trace,
      'CODEGRAPH_TEST_PROJECT' => @project, 'CODEGRAPH_TEST_PROJECT_JSON' => JSON.generate(@project),
      'CODEGRAPH_TEST_INDEX_JSON' => JSON.generate(File.join(@project, '.codegraph')),
      'CODEGRAPH_TEST_INITIAL_CLI' => File.join(@bin, 'codegraph'),
      'CODEGRAPH_TEST_BREW_PREFIX' => @brew_prefix,
      'CODEGRAPH_TEST_SYSTEM_PREFIX' => @system_brew,
      'CODEGRAPH_TEST_BIN' => @bin, 'CODEGRAPH_TEST_TEMPLATES' => @templates
    }
    write_mock('codegraph', codegraph_mock)
    write_mock('brew', brew_mock)
    write_mock('node', node_mock)
    write_mock('npm', npm_mock)
    write_mock('curl', curl_mock)
    write_mock('git', git_mock)
    write_mock('xcode-select', <<~'SH')
      if [ "$1" = -p ]; then
        [ "${CODEGRAPH_TEST_CLT_EXIT:-0}" = 0 ] || exit "$CODEGRAPH_TEST_CLT_EXIT"
        printf '%s/clt\n' "$CODEGRAPH_TEST_ROOT"
      else
        exit "${CODEGRAPH_TEST_CLT_INSTALL_EXIT:-0}"
      fi
    SH
    write_mock('xcrun', 'printf "%s/clang\n" "$CODEGRAPH_TEST_BIN"')
    write_mock('clang', 'exit "${CODEGRAPH_TEST_CLANG_EXIT:-0}"')
    source = File.read(File.expand_path('../JobsTerminalFinderSync/TerminalOpener.swift', __dir__))
    embedded = %w[codeGraphDependencyCommand codeGraphHomebrewCommand].map do |name|
      match = source.match(/func #{name}\(\) -> String \{\n        #"""\n(.*?)\n        """#/m)
      raise "没有找到真实 #{name} 脚本" unless match

      match[1].lines.map { |line| line.delete_prefix('        ') }.join
    end.join("\n") + "\nmain \"$@\"\n"
    # 只隔离固定系统安装候选，避免缺失测试发现本机真实的 Homebrew 或 CodeGraph。
    embedded = embedded.gsub('/opt/homebrew', @system_brew).gsub('/usr/local', @system_brew)
    @script = File.join(@root, 'codegraph-command.zsh')
    File.write(@script, embedded)
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def test_real_embedded_script_has_valid_zsh_syntax
    output, exit_status = Open3.capture2e('/bin/zsh', '-n', @script)
    assert exit_status.success?, output
  end

  def test_actual_node_probe_rejects_unsupported_runtime_versions
    host_node = ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).map { |entry| File.join(entry, 'node') }
                   .find { |candidate| File.executable?(candidate) && !File.directory?(candidate) }
    skip '主机没有 Node；安装链仍使用隔离假命令验证' unless host_node

    expression = File.read(@script).match(/"\$CODEGRAPH_NODE_BIN" -e '([^']+)'/)[1]
    runner = <<~'JS'
      const vm = require('node:vm');
      const expression = JSON.parse(process.argv[1]);
      for (const major of [18, 20, 22, 24, 25, 26]) {
        let healthy = true;
        try {
          vm.runInNewContext(expression, {
            process: {versions: {node: `${major}.0.0`}, exit(code) {throw code;}}, require
          });
        } catch (error) {
          if (error !== 1) throw error;
          healthy = false;
        }
        if (healthy !== (major >= 20 && major < 25)) throw new Error(`Node ${major} 判定错误`);
      }
    JS
    output, exit_status = Open3.capture2e(host_node, '-e', runner, JSON.generate(expression))
    assert exit_status.success?, output
  end

  def test_healthy_cli_creates_only_the_selected_map_without_tool_updates
    output, exit_status = run_command(input: "\n")
    assert_equal 0, exit_status, output
    assert_includes trace, "codegraph|init --yes #{@project}"
    assert_includes trace, "codegraph|status --json #{@project}"
    assert File.file?(File.join(@project, '.codegraph/mock-index'))
    assert_includes trace, 'brew|doctor'
    assert_includes trace, 'node|-e '
    assert_includes trace, 'npm|config get prefix'
    assert_includes trace, 'curl|--version'
    assert_includes trace, 'git|--version'
    refute_match(/brew\|(?:install|reinstall|update|upgrade)|npm\|(?:install|update|uninstall)|curl\|[^\n]*https:/, trace)
    refute_match(/codegraph\|(?:upgrade|install|watch|serve)/, trace)
    assert_includes trace, 'map-env|watch=0;download=1;telemetry=0;track=1;dir=.codegraph'
    refute File.exist?(File.join(@project, 'SHOULD_NOT_EXIST'))
    assert_includes output, '代码地图更新完成'
    assert_includes File.read(log_files.fetch(0)), 'mock codegraph init'
    refute_match(/\e\[/, output)
    assert_profiles_preserved
  end

  def test_healthy_standalone_cli_reports_missing_installation_upstream_without_installing_it
    remove_brew
    remove_node_npm
    %w[curl git xcode-select xcrun clang].each { |name| File.delete(File.join(@bin, name)) }
    output, exit_status = run_command(input: "\n")
    assert_equal 0, exit_status, output
    assert_includes output, '工具链健康体检'
    assert_includes output, 'Homebrew 缺失或版本/前缀检查失败'
    assert_includes output, 'Node.js / npm 缺失或真实执行失败'
    assert_includes output, 'Command Line Tools 缺失或不可用'
    assert_includes output, 'curl 缺失'
    assert_includes output, 'Git 缺失'
    assert_includes output, '代码地图更新完成'
    refute_match(/(?:brew|node|npm|curl|git)\|/, trace)
    assert_profiles_preserved
  end

  def test_healthy_cli_still_reports_broken_node_npm_brew_and_download_tools
    @environment['CODEGRAPH_TEST_NODE_EXIT'] = '41'
    @environment['CODEGRAPH_TEST_BREW_CONFIG_EXIT'] = '42'
    @environment['CODEGRAPH_TEST_CURL_EXIT'] = '43'
    output, exit_status = run_command(input: "\n")
    assert_equal 0, exit_status, output
    assert_includes output, 'Homebrew 配置 不可用'
    assert_includes output, '退出码 42'
    assert_includes output, 'curl 不可用'
    assert_includes output, '退出码 43'
    assert_includes output, 'Node.js / npm 缺失或真实执行失败'
    refute_match(/brew\|(?:install|reinstall|update|upgrade)|npm\|install/, trace)
    assert_operator output.index('工具链健康体检'), :<, output.index('mock codegraph init')
    assert_profiles_preserved
  end

  def test_healthy_cli_runs_brew_doctor_and_reports_its_warning_without_upgrading
    @environment['CODEGRAPH_TEST_BREW_DOCTOR_EXIT'] = '44'
    output, exit_status = run_command(input: "\n")
    assert_equal 0, exit_status, output
    assert_includes output, 'Homebrew doctor 不可用'
    assert_includes output, '退出码 44'
    refute_match(/brew\|(?:install|reinstall|update|upgrade)/, trace)
    assert_profiles_preserved
  end

  def test_existing_map_is_checked_then_synced_without_reinitializing_or_deleting
    create_graph_database(@project)
    sentinel = File.join(@project, '.codegraph/keep-me')
    File.write(sentinel, 'existing index')
    output, exit_status = run_command(input: "\n")
    assert_equal 0, exit_status, output
    assert_equal 2, trace.scan('codegraph|status --json').length
    assert_includes trace, "codegraph|sync #{@project}"
    refute_includes trace, 'codegraph|init --yes'
    assert_equal 'existing index', File.read(sentinel)
    assert_operator trace.index('codegraph|status --json'), :<, trace.index("codegraph|sync #{@project}")
  end

  def test_noninteractive_input_stops_before_logs_or_tool_execution
    output, exit_status = Open3.capture2e(@environment, '/bin/zsh', '-f', @script, @project,
                                         stdin_data: "\n\n", unsetenv_others: true)
    refute exit_status.success?
    assert_includes output, '没有可交互输入'
    assert_empty trace
    assert_empty log_files
    refute File.exist?(File.join(@project, '.codegraph'))
  end

  def test_waiting_for_the_first_confirmation_does_not_write_or_probe_tools
    output, exit_status = run_command(input: "\u0003", before_input: lambda {
      assert_empty trace
      assert_empty log_files
      refute File.exist?(File.join(@project, '.codegraph'))
    })
    refute_equal 0, exit_status
    assert_includes output, '已了解用途与影响'
    assert_empty trace
    assert_empty log_files
  end

  def test_cancelling_missing_cli_installation_does_not_run_installation_tools_or_build_map
    remove_cli
    output, exit_status = run_command(input: "\nCANCEL\n")
    assert_equal 0, exit_status, output
    assert_includes output, '已取消安装'
    assert_empty trace
    refute File.exist?(File.join(@root, '.local'))
    refute File.exist?(File.join(@project, '.codegraph'))
    assert_profiles_preserved
  end

  def test_missing_cli_uses_official_npm_package_and_user_prefix_after_confirmation
    remove_cli
    output, exit_status = run_command
    assert_equal 0, exit_status, output
    expected_prefix = File.join(@root, '.local/share/jobs-codegraph')
    assert_includes trace, "npm|install --global --prefix #{expected_prefix} --registry https://registry.npmjs.org/"
    assert_includes trace, '@colbymchenry/codegraph@latest'
    assert_includes trace, "map-bin|#{expected_prefix}/bin/codegraph"
    assert_includes trace, 'brew|doctor'
    assert_includes trace, 'npm|ping --registry https://registry.npmjs.org/'
    refute_match(/brew\|(?:upgrade|update|install node|reinstall node)\b/, trace)
    refute_match(/npm\|(?:config set|uninstall|update)/, trace)
    assert_operator output.index('来源｜CodeGraph'), :<, output.index('mock npm install')
    assert_profiles_preserved
  end

  def test_broken_cli_and_broken_help_are_replaced_once_in_the_user_prefix
    @environment['CODEGRAPH_TEST_INITIAL_VERSION_EXIT'] = '19'
    output, exit_status = run_command
    assert_equal 0, exit_status, output
    assert_equal 1, trace.scan('npm|install --global').length
    assert_includes output, 'mock codegraph init'
    refute_includes trace, 'codegraph|upgrade'
    File.delete(@trace)
    FileUtils.remove_entry(File.join(@root, '.local'))
    FileUtils.remove_entry(File.join(@project, '.codegraph'))
    @environment.delete('CODEGRAPH_TEST_INITIAL_VERSION_EXIT')
    @environment['CODEGRAPH_TEST_INITIAL_HELP_EXIT'] = '20'
    output, exit_status = run_command
    assert_equal 0, exit_status, output
    assert_equal 1, trace.scan('npm|install --global').length
  end

  def test_missing_node_npm_are_installed_by_brew_and_rechecked_before_cli_installation
    remove_cli
    remove_node_npm
    output, exit_status = run_command
    assert_equal 0, exit_status, output
    assert_includes trace, 'brew|install node@24'
    assert_operator trace.index('brew|install node@24'), :<, trace.index('npm|install --global')
    assert_includes trace, 'node|-e '
    assert_profiles_preserved
  end

  def test_registered_broken_node_npm_are_reinstalled_once
    remove_cli
    remove_node_npm
    File.write(File.join(@brew_prefix, 'node-registered'), 'registered')
    @environment['CODEGRAPH_TEST_NPM_VERSION_EXIT'] = '21'
    @environment['CODEGRAPH_TEST_REPAIR_RESETS_NPM'] = '1'
    output, exit_status = run_command
    assert_equal 0, exit_status, output
    assert_equal 1, trace.scan('brew|reinstall node@24').length
    refute_includes trace, 'brew|install node@24'
  end

  def test_missing_brew_can_choose_system_location_without_touching_profiles
    remove_cli
    remove_brew
    @environment['CODEGRAPH_TEST_BREW_PREFIX'] = @system_brew
    output, exit_status = run_command(input: "\n\nYES\n")
    assert_equal 0, exit_status, output
    assert_includes trace, 'installer|system'
    assert_includes trace, 'https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh'
    assert File.file?(File.join(@system_brew, 'bin/brew'))
    refute File.exist?(@user_brew)
    assert_profiles_preserved
  end

  def test_missing_brew_can_choose_user_location_without_sudo_or_profile_changes
    remove_cli
    remove_brew
    @environment['CODEGRAPH_TEST_BREW_PREFIX'] = @user_brew
    output, exit_status = run_command(input: "\n\n\n")
    assert_equal 0, exit_status, output
    assert_includes trace, 'https://api.github.com/repos/Homebrew/brew/releases/latest'
    assert_includes trace, 'https://github.com/Homebrew/brew.git'
    assert File.file?(File.join(@user_brew, 'bin/brew'))
    refute File.exist?(@system_brew)
    refute_includes trace, 'installer|system'
    assert_profiles_preserved
  end

  def test_missing_or_broken_curl_stops_before_brew_or_npm
    remove_cli
    @environment['CODEGRAPH_TEST_CURL_EXIT'] = '22'
    output, exit_status = run_command
    assert_equal 1, exit_status
    assert_includes output, 'curl 不可用'
    refute_match(/(?:brew|npm)\|/, trace)
    File.delete(File.join(@bin, 'curl'))
    _, exit_status = run_command
    assert_equal 1, exit_status
  end

  def test_unavailable_clt_requests_system_installation_then_stops_downstream
    remove_cli
    @environment['CODEGRAPH_TEST_CLT_EXIT'] = '23'
    output, exit_status = run_command
    assert_equal 1, exit_status
    assert_includes output, 'Command Line Tools 尚未就绪'
    assert_includes trace, 'xcode-select|--install'
    refute_match(/(?:brew|npm)\|/, trace)
    refute File.exist?(File.join(@project, '.codegraph'))
  end

  def test_missing_xcrun_and_broken_clang_do_not_reach_brew
    remove_cli
    @environment['CODEGRAPH_TEST_CLANG_EXIT'] = '24'
    _, exit_status = run_command
    assert_equal 1, exit_status
    refute_match(/(?:brew|npm)\|/, trace)
    File.delete(File.join(@bin, 'xcrun'))
    output, exit_status = run_command
    assert_equal 1, exit_status
    assert_includes output, '缺少 xcode-select/xcrun'
  end

  def test_broken_brew_configuration_stops_before_node_or_cli_installation
    remove_cli
    @environment['CODEGRAPH_TEST_BREW_CONFIG_EXIT'] = '25'
    output, exit_status = run_command
    assert_equal 1, exit_status
    assert_includes output, 'Homebrew 当前进程环境激活失败'
    refute_match(/npm\||brew\|(?:install|reinstall)/, trace)
  end

  def test_brew_doctor_warning_does_not_reinstall_a_healthy_package_manager
    remove_cli
    @environment['CODEGRAPH_TEST_BREW_DOCTOR_EXIT'] = '25'
    output, exit_status = run_command
    assert_equal 0, exit_status, output
    assert_includes output, 'Homebrew doctor'
    refute_match(/brew\|(?:install|reinstall|update|upgrade)/, trace)
    assert_profiles_preserved
  end

  def test_failed_brew_installation_stops_without_switching_locations
    remove_cli
    remove_brew
    @environment['CODEGRAPH_TEST_INSTALLER_EXIT'] = '26'
    output, exit_status = run_command(input: "\n\nYES\n")
    assert_equal 1, exit_status
    assert_includes output, '系统目录 Homebrew 安装失败'
    assert_equal 1, trace.scan('installer|system').length
    refute_includes trace, 'https://api.github.com/repos/Homebrew/brew/releases/latest'
    refute_includes trace, 'npm|'
    assert_profiles_preserved
  end

  def test_brew_installation_success_without_healthy_result_stops
    remove_cli
    remove_brew
    @environment['CODEGRAPH_TEST_INSTALLER_SKIP_BREW'] = '1'
    output, exit_status = run_command(input: "\n\nYES\n")
    assert_equal 1, exit_status
    assert_includes output, '未找到健康 Homebrew'
    refute_includes trace, 'npm|'
  end

  def test_failed_node_installation_does_not_install_cli_or_retry
    remove_cli
    remove_node_npm
    @environment['CODEGRAPH_TEST_NODE_INSTALL_EXIT'] = '27'
    output, exit_status = run_command
    assert_equal 1, exit_status
    assert_includes output, 'Homebrew Node.js 安装或修复失败'
    assert_equal 1, trace.scan('brew|install node@24').length
    refute_includes trace, 'npm|install --global'
  end

  def test_node_installation_success_with_broken_result_stops_after_one_attempt
    remove_cli
    remove_node_npm
    @environment['CODEGRAPH_TEST_NODE_AFTER_INSTALL_EXIT'] = '28'
    output, exit_status = run_command
    assert_equal 1, exit_status
    assert_includes output, 'Node/npm 安装后复检失败'
    assert_equal 1, trace.scan('brew|install node@24').length
    refute_includes trace, 'npm|install --global'
  end

  def test_registry_failure_does_not_install_cli_or_build_map
    remove_cli
    @environment['CODEGRAPH_TEST_NPM_PING_EXIT'] = '29'
    output, exit_status = run_command
    assert_equal 1, exit_status
    assert_includes output, 'npm 官方 Registry 不可用'
    refute_includes trace, 'npm|install --global'
    refute File.exist?(File.join(@project, '.codegraph'))
  end

  def test_failed_cli_installation_does_not_build_map_or_retry
    remove_cli
    @environment['CODEGRAPH_TEST_NPM_INSTALL_EXIT'] = '30'
    output, exit_status = run_command
    assert_equal 1, exit_status
    assert_includes output, 'CodeGraph 官方 npm 包安装失败'
    assert_equal 1, trace.scan('npm|install --global').length
    refute File.exist?(File.join(@project, '.codegraph'))
  end

  def test_cli_installation_success_with_broken_result_stops_before_map
    remove_cli
    @environment['CODEGRAPH_TEST_INSTALLED_VERSION_EXIT'] = '31'
    output, exit_status = run_command
    assert_equal 1, exit_status
    assert_includes output, 'CodeGraph 安装后版本或 CLI 接口复检失败'
    assert_equal 1, trace.scan('npm|install --global').length
    refute File.exist?(File.join(@project, '.codegraph'))
  end

  def test_map_command_and_status_failures_preserve_the_external_exit_code
    @environment['CODEGRAPH_TEST_MAP_EXIT'] = '41'
    output, exit_status = run_command(input: "\n")
    assert_equal 41, exit_status
    assert_includes output, '代码地图命令执行失败'
    refute_includes output, '✔ 代码地图更新完成'
    @environment.delete('CODEGRAPH_TEST_MAP_EXIT')
    @environment['CODEGRAPH_TEST_STATUS_EXIT'] = '42'
    output, exit_status = run_command(input: "\n")
    assert_equal 42, exit_status
    assert_includes output, 'CodeGraph 状态读取失败'
  end

  def test_existing_map_belonging_to_another_project_is_not_synced
    create_graph_database(@project)
    @environment['CODEGRAPH_TEST_STATUS_MODE'] = 'other-project'
    output, exit_status = run_command(input: "\n")
    assert_equal 1, exit_status
    assert_includes output, '地图项目身份或输出位置不匹配'
    refute_includes trace, "codegraph|sync #{@project}"
    refute_includes trace, 'codegraph|init --yes'
  end

  def test_invalid_or_incomplete_status_is_not_reported_as_success
    %w[invalid incomplete missing-time other-index pending pending-modified pending-removed refs-pending missing-count missing-added missing-modified missing-removed optional-pending optional-parse-errors].each do |mode|
      @environment['CODEGRAPH_TEST_STATUS_MODE'] = mode
      output, exit_status = run_command(input: "\n")
      assert_equal 1, exit_status, "#{mode}: #{output}"
      refute_includes output, '✔ 代码地图更新完成'
      FileUtils.remove_entry(File.join(@project, '.codegraph')) if File.directory?(File.join(@project, '.codegraph'))
    end
  end

  def test_published_1_6_2_status_and_optional_new_fields_are_both_supported
    %w[published-1.6.2 with-optional].each do |mode|
      @environment['CODEGRAPH_TEST_STATUS_MODE'] = mode
      output, exit_status = run_command(input: "\n")
      assert_equal 0, exit_status, "#{mode}: #{output}"
      assert_includes output, '✔ 代码地图更新完成'
      FileUtils.remove_entry(File.join(@project, '.codegraph'))
    end
  end

  def test_map_directory_without_database_is_initialized_without_deleting_other_content
    FileUtils.mkdir_p(File.join(@project, '.codegraph'))
    sentinel = File.join(@project, '.codegraph/config.json')
    File.write(sentinel, 'keep configuration')
    output, exit_status = run_command(input: "\n")
    assert_equal 0, exit_status, output
    assert_includes trace, "codegraph|init --yes #{@project}"
    refute_includes trace, "codegraph|sync #{@project}"
    assert_equal 'keep configuration', File.read(sentinel)
  end

  def test_symlink_or_regular_file_map_is_rejected_without_running_cli
    other = File.join(@root, 'other-project')
    FileUtils.mkdir_p(other)
    map = File.join(@project, '.codegraph')
    File.symlink(other, map)
    output, exit_status = run_command(input: "\n")
    assert_equal 1, exit_status
    assert_includes output, '符号链接'
    assert_empty trace
    assert_empty Dir.children(other)
    File.delete(map)
    File.write(map, 'keep file')
    _, exit_status = run_command(input: "\n")
    assert_equal 1, exit_status
    assert_equal 'keep file', File.read(map)
    assert_empty trace
  end

  def test_database_or_sidecar_symlinks_cannot_redirect_writes_to_another_project
    FileUtils.mkdir_p(File.join(@project, '.codegraph'))
    other_database = File.join(@root, 'another-project.db')
    File.write(other_database, 'untouched database')
    %w[codegraph.db codegraph.db-wal codegraph.db-shm].each do |name|
      link = File.join(@project, '.codegraph', name)
      File.symlink(other_database, link)
      output, exit_status = run_command(input: "\n")
      assert_equal 1, exit_status, output
      assert_includes output, '符号链接'
      assert_empty trace
      assert_equal 'untouched database', File.read(other_database)
      File.delete(link)
    end
  end

  def test_invalid_or_incomplete_database_stops_before_status_can_fall_back_to_parent
    create_graph_database(@root)
    parent_database = File.join(@root, '.codegraph/codegraph.db')
    parent_contents = File.binread(parent_database)
    FileUtils.mkdir_p(File.join(@project, '.codegraph'))
    database = File.join(@project, '.codegraph/codegraph.db')
    [:empty, :corrupt, :missing_nodes].each do |kind|
      File.delete(database) if File.exist?(database)
      case kind
      when :empty then File.write(database, '')
      when :corrupt then File.write(database, 'not a SQLite database')
      when :missing_nodes then create_graph_database(@project, schema: 'CREATE TABLE another_table (id TEXT);')
      end
      target_contents = File.binread(database)
      output, exit_status = run_command(input: "\n")
      assert_equal 1, exit_status, "#{kind}: #{output}"
      refute_includes trace, 'codegraph|status --json'
      refute_includes trace, "codegraph|sync #{@project}"
      refute_includes trace, "codegraph|init --yes #{@project}"
      assert_equal target_contents, File.binread(database)
      assert_equal parent_contents, File.binread(parent_database)
    end
  end

  def test_successful_map_command_without_local_schema_does_not_read_status_or_claim_success
    @environment['CODEGRAPH_TEST_SKIP_DATABASE'] = '1'
    output, exit_status = run_command(input: "\n")
    assert_equal 1, exit_status, output
    refute_includes trace, 'codegraph|status --json'
    refute_includes output, '✔ 代码地图更新完成'
  end

  def test_sqlite_health_and_schema_checks_do_not_load_user_sqliterc
    poison_marker = File.join(@root, 'sqliterc-was-read')
    File.write(File.join(@root, '.sqliterc'), ".shell /usr/bin/touch #{poison_marker}\n")
    create_graph_database(@project)
    output, exit_status = run_command(input: "\n")
    assert_equal 0, exit_status, output
    refute File.exist?(poison_marker)
  end

  private

  def trace
    File.file?(@trace) ? File.read(@trace) : ''
  end

  def log_files
    Dir[File.join(@logs, 'JobsTerminalOpener-CodeGraph.*')]
  end

  def assert_profiles_preserved
    assert_equal "# keep zprofile\n", File.read(File.join(@root, '.zprofile'))
    assert_equal "# keep bash profile\n", File.read(File.join(@root, '.bash_profile'))
  end

  def remove_cli
    File.delete(File.join(@bin, 'codegraph'))
  end

  def remove_brew
    File.delete(File.join(@bin, 'brew'))
    @environment.delete('JOBS_HOMEBREW_BIN')
  end

  def remove_node_npm
    %w[node npm].each { |name| File.delete(File.join(@bin, name)) }
  end

  def create_graph_database(project, schema: 'CREATE TABLE nodes (id TEXT PRIMARY KEY);')
    directory = File.join(project, '.codegraph')
    FileUtils.mkdir_p(directory)
    output, status = Open3.capture2e('/usr/bin/sqlite3', '-batch', '-init', '/dev/null',
                                     File.join(directory, 'codegraph.db'), schema)
    raise "SQLite 夹具创建失败：#{output}" unless status.success?
  end

  def write_mock(name, body)
    script = "#!/bin/sh\nprintf '#{name}|%s\\n' \"$*\" >> \"$CODEGRAPH_TEST_TRACE\"\n#{body}\n"
    [File.join(@bin, name), File.join(@templates, name)].each do |path|
      File.delete(path) if File.symlink?(path)
      File.write(path, script)
      File.chmod(0o700, path)
    end
  end

  def run_command(input: "\n\n", before_input: nil)
    output = +''
    exit_status = nil
    Timeout.timeout(12) do
      PTY.spawn(@environment, '/bin/zsh', '-f', @script, @project, unsetenv_others: true) do |reader, writer, process_id|
        if before_input
          output << reader.readpartial(4096) until output.b.include?('👉 已了解用途与影响'.b)
          before_input.call
        end
        writer.write(input)
        begin
          loop { output << reader.readpartial(4096) }
        rescue EOFError, Errno::EIO
          _, status = Process.wait2(process_id)
          exit_status = status.exitstatus || 128 + status.termsig
        end
      end
    end
    [output.force_encoding(Encoding::UTF_8), exit_status]
  end

  def codegraph_mock
    <<~'SH'
      if [ "$1" = --version ]; then
        if [ "$0" = "$CODEGRAPH_TEST_INITIAL_CLI" ]; then
          [ "${CODEGRAPH_TEST_INITIAL_VERSION_EXIT:-0}" = 0 ] || exit "$CODEGRAPH_TEST_INITIAL_VERSION_EXIT"
        else
          [ "${CODEGRAPH_TEST_INSTALLED_VERSION_EXIT:-0}" = 0 ] || exit "$CODEGRAPH_TEST_INSTALLED_VERSION_EXIT"
        fi
        printf '1.6.2\n'
        exit 0
      fi
      if [ "${2:-}" = --help ]; then
        [ "$0" != "$CODEGRAPH_TEST_INITIAL_CLI" ] || exit "${CODEGRAPH_TEST_INITIAL_HELP_EXIT:-0}"
        exit 0
      fi
      printf 'map-bin|%s\n' "$0" >> "$CODEGRAPH_TEST_TRACE"
      printf 'map-env|watch=%s;download=%s;telemetry=%s;track=%s;dir=%s\n' "$CODEGRAPH_NO_WATCH" "$CODEGRAPH_NO_DOWNLOAD" "$CODEGRAPH_TELEMETRY" "$DO_NOT_TRACK" "$CODEGRAPH_DIR" >> "$CODEGRAPH_TEST_TRACE"
      command="$1"
      shift
      target=''
      for argument in "$@"; do
        case "$argument" in --*) ;; *) target="$argument" ;; esac
      done
      [ "$target" = "$CODEGRAPH_TEST_PROJECT" ] || exit 95
      case "$command" in
        init|sync)
          [ "${CODEGRAPH_TEST_MAP_EXIT:-0}" = 0 ] || exit "$CODEGRAPH_TEST_MAP_EXIT"
          /bin/mkdir -p "$target/.codegraph"
          if [ "${CODEGRAPH_TEST_SKIP_DATABASE:-0}" != 1 ]; then
            /usr/bin/sqlite3 -batch -init /dev/null "$target/.codegraph/codegraph.db" 'CREATE TABLE IF NOT EXISTS nodes (id TEXT PRIMARY KEY);' || exit 105
          fi
          printf 'mock index\n' > "$target/.codegraph/mock-index"
          printf 'mock codegraph %s\n' "$command"
          ;;
        status)
          [ "${CODEGRAPH_TEST_STATUS_EXIT:-0}" = 0 ] || exit "$CODEGRAPH_TEST_STATUS_EXIT"
          project="$CODEGRAPH_TEST_PROJECT_JSON"
          index="$CODEGRAPH_TEST_INDEX_JSON"
          state=complete
          time='"lastIndexed":"2026-10-18T12:00:00.000Z",'
          count=0
          counts='"pendingRefs":0,'
          pending='"added":0,"modified":0,"removed":0'
          case "${CODEGRAPH_TEST_STATUS_MODE:-}" in
            invalid) printf 'invalid JSON\n'; exit 0 ;;
            incomplete) state=building ;;
            missing-time) time='' ;;
            other-project) project='"/another/project"' ;;
            other-index) index='"/another/.codegraph"' ;;
            pending) count=1 ;;
            pending-modified) pending='"added":0,"modified":1,"removed":0' ;;
            pending-removed) pending='"added":0,"modified":0,"removed":1' ;;
            refs-pending) counts='"pendingRefs":1,' ;;
            missing-count) counts='' ;;
            missing-added) pending='"modified":0,"removed":0' ;;
            missing-modified) pending='"added":0,"removed":0' ;;
            missing-removed) pending='"added":0,"modified":0' ;;
            with-optional) counts='"pendingRefs":0,"filesNeedingReindex":0,"filesWithParseErrors":0,' ;;
            optional-pending) counts='"pendingRefs":0,"filesNeedingReindex":1,"filesWithParseErrors":0,' ;;
            optional-parse-errors) counts='"pendingRefs":0,"filesNeedingReindex":0,"filesWithParseErrors":1,' ;;
          esac
          if [ "$count" != 0 ]; then pending='"added":1,"modified":0,"removed":0'; fi
          printf '{"initialized":true,"projectPath":%s,"indexPath":%s,%s"pendingChanges":{%s},"index":{%s"state":"%s"}}\n' "$project" "$index" "$time" "$pending" "$counts" "$state"
          ;;
        *) exit 96 ;;
      esac
    SH
  end

  def node_mock
    <<~'SH'
      if [ -f "$CODEGRAPH_TEST_ROOT/node-repaired" ]; then
        exit "${CODEGRAPH_TEST_NODE_AFTER_INSTALL_EXIT:-0}"
      fi
      exit "${CODEGRAPH_TEST_NODE_EXIT:-0}"
    SH
  end

  def npm_mock
    <<~'SH'
      case "$1" in
        --version)
          [ ! -f "$CODEGRAPH_TEST_ROOT/node-repaired" ] || [ "${CODEGRAPH_TEST_REPAIR_RESETS_NPM:-0}" != 1 ] || exit 0
          exit "${CODEGRAPH_TEST_NPM_VERSION_EXIT:-0}"
          ;;
        config|root) printf '%s/npm-prefix\n' "$CODEGRAPH_TEST_ROOT" ;;
        ping) exit "${CODEGRAPH_TEST_NPM_PING_EXIT:-0}" ;;
        install)
          [ "${CODEGRAPH_TEST_NPM_INSTALL_EXIT:-0}" = 0 ] || exit "$CODEGRAPH_TEST_NPM_INSTALL_EXIT"
          prefix=''
          while [ "$#" -gt 0 ]; do
            if [ "$1" = --prefix ]; then shift; prefix="$1"; fi
            shift
          done
          [ "$prefix" = "$CODEGRAPH_TEST_ROOT/.local/share/jobs-codegraph" ] || exit 97
          /bin/mkdir -p "$prefix/bin"
          /bin/cp "$CODEGRAPH_TEST_TEMPLATES/codegraph" "$prefix/bin/codegraph"
          printf 'mock npm install\n'
          ;;
        *) exit 98 ;;
      esac
    SH
  end

  def brew_mock
    <<~'SH'
      prefix="$CODEGRAPH_TEST_BREW_PREFIX"
      case "$1" in
        --version) printf 'Homebrew 4.6.0\n'; exit "${CODEGRAPH_TEST_BREW_VERSION_EXIT:-0}" ;;
        --prefix)
          if [ "$#" = 1 ]; then
            printf '%s\n' "$prefix"
          elif [ -d "$prefix/opt/$2" ]; then
            printf '%s/opt/%s\n' "$prefix" "$2"
          else
            exit 1
          fi
          ;;
        config) exit "${CODEGRAPH_TEST_BREW_CONFIG_EXIT:-0}" ;;
        doctor) exit "${CODEGRAPH_TEST_BREW_DOCTOR_EXIT:-0}" ;;
        shellenv) printf 'export PATH="%s/bin:$PATH"\n' "$prefix" ;;
        list) [ -f "$prefix/node-registered" ] || exit 1 ;;
        install|reinstall)
          [ "$2" = node@24 ] || exit 99
          [ "${CODEGRAPH_TEST_NODE_INSTALL_EXIT:-0}" = 0 ] || exit "$CODEGRAPH_TEST_NODE_INSTALL_EXIT"
          /bin/mkdir -p "$prefix/opt/node@24/bin"
          /bin/cp "$CODEGRAPH_TEST_TEMPLATES/node" "$prefix/opt/node@24/bin/node"
          /bin/cp "$CODEGRAPH_TEST_TEMPLATES/npm" "$prefix/opt/node@24/bin/npm"
          printf 'repaired\n' > "$CODEGRAPH_TEST_ROOT/node-repaired"
          ;;
        *) exit 100 ;;
      esac
    SH
  end

  def curl_mock
    <<~'SH'
      if [ "$1" = --version ]; then exit "${CODEGRAPH_TEST_CURL_EXIT:-0}"; fi
      destination=''
      for argument in "$@"; do
        if [ "$previous" = -o ]; then destination="$argument"; fi
        previous="$argument"
      done
      case "$destination" in "$CODEGRAPH_TEST_ROOT"/*) ;; *) exit 101 ;; esac
      case "$*" in
        *api.github.com*) printf '{"tag_name":"4.6.0"}\n' > "$destination" ;;
        *raw.githubusercontent.com*)
          /bin/cat > "$destination" <<'INSTALLER'
      printf 'installer|system\n' >> "$CODEGRAPH_TEST_TRACE"
      [ "${CODEGRAPH_TEST_INSTALLER_EXIT:-0}" = 0 ] || exit "$CODEGRAPH_TEST_INSTALLER_EXIT"
      [ "${CODEGRAPH_TEST_INSTALLER_SKIP_BREW:-0}" != 1 ] || exit 0
      case "$CODEGRAPH_TEST_SYSTEM_PREFIX" in "$CODEGRAPH_TEST_ROOT"/*) ;; *) exit 102 ;; esac
      /bin/mkdir -p "$CODEGRAPH_TEST_SYSTEM_PREFIX/bin"
      /bin/cp "$CODEGRAPH_TEST_TEMPLATES/brew" "$CODEGRAPH_TEST_SYSTEM_PREFIX/bin/brew"
      INSTALLER
          ;;
        *) exit 103 ;;
      esac
    SH
  end

  def git_mock
    <<~'SH'
      if [ "$1" = --version ]; then exit "${CODEGRAPH_TEST_GIT_EXIT:-0}"; fi
      case "$*" in
        *clone*)
          for argument in "$@"; do destination="$argument"; done
          case "$destination" in "$CODEGRAPH_TEST_ROOT"/*) ;; *) exit 104 ;; esac
          /bin/mkdir -p "$destination/bin"
          /bin/cp "$CODEGRAPH_TEST_TEMPLATES/brew" "$destination/bin/brew"
          ;;
        *) exit 0 ;;
      esac
    SH
  end
end
