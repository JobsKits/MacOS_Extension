# frozen_string_literal: true
# Jobs：临时原生 CLI 代替面板，验证稳定 App 身份、标准签名和外置缓存，不打开 GUI 或更改授权。
require 'minitest/autorun'
require 'open3'
require 'tmpdir'
require 'fileutils'
require 'digest'

class GUIHostIdentityTests < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)
  HELPER = File.join(ROOT, 'Scripts/FinderManagerGUI.zsh')

  def fixture
    Dir.mktmpdir('jobs-gui-host-') do |directory|
      directory = File.realpath(directory)
      package = File.join(directory, 'package 中文')
      cache = File.join(directory, 'external cache')
      FileUtils.mkdir_p([File.join(package, 'Scripts'), cache])
      File.write(File.join(package, 'Scripts/SelectFinderExtensionFeatures.swift'), '// fixture source')
      entry = File.join(package, 'Scripts/ManageFinderExtensions.zsh')
      File.write(entry, '# never executed')
      binary = File.join(cache, 'SelectFinderExtensionFeatures')
      compile_native(directory, binary, 'original')
      File.utime(Time.now + 60, Time.now + 60, binary)
      yield directory, package, cache, entry, binary
    end
  end

  def compile_native(directory, binary, version)
    source = File.join(directory, 'main.swift')
    File.write(source, <<~SWIFT)
      import Foundation
      print("VERSION=#{version}")
      print("BUNDLE=\\(Bundle.main.bundleURL.path)")
      print("EXECUTABLE=\\(CommandLine.arguments[0])")
      print("RESPONSIBLE=\\(ProcessInfo.processInfo.environment["JOBS_FINDER_RESPONSIBLE_APP"] ?? "")")
      for argument in CommandLine.arguments.dropFirst() {
          print("ARG=\\(argument)")
      }
    SWIFT
    output, result = Open3.capture2e('/usr/bin/xcrun', 'swiftc', source, '-o', binary)
    assert result.success?, output
  end

  def launch(cache, entry)
    code = File.read(HELPER) + <<~'ZSH'
      jobs_manager_launch_error() { print -u2 -r -- "$1|${2:-}"; return 1; }
      jobs_launch_finder_manager_gui "$1" 'path_copier,file-create' uninstall 1
    ZSH
    Open3.capture3({ 'JOBS_FINDER_MANAGER_CACHE_DIR' => cache, 'JOBS_FINDER_INSTALL_LOCATION' => 'applications', 'JOBS_FINDER_CLEANUP_BUILD_PRODUCTS' => '0' }, '/bin/zsh', '-f', '-c', code, 'fixture', entry)
  end

  def test_native_host_has_stable_identity_standard_signature_and_reuses_identical_binary
    fixture do |_directory, package, cache, entry, binary|
      output, errors, result = launch(cache, entry)
      assert result.success?, output + errors
      app = File.join(cache, 'Jobs右键菜单管理面板.app')
      executable = File.join(app, 'Contents/MacOS/JobsFinderManager')
      assert_includes output, "BUNDLE=#{app}"
      assert_includes output, "EXECUTABLE=#{executable}"
      assert_includes output, "RESPONSIBLE=#{app}"
      assert_equal ['--manager', entry, '--action', 'uninstall', '--install-location', 'applications', '--scope', 'path_copier,file-create'], output.lines.grep(/^ARG=/).map { |line| line.chomp.delete_prefix('ARG=') }
      values = { 'CFBundleIdentifier' => 'com.jobs.finderextensions.managementpanel', 'CFBundleName' => 'Jobs右键菜单管理面板', 'CFBundleDisplayName' => 'Jobs右键菜单管理面板', 'CFBundleExecutable' => 'JobsFinderManager' }
      values.each do |key, value|
        actual, result = Open3.capture2e('/usr/libexec/PlistBuddy', '-c', "Print :#{key}", File.join(app, 'Contents/Info.plist'))
        assert result.success?, actual
        assert_equal value, actual.strip
      end
      actual, result = Open3.capture2e('/usr/bin/codesign', '--verify', '--deep', '--strict', app)
      assert result.success?, actual
      actual, result = Open3.capture2e('/usr/bin/codesign', '--display', '--verbose=4', app)
      assert result.success?, actual
      assert_includes actual, 'Signature=adhoc'
      assert_includes actual, 'Identifier=com.jobs.finderextensions.managementpanel'
      assert_equal Digest::SHA256.file(binary).hexdigest, File.read(File.join(app, 'Contents/Resources/BinarySource.sha256')).strip
      inode = File.stat(executable).ino
      modified = File.mtime(executable)
      output, errors, result = launch(cache, entry)
      assert result.success?, output + errors
      assert_equal inode, File.stat(executable).ino, 'unchanged native binary keeps the existing App'
      assert_equal modified, File.mtime(executable)
      refute File.exist?(File.join(package, 'work')), 'bundle source remains read only with an external cache'
      assert_empty Dir.glob(File.join(cache, '.JobsFinderManagerHost.*'))
    end
  end

  def test_signing_failure_preserves_previous_host_and_its_valid_signature
    fixture do |directory, _package, cache, entry, binary|
      _, errors, result = launch(cache, entry)
      assert result.success?, errors
      app = File.join(cache, 'Jobs右键菜单管理面板.app')
      executable = File.join(app, 'Contents/MacOS/JobsFinderManager')
      before = Digest::SHA256.file(executable).hexdigest
      inode = File.stat(executable).ino
      compile_native(directory, binary, 'changed')
      code = File.read(HELPER) + <<~'ZSH'
        jobs_manager_sign_gui_app() { print -u2 simulated-signing-failure; return 23; }
        jobs_manager_prepare_gui_app "$1" "$2"
      ZSH
      _, errors, result = Open3.capture3('/bin/zsh', '-f', '-c', code, 'fixture', binary, cache)
      assert_equal 23, result.exitstatus, errors
      assert_includes errors, 'simulated-signing-failure'
      assert_equal before, Digest::SHA256.file(executable).hexdigest
      assert_equal inode, File.stat(executable).ino
      actual, verified = Open3.capture2e('/usr/bin/codesign', '--verify', '--deep', '--strict', app)
      assert verified.success?, actual
      assert_empty Dir.glob(File.join(cache, '.JobsFinderManagerHost.*'))
    end
  end

  def test_foreign_same_named_app_is_not_overwritten
    fixture do |_directory, _package, cache, _entry, binary|
      app = File.join(cache, 'Jobs右键菜单管理面板.app')
      FileUtils.mkdir_p(File.join(app, 'Contents'))
      marker = File.join(app, 'Contents/Info.plist')
      File.write(marker, '<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>org.other.app</string></dict></plist>')
      before = File.binread(marker)
      code = File.read(HELPER) + "\njobs_manager_prepare_gui_app \"$1\" \"$2\"\n"
      _, errors, result = Open3.capture3('/bin/zsh', '-f', '-c', code, 'fixture', binary, cache)
      refute result.success?
      assert_includes errors, '拒绝覆盖非自有管理 App'
      assert_equal before, File.binread(marker)
    end
  end
end
