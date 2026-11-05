# frozen_string_literal: true
# 在加载真实定义前封住所有系统操作；业务子进程须由测试显式提供 recorder。
module IsolatedInstallerDefinitions
  def isolated_installer_source(path, replacements: {}, operation: :install)
    source = File.read(path)
    if source.include?('run_install_operation() {')
      source = source[/^run_#{operation}_operation\(\) \{\n\(\n(.*?)\n# 外层统一负责交互/m, 1]
      raise "缺少 #{operation} 定义：#{path}" unless source
    else
      raise "入口未找到：#{path}" unless source.sub!(/^main "\$@"\s*\z/, '')
    end
    # 动态 source 的新部署模块不能绕过原源码的系统命令封锁；部署边界另由专门临时夹具验证。
    source = source.gsub(/^load_deployment_support\(\) \{.*?^\}/m, "load_deployment_support() { return 0; }")
    source = source.gsub(/^manager_load_deployment\(\) \{.*?^\}/m, "manager_load_deployment() { return 0; }")
    source = source.gsub(/^cleanup_manager_control_directory\(\) \{.*?^\}/m, "cleanup_manager_control_directory() { return 0; }")
    replacements.each { |from, to| source = source.gsub(from, to) }
    # 必须覆盖整条可执行路径；按调用字符串替换无法拦住动态生成的管理器路径。
    %w[/bin/zsh /bin/rm /usr/bin/pluginkit /usr/bin/open /usr/bin/killall /usr/bin/pkill
       /bin/kill /usr/bin/xcode-select /usr/bin/xcodebuild /usr/bin/xcrun /usr/bin/codesign
       /bin/launchctl /bin/sleep /usr/bin/find].each do |command|
      source = source.gsub(command, 'jobs_forbidden_system_operation')
    end
    %w[mkdir chmod mv cp].each { |command| source = source.gsub("/bin/#{command}", "jobs_fixture_#{command}") }
    <<~'ZSH' + source
      manager_deploy_built_application() { return 0; }
      manager_commit_deployment() { return 0; }
      jobs_deployment_install() { return 0; }
      jobs_deployment_commit() { return 0; }
      jobs_deployment_rollback() { return 0; }
      jobs_deployment_retire_other_copies() { return 0; }
      jobs_deployment_has_other_enabled() { return 1; }
      jobs_deployment_app_path() { print -r -- "$1"; }
      jobs_deployment_validate_app() { jobs_forbidden_system_operation "$@"; }
      jobs_deployment_unregister_app() { jobs_forbidden_system_operation "$@"; }
      jobs_deployment_uninstall() { jobs_forbidden_system_operation "$@"; }
      jobs_forbidden_system_operation() {
        print -u2 -r -- "blocked unexpected system operation: ${(j:|:)@}"
        return 97
      }
      jobs_assert_fixture_paths() {
        local item=""
        for item in "$@"; do
          [[ "$item" == -* || "$item" == <-> ]] && continue
          item="${item:A}"
          [[ "$item" == "$JOBS_TEST_TEMP_ROOT"/* || "$item" == "$JOBS_TEST_TEMP_ROOT" ]] || {
            print -u2 -r -- "blocked non-fixture write: $item"
            return 97
          }
        done
      }
      jobs_fixture_mkdir() { jobs_assert_fixture_paths "$@" && /bin/mkdir "$@"; }
      jobs_fixture_chmod() { jobs_assert_fixture_paths "$@" && /bin/chmod "$@"; }
      jobs_fixture_mv() { jobs_assert_fixture_paths "$@" && /bin/mv "$@"; }
      jobs_fixture_cp() { jobs_assert_fixture_paths "$@" && /bin/cp "$@"; }
      zsh() { jobs_forbidden_system_operation "$@"; }
      pluginkit() { jobs_forbidden_system_operation "$@"; }
      xcodebuild() { jobs_forbidden_system_operation "$@"; }
      xcrun() { jobs_forbidden_system_operation "$@"; }
      codesign() { jobs_forbidden_system_operation "$@"; }
      rm() { jobs_forbidden_system_operation "$@"; }
      killall() { jobs_forbidden_system_operation "$@"; }
      pkill() { jobs_forbidden_system_operation "$@"; }
    ZSH
  end

  def isolated_installer_environment(directory)
    { 'NO_COLOR' => '1', 'HOME' => directory, 'TMPDIR' => "#{directory}/",
      'JOBS_TEST_TEMP_ROOT' => File.realpath(Dir.tmpdir) }
  end
end
