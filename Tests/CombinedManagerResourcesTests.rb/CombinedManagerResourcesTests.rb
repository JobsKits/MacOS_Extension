# frozen_string_literal: true
# Jobs：仅临时伪 App 与假 GUI 缓存，验证管理资源可脱离源码，不调用安装或登记。
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'

class CombinedManagerResourcesTests < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)
  LIBRARY = '【MacOS】联合App管理.zsh'
  DEPLOYMENT = '【MacOS】AppDeployment.zsh'
  PACKAGES = %w[JobsProjectTools JobsPathCopier JobsFileCreator JobsRunAuthorizer JobsRunAuthorizationRevoker JobsIPAResigner JobsDesktopTools JobsFlutterTools JobsTerminalOpener JobsIOSTools].freeze

  def fixture
    Dir.mktmpdir('jobs-combined-manager-') do |directory|
      directory = File.realpath(directory)
      source = File.join(directory, 'source 中文')
      FileUtils.mkdir_p(File.join(source, 'Scripts'))
      FileUtils.cp_r(File.join(ROOT, 'Scripts', LIBRARY), File.join(source, 'Scripts'))
      FileUtils.cp_r(File.join(ROOT, 'Scripts', DEPLOYMENT), File.join(source, 'Scripts'))
      File.write(File.join(source, 'Scripts/ManageFinderExtensions.zsh'), '# full source marker')
      PACKAGES.each { |name| prepare_package(File.join(source, name), name) }
      app = File.join(directory, 'Jobs自定义右键菜单.app')
      FileUtils.mkdir_p(File.join(app, 'Contents/Resources'))
      File.write(File.join(app, 'Contents/Info.plist'), '<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.jobs.finderextensions.manager</string></dict></plist>')
      yield directory, source, app
    end
  end

  def prepare_package(path, contents)
    FileUtils.mkdir_p(File.join(path, 'Scripts/Tools'))
    File.write(File.join(path, 'Scripts/ManageExtension.zsh'), "# #{contents}\n")
    File.write(File.join(path, 'Scripts/Tools/business.zsh'), 'must not be copied')
    FileUtils.cp_r(File.join(ROOT, 'Scripts', DEPLOYMENT), File.join(path, 'Scripts'))
    if File.basename(path) == 'JobsProjectTools'
      File.write(File.join(path, 'Scripts/ManageProjectTools.zsh'), '# project manager')
    elsif File.basename(path) == 'JobsDesktopTools'
      File.write(File.join(path, 'Scripts/ManageDesktopTools.zsh'), '# desktop manager')
    end
  end

  def prepare(source, app)
    library = File.join(source, 'Scripts', LIBRARY, LIBRARY)
    Open3.capture3('/bin/zsh', '-f', '-c', 'source "$1" && jobs_prepare_combined_manager_resources "$2"', 'fixture', library, app)
  end

  def test_full_source_copies_only_management_resources_and_snapshots
    fixture do |_directory, source, app|
      output, errors, status = prepare(source, app)
      assert status.success?, output + errors
      manager = File.join(app, 'Contents/Resources/ManagerRoot')
      assert_equal PACKAGES.sort, Dir.children(manager).grep(/^Jobs/).sort
      PACKAGES.each do |name|
        assert File.file?(File.join(manager, name, 'Scripts/ManageExtension.zsh'))
        refute File.exist?(File.join(manager, name, 'Scripts/Tools'))
      end
      %w[RootWorker PanelSource GuiBootstrap].zip(%w[ManageFinderExtensions.zsh SelectFinderExtensionFeatures.swift FinderManagerGUI.zsh]).each do |snapshot, name|
        assert_equal File.binread(File.join(source, 'Scripts', LIBRARY, 'Resources', "#{snapshot}.txt")), File.binread(File.join(manager, 'Scripts', name))
      end
      assert File.file?(File.join(manager, 'JobsProjectTools/Scripts/ManageProjectTools.zsh'))
      assert File.file?(File.join(manager, 'JobsDesktopTools/Scripts/ManageDesktopTools.zsh'))
    end
  end

  def test_entry_locates_resources_after_source_removal_and_uses_external_gui_cache
    fixture do |directory, source, app|
      output, errors, status = prepare(source, app)
      assert status.success?, output + errors
      resources = File.join(app, 'Contents/Resources')
      worker = File.join(resources, 'ManagerRoot/Scripts/ManageFinderExtensions.zsh')
      capture = File.join(directory, 'captured')
      home = File.join(directory, 'home')
      cache = File.join(home, 'Library/Caches/JobsFinderExtensions/Management')
      FileUtils.mkdir_p(cache)
      File.write(worker, <<~'ZSH')
        print -r -- "BUILT=${JOBS_FINDER_BUILT_APP_PATH-unset}" > "$CAPTURE"
        print -r -- "CACHE=$JOBS_FINDER_MANAGER_CACHE_DIR" >> "$CAPTURE"
        printf 'ENTRY:%s\n' "$@" >> "$CAPTURE"
        source "${0:A:h}/FinderManagerGUI.zsh"
        jobs_launch_finder_manager_gui "${0:A}" '' uninstall 1
      ZSH
      binary = File.join(cache, 'SelectFinderExtensionFeatures')
      File.write(binary, "#!/bin/zsh\nprintf 'GUI:%s\\n' \"$@\" >> \"$CAPTURE\"\n")
      File.chmod(0o755, binary)
      File.utime(Time.now + 60, Time.now + 60, binary)
      FileUtils.mv(source, source + '.unavailable')
      environment = { 'HOME' => home, 'CAPTURE' => capture, 'JOBS_FINDER_BUILT_APP_PATH' => '/developer/source/build/Old.app', 'JOBS_FINDER_CLEANUP_BUILD_PRODUCTS' => '1' }
      output, errors, status = Open3.capture3(environment, '/bin/zsh', File.join(resources, 'ManageInstalledExtensions.zsh'))
      assert status.success?, output + errors
      contents = File.read(capture)
      assert_includes contents, 'BUILT=unset'
      assert_includes contents, "CACHE=#{cache}"
      assert_includes contents, "ENTRY:--action\nENTRY:uninstall\nENTRY:--install-location\nENTRY:applications\nENTRY:--gui-session"
      snapshot_worker = contents[/GUI:--manager\nGUI:([^\n]+)/, 1]
      refute_nil snapshot_worker
      assert_match(%r{/JobsFinderManagerSession\.[^/]+/ManagerRoot/Scripts/ManageFinderExtensions\.zsh\z}, snapshot_worker)
      refute_equal worker, snapshot_worker
      refute File.exist?(File.expand_path('../..', snapshot_worker)), 'completed GUI releases its private snapshot'
      assert_includes contents, "GUI:--action\nGUI:uninstall\nGUI:--install-location\nGUI:applications"
      refute_includes contents, '--cleanup-build-products'
      refute File.exist?(File.join(resources, 'ManagerRoot/work'))
      refute_includes contents, '/developer/source'
    end
  end

  def test_running_session_survives_container_removal_and_releases_only_its_snapshot
    fixture do |directory, source, app|
      _, errors, status = prepare(source, app)
      assert status.success?, errors
      resources = File.join(app, 'Contents/Resources')
      worker = File.join(resources, 'ManagerRoot/Scripts/ManageFinderExtensions.zsh')
      capture = File.join(directory, 'session-root')
      release = File.join(directory, 'continue')
      completed = File.join(directory, 'completed')
      session_root = File.join(directory, 'private-sessions')
      FileUtils.mkdir_p(session_root)
      sentinel = File.join(session_root, 'unrelated')
      File.write(sentinel, 'preserved')
      File.write(worker, <<~'ZSH')
        print -r -- "${0:A:h:h}" > "$CAPTURE"
        local_attempt=0
        until [[ -f "$RELEASE" ]]; do
          (( local_attempt += 1 ))
          (( local_attempt < 200 )) || exit 90
          /bin/sleep 0.02
        done
        entries=("${0:A:h:h}"/Jobs*/Scripts/ManageExtension.zsh(N))
        (( ${#entries} == 10 )) || exit 91
        for entry in "${entries[@]}"; do
          [[ -f "$entry" && -r "$entry" ]] || exit 92
        done
        [[ -r "${0:A:h}/SelectFinderExtensionFeatures.swift" && -r "${0:A:h}/FinderManagerGUI.zsh" ]] || exit 93
        print -r -- 'all ten management units remained readable' > "$COMPLETED"
        exit "${FINAL_STATUS:-0}"
      ZSH
      environment = { 'HOME' => directory, 'TMPDIR' => session_root, 'CAPTURE' => capture, 'RELEASE' => release, 'COMPLETED' => completed }
      Open3.popen3(environment, '/bin/zsh', File.join(resources, 'ManageInstalledExtensions.zsh')) do |input, output, error, waiter|
        input.close
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
        sleep 0.01 until File.file?(capture) || Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        assert File.file?(capture), 'session starts from a complete private snapshot'
        snapshot_manager = File.read(capture).strip
        snapshot = File.dirname(snapshot_manager)
        assert File.directory?(snapshot)
        assert snapshot.start_with?(session_root + '/JobsFinderManagerSession.')
        assert waiter.alive?, 'entry waits for the GUI and worker lifetime'
        FileUtils.remove_entry(app)
        refute File.exist?(app)
        File.write(release, 'continue')
        result = waiter.value
        assert result.success?, output.read + error.read
        assert_equal 'all ten management units remained readable', File.read(completed).strip
        refute File.exist?(snapshot), 'normal completion removes its private snapshot'
        assert_equal 'preserved', File.read(sentinel)
        assert_empty Dir.glob(File.join(session_root, 'JobsFinderManagerSession.*'))
      end
    end
  end

  def test_independent_package_merges_without_losing_other_installed_managers
    fixture do |directory, source, app|
      _, errors, status = prepare(source, app)
      assert status.success?, errors
      independent = File.join(directory, 'JobsFileCreator')
      prepare_package(independent, 'updated independent copy')
      FileUtils.cp_r(File.join(ROOT, 'Scripts', LIBRARY), File.join(independent, 'Scripts'))
      output, errors, status = prepare(independent, app)
      assert status.success?, output + errors
      manager = File.join(app, 'Contents/Resources/ManagerRoot')
      assert_equal PACKAGES.sort, Dir.children(manager).grep(/^Jobs/).sort
      assert_equal "# updated independent copy\n", File.read(File.join(manager, 'JobsFileCreator/Scripts/ManageExtension.zsh'))
      assert_equal "# JobsPathCopier\n", File.read(File.join(manager, 'JobsPathCopier/Scripts/ManageExtension.zsh'))
      assert File.file?(File.join(manager, 'Scripts', DEPLOYMENT, DEPLOYMENT))
      refute File.exist?(File.join(manager, 'Scripts', DEPLOYMENT, DEPLOYMENT, DEPLOYMENT))
    end
  end

  def test_foreign_container_and_linked_resources_are_rejected
    fixture do |directory, source, app|
      plist = File.join(app, 'Contents/Info.plist')
      File.write(plist, '<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>org.foreign.app</string></dict></plist>')
      _, _, status = prepare(source, app)
      refute status.success?
      refute File.exist?(File.join(app, 'Contents/Resources/ManagerRoot'))
      File.write(plist, '<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.jobs.finderextensions.manager</string></dict></plist>')
      external = File.join(directory, 'external')
      FileUtils.mkdir_p(external)
      File.write(File.join(external, 'sentinel'), 'preserved')
      File.symlink(external, File.join(app, 'Contents/Resources/ManagerRoot'))
      _, _, status = prepare(source, app)
      refute status.success?
      assert_equal 'preserved', File.read(File.join(external, 'sentinel'))
    end
  end

  def test_stage_failure_keeps_previous_manager_root
    fixture do |_directory, source, app|
      _, errors, status = prepare(source, app)
      assert status.success?, errors
      previous = File.join(app, 'Contents/Resources/ManagerRoot/JobsPathCopier/Scripts/ManageExtension.zsh')
      before = File.binread(previous)
      broken = File.join(source, 'JobsPathCopier/Scripts/ManageExtension.zsh')
      FileUtils.rm(broken)
      File.symlink('missing', broken)
      _, _, status = prepare(source, app)
      refute status.success?
      assert_equal before, File.binread(previous)
      assert_empty Dir.glob(File.join(app, 'Contents/Resources/.JobsCombinedManager.*'))
    end
  end
end
