# frozen_string_literal: true
# Jobs：随包窗口分支不调用编译器；构建脚本只写临时Xcode产物。
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'json'

class SetupWindowLauncherTests < Minitest::Test
  ROOT = File.expand_path('..', __dir__)
  def test_prebuilt_window_launches_without_swift_source_or_compiler
    Dir.mktmpdir('jobs-setup-prebuilt-') do |directory|
      directory = File.realpath(directory)
      tools = File.join(directory, 'Tools')
      project = File.join(directory, "工程 ' $ literal")
      FileUtils.mkdir_p([File.join(tools, 'SetupGUIAssets'), project])
      launcher = File.join(tools, 'OpenSetupWindow.zsh')
      # The fixture makes accidental compiler lookup fail explicitly.
      source = File.read(File.join(ROOT, 'Scripts/Tools/OpenSetupWindow.zsh')).gsub('/usr/bin/xcrun', 'unavailable_fixture_compiler').gsub('/usr/bin/xcode-select', 'unavailable_fixture_clt')
      File.write(launcher, source)
      File.write(File.join(tools, 'SetupGUIAssets/terminal.html'), 'fixture')
      binary = File.join(tools, 'JobsFlutterSetup')
      File.write(binary, "#!/bin/zsh\n/usr/bin/printf '%s\\0' \"$@\" > \"$JOBS_TEST_SETUP_ARGS\"\nexit 19\n")
      FileUtils.chmod(0o755, binary)
      args = File.join(directory, 'args')
      out, err, status = Open3.capture3({'PATH'=>'/usr/bin:/bin', 'JOBS_TEST_SETUP_ARGS'=>args}, '/bin/zsh', '-f', launcher, '--project', project)
      assert_equal 19, status.exitstatus, out + err
      assert_equal ['--project', project, '--tools', tools], File.binread(args).force_encoding(Encoding::UTF_8).split("\0")
      refute_includes out + err, 'unavailable_fixture'
      refute File.exist?(File.join(tools, 'SetupProjectWindow.swift'))
    end
  end
  def test_build_phase_runs_after_resource_copy_before_extension_registration_and_does_not_change_skip_gate
    project = File.read(File.join(ROOT, 'JobsFlutterTools.xcodeproj/project.pbxproj'))
    host = project[/01D000000000000000000001 \/\* JobsFlutterTools \*\/ = \{.*?\n\t\t\};/m]
    assert_operator host.index('/* Resources */'), :<, host.index('/* Build Setup Window */')
    assert_operator host.index('/* Build Setup Window */'), :<, host.index('/* Enable Finder Extension */')
    assert_includes project, '$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/Tools/JobsFlutterSetup'
    registrar = File.read(File.join(ROOT, 'Scripts/EnableFinderExtension.zsh'))
    assert_includes registrar, 'JOBS_SKIP_FINDER_EXTENSION_BUILD_PHASE'
  end
  def test_real_build_helper_generates_executable_only_inside_fake_xcode_products
    Dir.mktmpdir('jobs-setup-build-') do |directory|
      directory = File.realpath(directory)
      src = File.join(directory, 'project')
      products = File.join(directory, 'products')
      resource = 'Fixture.app/Contents/Resources'
      FileUtils.mkdir_p([File.join(src, 'Scripts/Tools'), File.join(products, resource, 'Tools')])
      # Minimal Swift fixture checks real compiler/lipo/signing without launching GUI.
      File.write(File.join(src, 'Scripts/Tools/SetupProjectWindow.swift'), 'print("fixture window")')
      out, err, status = Open3.capture3({'SRCROOT'=>src, 'TARGET_BUILD_DIR'=>products, 'UNLOCALIZED_RESOURCES_FOLDER_PATH'=>resource, 'TEMP_DIR'=>directory,
        'ARCHS'=>'arm64 x86_64', 'MACOSX_DEPLOYMENT_TARGET'=>'12.0', 'EXPANDED_CODE_SIGN_IDENTITY'=>'-'}, '/bin/zsh', File.join(ROOT, 'Scripts/BuildSetupWindow.zsh'))
      assert status.success?, out + err
      binary = File.join(products, resource, 'Tools/JobsFlutterSetup')
      assert File.executable?(binary)
      refute File.exist?(File.join(src, 'Scripts/Tools/JobsFlutterSetup'))
      out, err, status = Open3.capture3('/usr/bin/lipo', '-archs', binary)
      assert status.success?, out + err
      assert_includes out, 'arm64'
      assert_includes out, 'x86_64'
    end
  end
end
