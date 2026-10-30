# frozen_string_literal: true
# 复制真实启动器验证搬迁寻址；桌面选择、错误弹窗与 worker 全部由临时替身承接。
require 'minitest/autorun'
require 'open3'
require 'tmpdir'
require 'fileutils'
require 'shellwords'

class PortableLauncherTests < Minitest::Test
  ROOT = File.expand_path('..', __dir__)
  APPS = Dir.glob(File.join(ROOT, '**', '【MacOS】*Finder扩展.app')).freeze
  ROOT_APP = File.join(ROOT, '【MacOS】🧩管理Finder扩展.app')
  SINGLE_APP = APPS.find { |app| app.include?('/JobsFlutterTools/') }

  # 仅搭建 App、脚本替身和受控桌面替身，不复制业务实现。
  def package(directory, source_app: ROOT_APP, worker: :file)
    app = File.join(directory, File.basename(source_app))
    launcher = File.join(app, 'Contents/MacOS/LaunchManager')
    scripts = File.join(directory, 'Scripts')
    worker_name = source_app == ROOT_APP ? 'ManageFinderExtensions.zsh' : 'ManageExtension.zsh'
    manager = File.join(scripts, worker_name)
    FileUtils.mkdir_p([File.dirname(launcher), scripts])
    ui = <<~'ZSH'
      fixture_desktop() {
        if (( $# == 3 )); then
          print -u2 -r -- "CHOOSER=$3"
          [[ "${JOBS_TEST_PICK_STATUS:-0}" == 0 ]] || return 23
          print -r -- "${JOBS_TEST_PICK_DIRECTORY:-}"
        else
          print -u2 -r -- "DIALOG=$2"
        fi
      }
    ZSH
    source = File.read(File.join(source_app, 'Contents/MacOS/LaunchManager'))
    File.write(launcher, source.gsub('/usr/bin/osascript', 'fixture_desktop').sub(/\A(#![^\n]*\n)/) { "#{Regexp.last_match(1)}#{ui}" })
    File.chmod(0o755, launcher)
    if worker == :file
      File.write(manager, <<~'ZSH')
        #!/bin/zsh
        print -r -- invoked > "$JOBS_TEST_MARKER"
        printf '%s\0' "${0:A}" "$@"
      ZSH
    elsif worker == :directory
      FileUtils.mkdir_p(manager)
    end
    { app: app, launcher: launcher, manager: manager }
  end

  # 路径和参数直接交给进程，不通过 Shell 拼接。
  def launch(fixture, *arguments, env: {}, chdir: '/')
    Open3.capture3(env, '/bin/zsh', fixture.fetch(:launcher), *arguments, chdir: chdir)
  end

  def expected_worker_output(fixture, *arguments)
    [File.realpath(fixture.fetch(:manager)), '--gui-session', *arguments]
  end

  def test_every_package_works_after_copy_rename_and_unrelated_working_directory
    assert_equal 32, APPS.length
    Dir.mktmpdir('jobs-portable-') do |directory|
      APPS.each_with_index do |source_app, index|
        original = File.join(directory, "original-#{index}")
        fixture = package(original, source_app: source_app)
        moved = File.join(directory, "搬迁 #{index} 中文 [a]; & '$()`")
        FileUtils.mv(original, moved)
        fixture = fixture.transform_values { |path| path.sub(original, moved) }
        marker = File.join(directory, "worker-#{index}")
        scope = "menu 中文;$(touch injected) ' & `echo injected`"
        output, errors, result = launch(fixture, '--action', 'uninstall', '--scope', scope,
                                       env: { 'JOBS_TEST_MARKER' => marker })
        assert result.success?, "#{source_app}: #{errors}"
        assert_equal expected_worker_output(fixture, '--action', 'uninstall', '--scope', scope), output.split("\0"), source_app
        assert File.file?(marker), source_app
        assert_empty errors, source_app
        refute File.exist?(File.join(moved, 'injected'))
      end
    end
  end

  def test_runtime_package_root_works_when_every_app_is_detached_from_its_scripts
    Dir.mktmpdir('jobs-detached-') do |directory|
      APPS.each_with_index do |source_app, index|
        original_root = File.join(directory, "原目录 #{index}")
        original = package(original_root, source_app: source_app)
        detached = package(File.join(directory, "AppTranslocation-#{index}/d"), source_app: source_app, worker: :missing)
        marker = File.join(directory, "worker-#{index}")
        output, errors, result = launch(detached, '--package-root', original_root, '--action=install',
                                       env: { 'JOBS_TEST_MARKER' => marker })
        assert result.success?, "#{source_app}: #{errors}"
        assert_equal expected_worker_output(original, '--action', 'install'), output.split("\0"), source_app
        assert_empty errors, source_app
      end
    end
  end

  def test_command_passes_its_package_root_through_open_to_a_detached_app
    Dir.mktmpdir('jobs-command-path-') do |directory|
      [ROOT_APP, SINGLE_APP].each_with_index do |source_app, index|
        original_root = File.join(directory, "真实包 #{index}; '$()`")
        original = package(original_root, source_app: source_app)
        detached = package(File.join(directory, "isolated-#{index}"), source_app: source_app, worker: :missing)
        command = original.fetch(:app).sub(/\.app\z/, '.command')
        fake_open = File.join(original_root, 'open-stub')
        File.write(fake_open, <<~'ZSH')
          #!/bin/zsh
          [[ "$1" == -n && "$3" == --args ]] || exit 91
          shift 3
          exec /bin/zsh "$JOBS_TEST_DETACHED_LAUNCHER" "$@"
        ZSH
        File.chmod(0o755, fake_open)
        source = File.read(source_app.sub(/\.app\z/, '.command'))
        File.write(command, source.gsub('/usr/bin/open') { Shellwords.escape(fake_open) })
        marker = File.join(directory, "worker-#{index}")
        output, errors, result = Open3.capture3({ 'JOBS_TEST_MARKER' => marker,
                                                'JOBS_TEST_DETACHED_LAUNCHER' => detached.fetch(:launcher),
                                                'TERM_PROGRAM' => '' },
                                              '/bin/zsh', command, '--action', 'uninstall', chdir: '/')
        assert result.success?, errors
        assert_equal expected_worker_output(original, '--action', 'uninstall'), output.split("\0")
        assert_empty errors
      end
    end
  end

  def test_direct_app_accepts_a_user_selected_valid_package_for_root_and_single_feature
    Dir.mktmpdir('jobs-choose-package-') do |directory|
      [ROOT_APP, SINGLE_APP].each_with_index do |source_app, index|
        original_root = File.join(directory, "原始目录 #{index}")
        original = package(original_root, source_app: source_app)
        detached = package(File.join(directory, "detached-#{index}"), source_app: source_app, worker: :missing)
        marker = File.join(directory, "worker-#{index}")
        output, errors, result = launch(detached, '--action', 'uninstall',
                                       env: { 'JOBS_TEST_PICK_DIRECTORY' => original_root, 'JOBS_TEST_MARKER' => marker })
        assert result.success?, errors
        assert_equal expected_worker_output(original, '--action', 'uninstall'), output.split("\0")
        assert_includes errors, "CHOOSER=#{File.realpath(File.dirname(detached.fetch(:manager)))}/#{File.basename(detached.fetch(:manager))}"
        refute_includes errors, 'DIALOG='
      end
    end
  end

  def test_cancel_and_picker_failure_never_execute_a_worker
    Dir.mktmpdir('jobs-cancel-package-') do |directory|
      fixture = package(File.join(directory, 'detached'), worker: :missing)
      marker = File.join(directory, 'worker')
      [{ 'JOBS_TEST_PICK_DIRECTORY' => '' }, { 'JOBS_TEST_PICK_STATUS' => '23' }].each_with_index do |picker_env, index|
        output, errors, result = launch(fixture, env: picker_env.merge('JOBS_TEST_MARKER' => marker))
        assert_equal(index.zero? ? 130 : 2, result.exitstatus, errors)
        assert_empty output
        refute File.exist?(marker)
        refute_includes errors, 'DIALOG='
      end
    end
  end

  def test_wrong_package_and_a_directory_in_place_of_a_worker_are_rejected_with_actual_path
    Dir.mktmpdir('jobs-invalid-package-') do |directory|
      detached = package(File.join(directory, 'detached'), worker: :missing)
      wrong = package(File.join(directory, 'wrong-app'), source_app: SINGLE_APP)
      directory_worker = package(File.join(directory, 'directory-worker'), worker: :directory)
      marker = File.join(directory, 'worker')
      [wrong, directory_worker].each do |chosen|
        selected_root = File.dirname(chosen.fetch(:app))
        output, errors, result = launch(detached, env: { 'JOBS_TEST_PICK_DIRECTORY' => selected_root, 'JOBS_TEST_MARKER' => marker })
        assert_equal 2, result.exitstatus, errors
        assert_empty output
        assert_includes errors, '所选目录缺少同名 App 或可读的内部管理器。实际查找：'
        assert_includes errors, "#{File.realpath(selected_root)}/Scripts/ManageFinderExtensions.zsh"
        refute File.exist?(marker)
      end
    end
  end

  def test_diagnosis_reports_resolved_paths_without_ui_or_business_for_success_and_failure
    Dir.mktmpdir('jobs-diagnose-path-') do |directory|
      marker = File.join(directory, 'worker')
      [:file, :missing, :directory].each do |worker|
        fixture = package(File.join(directory, worker.to_s), worker: worker)
        output, errors, result = launch(fixture, '--diagnose-paths', env: { 'JOBS_TEST_MARKER' => marker })
        assert_equal(worker == :file ? 0 : 2, result.exitstatus, errors)
        assert_includes output, "App运行路径：#{File.realpath(fixture.fetch(:app))}"
        assert_includes output, "内部管理器：#{File.realpath(File.dirname(fixture.fetch(:manager)))}/#{File.basename(fixture.fetch(:manager))}"
        assert_includes output, worker == :file ? '路径校验：通过' : '路径校验：失败'
        assert_empty errors
        refute File.exist?(marker)
      end
    end
  end

  def test_all_shipping_launchers_have_no_developer_machine_path_fallback
    APPS.each do |app|
      [File.join(app, 'Contents/MacOS/LaunchManager'), app.sub(/\.app\z/, '.command')].each do |path|
        refute_match(%r{/Users/|/home/|file:///|[A-Za-z]:[\\/]}, File.read(path), path)
      end
    end
  end
end
