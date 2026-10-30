# frozen_string_literal: true
# 验证真实分发器的 SDK / Java 门禁和退出码；所有 worker 在临时目录替换，不执行安装。
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'

class VersionManagerDispatchTests < Minitest::Test
  def setup
    @root = File.realpath(Dir.mktmpdir('jobs-version-dispatch-'))
    @tools = File.join(@root, 'tools')
    @project = File.join(@root, "项目 ' $(touch NEVER) ; space")
    @trace = File.join(@root, 'trace')
    FileUtils.mkdir_p([@tools, File.join(@project, 'lib')])
    File.write(File.join(@project, 'pubspec.yaml'), "name: fixture\ndependencies:\n  flutter:\n    sdk: flutter\n")
    FileUtils.cp(File.expand_path('../Scripts/Tools/DispatchFlutterTools.zsh', __dir__), @tools)
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def write_worker(name, body)
    File.write(File.join(@tools, name), "#!/bin/zsh\n#{body}\n")
  end

  def dispatch(action)
    Open3.capture3({ 'JOBS_DISPATCH_TRACE' => @trace }, '/bin/zsh', File.join(@tools, 'DispatchFlutterTools.zsh'), action, @project)
  end

  def prepare_fvm
    File.write(File.join(@project, '.fvmrc'), '{"flutter":"fixture"}')
    %w[bin/flutter bin/cache/dart-sdk/bin/dart].each do |relative|
      path = File.join(@project, '.fvm/flutter_sdk', relative)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "#!/bin/zsh\nexit 97\n")
      FileUtils.chmod(0o755, path)
    end
  end

  def test_new_managers_run_without_fvm_and_with_unresolved_java_declaration
    File.write(File.join(@project, '.java-version'), 'unresolved-fixture')
    { 'ohos-sdk-manage' => 'ManageHarmonyFlutterVersion.zsh', 'java-manage' => 'ManageProjectJava.zsh' }.each do |action, worker|
      write_worker(worker, 'printf "%s\0" "$@" > "$JOBS_DISPATCH_TRACE"; exit 19')
      output, error, status = dispatch(action)
      assert_equal 19, status.exitstatus, output + error
      assert_equal ['--project', @project], File.binread(@trace).force_encoding('UTF-8').split("\0")
      refute File.exist?(File.join(@root, 'NEVER'))
    end
  end

  def test_java_binding_failure_stops_worker
    prepare_fvm
    File.write(File.join(@project, '.java-version'), '17')
    write_worker('ManageProjectJava.zsh', 'pj_bind_project_java() { return 23; }')
    write_worker('PackageFlutter.zsh', 'touch "$JOBS_DISPATCH_TRACE"')
    output, error, status = dispatch('package-android')
    assert_equal 23, status.exitstatus, output + error
    refute File.exist?(@trace)
  end

  def test_project_java_reaches_package_and_runner_workers
    prepare_fvm
    File.write(File.join(@project, '.java-version'), '17')
    write_worker('ManageProjectJava.zsh', <<~'SH')
      pj_bind_project_java() {
        export JAVA_HOME="$1/fixture-jdk"
        export GRADLE_OPTS='-Dorg.gradle.java.home="fixture-jdk"'
      }
    SH
    %w[PackageFlutter.zsh RunFlutterProject.zsh].each do |worker|
      write_worker(worker, 'printf "%s\0" "$JAVA_HOME" "$GRADLE_OPTS" > "$JOBS_DISPATCH_TRACE"; exit 21')
    end
    %w[package-android run].each do |action|
      output, error, status = dispatch(action)
      assert_equal 21, status.exitstatus, output + error
      assert_equal [File.join(@project, 'fixture-jdk'), '-Dorg.gradle.java.home="fixture-jdk"'], File.binread(@trace).force_encoding('UTF-8').split("\0")
    end
  end

  def test_projects_without_java_declaration_keep_old_worker_behavior
    prepare_fvm
    write_worker('PackageFlutter.zsh', 'printf "%s\0" "$@" > "$JOBS_DISPATCH_TRACE"; exit 29')
    output, error, status = dispatch('package-android')
    assert_equal 29, status.exitstatus, output + error
    assert_equal ['--project', @project, '--platform', 'android'], File.binread(@trace).force_encoding('UTF-8').split("\0")
  end

  def test_sdk_inspection_does_not_require_project_java
    prepare_fvm
    File.write(File.join(@project, '.java-version'), 'unresolved-fixture')
    write_worker('ManageProjectJava.zsh', 'pj_bind_project_java() { return 23; }')
    write_worker('InspectFlutterSdkVersion.zsh', 'printf "%s\0" "$@" > "$JOBS_DISPATCH_TRACE"; exit 31')
    output, error, status = dispatch('sdk-version')
    assert_equal 31, status.exitstatus, output + error
    assert_equal ['--project', @project], File.binread(@trace).force_encoding('UTF-8').split("\0")
  end

  def test_dependency_import_dispatch_preserves_path_and_worker_failure_without_binding_java
    prepare_fvm
    File.write(File.join(@project, '.java-version'), 'unresolved-fixture')
    write_worker('ManageProjectJava.zsh', 'pj_bind_project_java() { return 23; }')
    write_worker('ImportFlutterDependencies.zsh', 'printf "%s\0" "$@" > "$JOBS_DISPATCH_TRACE"; exit 37')
    output, error, status = dispatch('import-dependencies')
    assert_equal 37, status.exitstatus, output + error
    assert_equal [@project], File.binread(@trace).force_encoding('UTF-8').split("\0")
    refute File.exist?(File.join(@root, 'NEVER'))
  end

  def test_dependency_import_dispatches_a_flutter_root_without_lib
    prepare_fvm
    Dir.rmdir(File.join(@project, 'lib'))
    write_worker('ImportFlutterDependencies.zsh', 'printf "%s\0" "$@" > "$JOBS_DISPATCH_TRACE"; exit 37')
    output, error, status = dispatch('import-dependencies')
    assert_equal 37, status.exitstatus, output + error
    assert_equal [@project], File.binread(@trace).force_encoding('UTF-8').split("\0")
    refute File.exist?(File.join(@root, 'NEVER'))
  end

  def test_dependency_import_exception_does_not_expand_other_sdk_actions
    prepare_fvm
    Dir.rmdir(File.join(@project, 'lib'))
    write_worker('InspectFlutterSdkVersion.zsh', 'printf "%s\0" "$@" > "$JOBS_DISPATCH_TRACE"; exit 37')
    output, error, status = dispatch('sdk-version')
    assert_equal 1, status.exitstatus, output + error
    assert_includes error, '请选择 Flutter 项目根目录。'
    refute File.exist?(@trace)
  end
end
