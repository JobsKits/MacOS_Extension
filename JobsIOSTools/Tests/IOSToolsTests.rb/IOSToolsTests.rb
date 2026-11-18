# frozen_string_literal: true

# JOBS_TERMINAL_STYLE_GUARD_V1_BEGIN
if $PROGRAM_NAME == __FILE__
  # 直接运行时由 fork 父进程保护配色；子进程继续原文件，不重放 Ruby 参数和预载模块。
  def jobs_terminal_style_bootstrap_v1
    return unless $PROGRAM_NAME == __FILE__
    plain = lambda do
      ENV.update('PLAIN_OUTPUT' => '1', 'NO_COLOR' => '1', 'FORCE_COLOR' => '0',
                 'CLICOLOR' => '0', 'ANSI_COLORS_DISABLED' => '1', 'npm_config_color' => 'false')
    end
    notify = lambda do |message|
      encoding = $stderr.external_encoding || Encoding::UTF_8
      $stderr.write((message + "\n").encode(encoding, invalid: :replace, undef: :replace))
    end
    return unless $stdin.tty? && $stdout.tty?
    return if ENV.key?('NO_COLOR') || ENV['PLAIN_OUTPUT'] == '1' ||
              ENV['IS_SOURCETREE_RUNTIME'] == '1' ||
              ENV.keys.any? { |key| key.match?(/\A(?:SOURCETREE|SOURCE_TREE)/i) }
    return if ['', 'dumb'].include?(ENV.fetch('TERM', ''))
    if File::ALT_SEPARATOR == '\\' || !Process.respond_to?(:fork) ||
       Thread.list.length > 1 || ENV['TMUX'] || ENV['STY']
      plain.call
      return
    end
    tty_name = IO.popen(['tty'], err: File::NULL, &:read).strip
    groups = IO.popen(['ps', '-o', 'pgid=', '-o', 'tpgid=', '-p', Process.pid.to_s], err: File::NULL, &:read).split
    unless tty_name.match?(%r{\A/dev/[A-Za-z0-9_./-]+\z}) && groups.length == 2 &&
           groups.all? { |group| group.match?(/\A\d+\z/) } && groups[0].to_i > 0 && groups[0] == groups[1]
      plain.call
      return
    end
    owner = ENV['JOBS_TERMINAL_STYLE_OWNER']
    if ENV['JOBS_TERMINAL_STYLE_TTY'] == tty_name && owner && owner.match?(/\A\d+\z/)
      begin
        Process.kill(0, owner.to_i)
        return
      rescue Errno::ESRCH, Errno::EPERM
      end
    end
    require 'io/console'
    require 'tmpdir'
    if Thread.list.length > 1
      plain.call
      return
    end
    tty = File.open('/dev/tty', 'r+')
    tty.binmode
    tty.sync = true
    keys = ['10', '11', '12'] + (0..15).map { |index| "4;#{index}" }
    palette = %w[000000 ff5f56 5fd787 ffd75f 5fafff d787ff 5fd7ff eeeeee
                 9e9e9e ff8787 87ffaf ffff87 87bfff ffafff afffff ffffff]
    targets = { '10' => 'ffffff', '11' => '000000', '12' => 'ffffff' }
    palette.each_with_index { |color, index| targets["4;#{index}"] = color }
    query = lambda do |key|
      tty.write("\e]#{key};?\a")
      bytes = ''.b
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 0.3
      loop do
        remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        return nil if remaining <= 0 || !IO.select([tty], nil, nil, remaining)
        piece = tty.read_nonblock(256, exception: false)
        next if piece == :wait_readable
        return nil unless piece && !piece.empty?
        bytes << piece
        return nil if bytes.bytesize > 256 || !bytes.start_with?("\e".b)
        break if bytes.end_with?("\a".b) || bytes.end_with?("\e\\".b)
      end
      match = bytes.match(/\A\e\]#{Regexp.escape(key)};rgb:([0-9a-fA-F]{1,4})\/([0-9a-fA-F]{1,4})\/([0-9a-fA-F]{1,4})(?:\a|\e\\)\z/n)
      return nil unless match
      components = match.captures.map { |hex| (hex.to_i(16) * 65535.0 / (16**hex.length - 1)).round }
      { raw: bytes, rgb: components }
    rescue IOError, SystemCallError
      nil
    end
    snapshot = lambda do
      values = {}
      tty.raw(min: 0, time: 0, intr: true) do
        keys.each do |key|
          value = query.call(key)
          return nil unless value
          values[key] = value
        end
      end
      values
    rescue IOError, SystemCallError, ArgumentError
      nil
    end
    original = snapshot.call
    unless original
      notify.call('终端不支持完整配色保存，或启动时收到其它输入；保留原配色并使用纯文本。')
      tty.close
      plain.call
      return
    end
    directory = Dir.mktmpdir('jobs-terminal-style-')
    recovery = File.join(directory, 'restore.sh')
    original_bytes = keys.map { |key| original.fetch(key).fetch(:raw) }.join
    recovery_source = "#!/bin/sh\n" \
      "[ -t 0 ] && [ \"$(tty)\" = '#{tty_name}' ] || { printf '请在原终端运行恢复入口。\\n' >&2; exit 1; }\n" \
      "printf '本操作会覆盖此终端当前配色。确认恢复脚本启动前的配色，请输入 YES：' >&2\n" \
      "IFS= read -r jobs_restore_choice\n[ \"$jobs_restore_choice\" = YES ] || exit 1\n" \
      "printf '%s\\033[0m' '#{original_bytes}' > /dev/tty\n"
    File.open(recovery, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
      file.binmode
      file.write(recovery_source.b)
    end
    notify.call("本次终端临时使用黑底白字；强退后恢复入口：sh \"#{recovery}\"")
    changed = false
    applied = nil
    # 比较仍生效的本轮颜色，只恢复未被用户另行修改的项。
    cleanup = lambda do
      current = applied && snapshot.call
      unless current
        notify.call("终端配色未能安全自动恢复；确认覆盖当前配色后可运行：sh \"#{recovery}\"")
        return false
      end
      conflicts = []
      restore_bytes = ''.b
      keys.each do |key|
        if current.fetch(key).fetch(:rgb) == applied.fetch(key).fetch(:rgb)
          restore_bytes << original.fetch(key).fetch(:raw)
        else
          conflicts << key
        end
      end
      tty.write(restore_bytes + "\e[0m".b)
      if conflicts.empty?
        File.unlink(recovery)
        Dir.rmdir(directory)
        true
      else
        notify.call("检测到运行期间的配色变更，已保留这些项：#{conflicts.join(' ')}")
        notify.call("确认要覆盖后续改色时才使用恢复入口：sh \"#{recovery}\"")
        false
      end
    rescue IOError, SystemCallError
      notify.call("终端配色未能安全自动恢复；确认覆盖当前配色后可运行：sh \"#{recovery}\"")
      false
    end
    child_pid = nil
    guardian = false
    interrupted = nil
    previous_signals = {}
    %w[INT TERM HUP].each do |name|
      previous_signals[name] = Signal.trap(name) do
        interrupted = name
        if child_pid && name != 'INT'
          begin
            Process.kill(name, child_pid)
          rescue Errno::ESRCH
          end
        end
      end
    end
    begin
      changed = true
      tty.write(targets.map { |key, color| "\e]#{key};##{color}\a" }.join + "\e[0m")
      applied = snapshot.call
      unless applied
        notify.call('无法核实本次临时配色，已停止启动业务。')
        raise SystemExit, 1
      end
      desired = targets.all? do |key, hex|
        rgb = hex.scan(/../).map { |component| component.to_i(16) * 257 }
        applied.fetch(key).fetch(:rgb).zip(rgb).all? { |actual, expected| (actual - expected).abs <= 255 }
      end
      unless desired
        notify.call('终端未接受本次配色，恢复后使用纯文本。')
        restored = cleanup.call
        changed = false
        raise SystemExit, 1 unless restored
        plain.call
        return
      end
      if interrupted
        raise SystemExit, 128 + Signal.list.fetch(interrupted)
      end
      if Thread.list.length > 1
        restored = cleanup.call
        changed = false
        raise SystemExit, 1 unless restored
        plain.call
        return
      end
      $stdout.flush
      $stderr.flush
      begin
        child_pid = Process.fork
      rescue NotImplementedError, SystemCallError
        restored = cleanup.call
        changed = false
        raise SystemExit, 1 unless restored
        plain.call
        return
      end
      unless child_pid
        changed = false
        ENV['JOBS_TERMINAL_STYLE_TTY'] = tty_name
        ENV['JOBS_TERMINAL_STYLE_OWNER'] = Process.ppid.to_s
        raise SystemExit, 128 + Signal.list.fetch(interrupted) if interrupted
        return
      end
      guardian = true
      result = nil
      loop do
        begin
          _, result = Process.wait2(child_pid)
          break
        rescue Interrupt, Errno::EINTR
        end
      end
      status_code = result.exitstatus || 128 + result.termsig
      %w[INT TERM HUP].each { |name| Signal.trap(name, 'IGNORE') }
      restored = cleanup.call
      changed = false
      status_code = 1 if !restored && status_code.zero?
      tty.close
      Process.exit!(status_code)
    ensure
      if changed
        %w[INT TERM HUP].each { |name| Signal.trap(name, 'IGNORE') }
        cleanup.call
      end
      previous_signals.each { |name, handler| Signal.trap(name, handler) } unless guardian
      tty.close unless tty.closed?
    end
  rescue IOError, SystemCallError, LoadError => error
    if guardian
      notify.call("终端保护监督进程异常：#{error.message}")
      Process.exit!(1)
    end
    raise SystemExit, 1 if changed
    notify.call("终端保护不可用，使用纯文本：#{error.message}")
    plain.call
  end
  jobs_terminal_style_bootstrap_v1

end
# JOBS_TERMINAL_STYLE_GUARD_V1_END

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'json'
require 'digest'

require_relative '../../../Tests/SourceLayoutHelper.rb/SourceLayoutHelper'

class IOSToolsTests < Minitest::Test
  ROOT = File.expand_path('..', File.dirname(__dir__))
  TOOLS = JobsSourceLayout.file(File.join(ROOT, 'Scripts', 'Tools'))
  MANIFEST = JSON.parse(File.read(JobsSourceLayout.file(File.join(TOOLS, 'SourceManifest.json'))))
  INSTALL = JobsSourceLayout.file(File.join(ROOT, 'Scripts/【MacOS】ManageExtension.zsh/【MacOS】ManageExtension.zsh'))
  UNINSTALL = JobsSourceLayout.file(File.join(ROOT, 'Scripts/【MacOS】ManageExtension.zsh/【MacOS】ManageExtension.zsh'))

  def test_shell_syntax_and_source_provenance
    Dir.glob(JobsSourceLayout.file(File.join(ROOT, '**', '*'))).select { |p| File.file?(p) && p.end_with?('.command', '.zsh') }.each do |path|
      out, status = Open3.capture2e('/bin/zsh', '-n', path)
      assert status.success?, "#{path}: #{out}"
    end
    assert_operator MANIFEST.size, :>=, 9
    MANIFEST.each do |row|
      assert_equal row['bundledSHA256'], Digest::SHA256.file(JobsSourceLayout.file(File.join(TOOLS, row['file']))).hexdigest
      original = File.expand_path("../../../../JobsCommand@iOS/#{row['source']}", File.dirname(__dir__))
      assert_equal row['sourceSHA256'], Digest::SHA256.file(original).hexdigest if File.file?(original)
    end
  end

  def test_all_nine_read_only_routes_and_podspec_gate
    Dir.mktmpdir('JobsIOSRoute') do |root|
      project = File.join(root, "中文 ' $() `x`\n工程")
      FileUtils.mkdir_p(project)
      File.write(File.join(project, 'Podfile'), '')
      MANIFEST.each do |row|
        out, status = Open3.capture2e('/bin/zsh', JobsSourceLayout.file(File.join(TOOLS, '【MacOS】DispatchIOSTools.zsh/【MacOS】DispatchIOSTools.zsh')), '--plan', row['feature'], project)
        assert_equal row['feature'] != 'ios-pod-build-check', status.success?, out
        assert_includes out, '只读计划通过' if status.success?
      end
      nested = File.join(project, 'Nested')
      FileUtils.mkdir_p(nested)
      File.write(File.join(nested, 'Nested.podspec'), '')
      _, status = Open3.capture2e('/bin/zsh', JobsSourceLayout.file(File.join(TOOLS, '【MacOS】DispatchIOSTools.zsh/【MacOS】DispatchIOSTools.zsh')), '--plan', 'ios-pod-build-check', project)
      refute status.success?
      File.write(File.join(project, 'Current.podspec'), '')
      out, status = Open3.capture2e('/bin/zsh', JobsSourceLayout.file(File.join(TOOLS, '【MacOS】DispatchIOSTools.zsh/【MacOS】DispatchIOSTools.zsh')), '--plan', 'ios-pod-build-check', project)
      assert status.success?, out
      assert_includes out, '只读计划通过'
      assert_equal %w[Current.podspec Nested Podfile], Dir.children(project).sort
      _, status = Open3.capture2e('/bin/zsh', JobsSourceLayout.file(File.join(TOOLS, '【MacOS】DispatchIOSTools.zsh/【MacOS】DispatchIOSTools.zsh')), '--plan', 'unknown', project)
      refute status.success?
      _, status = Open3.capture2e('/bin/zsh', JobsSourceLayout.file(File.join(TOOLS, '【MacOS】DispatchIOSTools.zsh/【MacOS】DispatchIOSTools.zsh')), '--plan', 'ios-clean-cache', root)
      refute status.success?
    end
  end

  def test_build_cleanup_reuses_canonical_script_and_checks_native_ios_only
    canonical = File.expand_path('../../JobsTerminalOpener/Scripts/【MacOS】CleanBuildArtifacts.zsh/【MacOS】CleanBuildArtifacts.zsh', File.dirname(__dir__))
    assert_equal File.binread(canonical), File.binread(JobsSourceLayout.file(File.join(TOOLS, '【MacOS】CleanBuildArtifacts.zsh/【MacOS】CleanBuildArtifacts.zsh')))
    validator = File.expand_path('../../JobsTerminalOpener/JobsTerminalShared/DependencyProjectValidator.swift', File.dirname(__dir__))
    assert_equal File.binread(validator), File.binread(JobsSourceLayout.file(File.join(ROOT, 'JobsIOSToolsShared/DependencyProjectValidator.swift')))
    Dir.mktmpdir('JobsIOSCleanRoute') do |root|
      project = File.join(root, "中文 ' $() `x`\n工程")
      xcode = File.join(project, 'App.xcodeproj')
      FileUtils.mkdir_p(xcode)
      File.write(File.join(xcode, 'project.pbxproj'), 'SDKROOT = iphoneos;')
      FileUtils.mkdir_p(File.join(project, 'build'))
      File.write(File.join(project, 'build', 'keep-until-confirmed'), 'intact')
      out, status = Open3.capture2e('/bin/zsh', JobsSourceLayout.file(File.join(TOOLS, '【MacOS】DispatchIOSTools.zsh/【MacOS】DispatchIOSTools.zsh')), '--plan', 'ios-clean-build-artifacts', project)
      assert status.success?, out
      assert File.file?(File.join(project, 'build', 'keep-until-confirmed'))
      out, status = Open3.capture2e('/bin/zsh', JobsSourceLayout.file(File.join(TOOLS, '【MacOS】DispatchIOSTools.zsh/【MacOS】DispatchIOSTools.zsh')), '--plan', 'ios-clean-cache', project)
      assert status.success?, out
      assert_includes out, '动作：ios-clean-build-artifacts'
      assert_includes out, 'CleanBuildArtifacts.zsh'
      refute File.exist?(JobsSourceLayout.file(File.join(TOOLS, '【MacOS】🧹双击清理iOS缓存.command')))
      File.write(File.join(project, 'pubspec.yaml'), "dependencies: {flutter: {sdk: flutter}}\n")
      out, status = Open3.capture2e('/bin/zsh', JobsSourceLayout.file(File.join(TOOLS, '【MacOS】DispatchIOSTools.zsh/【MacOS】DispatchIOSTools.zsh')), '--plan', 'ios-clean-build-artifacts', project)
      refute status.success?, out
      assert File.file?(File.join(project, 'build', 'keep-until-confirmed'))
      File.delete(File.join(project, 'pubspec.yaml'))
      File.write(File.join(xcode, 'project.pbxproj'), 'SDKROOT = macosx;')
      out, status = Open3.capture2e('/bin/zsh', JobsSourceLayout.file(File.join(TOOLS, '【MacOS】DispatchIOSTools.zsh/【MacOS】DispatchIOSTools.zsh')), '--plan', 'ios-clean-build-artifacts', project)
      refute status.success?, out
      assert File.file?(File.join(project, 'build', 'keep-until-confirmed'))
    end
  end

  def definitions(path, operation: :install)
    source = File.read(path)
    if source.include?('run_install_operation() {')
      source = source[/^run_#{operation}_operation\(\) \{\n\(\n(.*?)\n# 外层统一负责交互/m, 1]
      raise "缺少操作分支 #{operation}" unless source
      return source
    end
    source.sub(/\nmain "\$@"\s*\z/, "\n")
  end

  def run_fixture(source, body, operation: :install)
    Dir.mktmpdir('JobsIOSFeatures') do |root|
      config = File.join(root, 'EnabledFeatures.txt')
      script = File.join(root, 'fixture.zsh')
      File.write(script, definitions(source, operation: operation) + "\nFEATURE_CONFIG=#{config.dump}\nlog() { print -r -- \"$*\"; }\n" + body)
      out, status = Open3.capture2e('/bin/zsh', '-f', script)
      assert status.success?, out
      yield config, out
    end
  end

  def test_subset_install_is_union_and_partial_uninstall_keeps_other_actions
    run_fixture(INSTALL, <<~ZSH) do |config, _out|
      parse_feature_options --features ios-clean-cache,ios-pod-build-check
      persist_feature_selection
      parse_feature_options --features=ios-pod-update
      persist_feature_selection
    ZSH
      assert_equal 'ios-pod-update,ios-pod-build-check,ios-clean-build-artifacts', File.read(config).strip
    end
    run_fixture(UNINSTALL, <<~ZSH, operation: :uninstall) do |config, out|
      print -r -- 'ios-clean-cache,ios-pod-update' > "$FEATURE_CONFIG"
      parse_feature_options --features ios-clean-cache
      plan_feature_removal
      uninstall_extension
    ZSH
      assert_equal 'ios-pod-update', File.read(config).strip
      assert_includes out, '仅关闭所选功能'
    end
    run_fixture(UNINSTALL, <<~ZSH, operation: :uninstall) do |_config, out|
      parse_feature_options --non-interactive
      plan_feature_removal
      (( ${#REMAINING_FEATURES[@]} == 0 )) || exit 1
    ZSH
      assert_includes out, '关闭功能'
    end
  end

  def test_bad_feature_stops_before_mutation
    run_fixture(INSTALL, <<~ZSH) do |config, _out|
      ( parse_feature_options --features 'ios-clean-cache,unexpected' )
      (( $? != 0 )) || exit 1
    ZSH
      refute File.exist?(config)
    end
  end

  def test_existing_cache_selection_migrates_when_installing_or_removing_another_feature
    run_fixture(INSTALL, <<~ZSH) do |config, _out|
      print -r -- 'ios-clean-cache' > "$FEATURE_CONFIG"
      parse_feature_options --features ios-pod-update
      persist_feature_selection
    ZSH
      assert_equal 'ios-pod-update,ios-clean-build-artifacts', File.read(config).strip
    end
    run_fixture(UNINSTALL, <<~ZSH, operation: :uninstall) do |config, _out|
      print -r -- 'ios-clean-cache,ios-pod-update' > "$FEATURE_CONFIG"
      parse_feature_options --features ios-pod-update
      plan_feature_removal
      uninstall_extension
    ZSH
      assert_equal 'ios-clean-build-artifacts', File.read(config).strip
    end
  end

  def test_podspec_gate_matches_hidden_files_and_rejects_directories_or_uppercase
    Dir.mktmpdir('JobsIOSPodGate') do |root|
      fixture = File.join(root, 'Project')
      FileUtils.mkdir_p(fixture)
      File.write(File.join(fixture, 'Podfile'), '')
      candidates = [['.Current.podspec', false, true], ['Current.podspec', false, true],
                    ['Directory.podspec', true, false], ['Upper.PODSPEC', false, false]]
      candidates.each do |name, directory, expected|
        path = File.join(fixture, name)
        directory ? FileUtils.mkdir_p(path) : File.write(path, '')
        out, status = Open3.capture2e('/bin/zsh', JobsSourceLayout.file(File.join(TOOLS, '【MacOS】DispatchIOSTools.zsh/【MacOS】DispatchIOSTools.zsh')), '--plan', 'ios-pod-build-check', fixture)
        assert_equal expected, status.success?, "#{name}: #{out}"
        directory ? Dir.rmdir(path) : File.delete(path)
      end
      nested = File.join(fixture, 'Nested')
      FileUtils.mkdir_p(nested)
      File.write(File.join(nested, 'Current.podspec'), '')
      _, status = Open3.capture2e('/bin/zsh', JobsSourceLayout.file(File.join(TOOLS, '【MacOS】DispatchIOSTools.zsh/【MacOS】DispatchIOSTools.zsh')), '--plan', 'ios-pod-build-check', fixture)
      refute status.success?
    end
  end

  def test_pod_target_and_sibling_dependency_paths_without_compiling
    row = MANIFEST.find { |entry| entry['feature'] == 'ios-pod-build-check' }
    Dir.mktmpdir('JobsIOSPodAdapter') do |root|
      target = File.join(root, '目标 Pod')
      sibling = File.join(root, 'Sibling')
      FileUtils.mkdir_p([target, sibling])
      File.write(File.join(target, 'Target.podspec'), "s.name = 'Target'\ns.dependency 'Sibling'\n")
      File.write(File.join(sibling, 'Sibling.podspec'), "s.name = 'Sibling'\n")
      fixture = File.join(root, 'adapter.zsh')
      File.write(fixture, definitions(JobsSourceLayout.file(File.join(TOOLS, row['file']))) + <<~ZSH)
        log() { :; }
        ask_for_workspace_root
        [[ "$WORKSPACE_ROOT" == "${JOBS_IOS_PROJECT_DIR:h}" ]] || exit 2
        ask_for_target_pod_name
        [[ "$TARGET_PODSPEC_PATH" == "$JOBS_IOS_PROJECT_DIR/Target.podspec" ]] || exit 3
        [[ "$TARGET_POD_NAME" == Target ]] || exit 4
        [[ "$(collect_smart_dependency_podspecs "$TARGET_PODSPEC_PATH")" == "$WORKSPACE_ROOT/Sibling/Sibling.podspec" ]] || exit 5
        [[ -z "$(find_x_command_candidates)" ]] || exit 6
      ZSH
      out, status = Open3.capture2e({ 'JOBS_IOS_PROJECT_DIR' => target }, '/bin/zsh', '-f', fixture)
      assert status.success?, "#{status.exitstatus}: #{out}"
      assert_equal ['Target.podspec'], Dir.children(target)
      assert_equal ['Sibling.podspec'], Dir.children(sibling)
    end
  end

  def test_swift_validator_request_and_shell_transport
    Dir.mktmpdir('JobsIOSSwift') do |root|
      binary = File.join(root, 'IOSToolsBehaviorTests')
      sources = [
        'JobsIOSToolsShared/IOSProjectValidator/IOSProjectValidator.swift',
        'JobsIOSToolsShared/DependencyProjectValidator.swift',
        'JobsIOSToolsShared/IOSToolsRequest/IOSToolsRequest.swift',
        'JobsIOSToolsShared/JobsIOSFactories.swift',
        'JobsIOSTools/IOSToolsLauncher/IOSToolsLauncher.swift',
        'Tests/IOSToolsBehaviorTests.swift'
      ].map { |p| JobsSourceLayout.file(File.join(ROOT, p)) }
      out, status = Open3.capture2e('/usr/bin/xcrun', 'swiftc', *sources, '-o', binary)
      assert status.success?, out
      out, status = Open3.capture2e(binary)
      assert status.success?, out
      assert_includes out, 'checks passed'
    end
  end

  def test_real_app_delegate_deduplicates_both_system_callbacks
    Dir.mktmpdir('JobsIOSDelegate') do |root|
      binary = File.join(root, 'IOSToolsAppDelegateTests')
      sources = [
        'JobsIOSTools/AppDelegate.swift',
        'JobsIOSToolsShared/IOSToolsRequest/IOSToolsRequest.swift',
        'JobsIOSToolsShared/JobsIOSFactories.swift',
        'Tests/IOSToolsAppDelegateTests.swift'
      ].map { |p| JobsSourceLayout.file(File.join(ROOT, p)) }
      out, status = Open3.capture2e('/usr/bin/xcrun', 'swiftc', *sources, '-o', binary)
      assert status.success?, out
      out, status = Open3.capture2e(binary)
      assert status.success?, out
      assert_includes out, 'URL 回调去重回归通过'
    end
  end

  def test_sidebar_menu_dispatch_uses_the_targeted_project
    Dir.mktmpdir('JobsIOSSidebar') do |directory|
      sources = %w[
        JobsIOSToolsShared/IOSProjectValidator/IOSProjectValidator.swift
        JobsIOSToolsShared/DependencyProjectValidator.swift
        JobsIOSToolsShared/IOSToolsRequest/IOSToolsRequest.swift
        JobsIOSToolsShared/JobsIOSFactories.swift
        JobsIOSToolsFinderSync/FinderSync.swift
      ].map do |relative|
        source = File.read(JobsSourceLayout.file(File.join(ROOT, relative))).gsub(/^import FinderSync\s*$/, '')
        source = source.split('enum IOSFeatureConfiguration {').first if relative.include?('IOSProjectValidator')
        source.gsub('NSWorkspace.shared.open(request)', 'TestWorkspace.open(request)')
              .gsub('NSAlert.jobsMake', 'TestAlert.jobsMake')
      end
      stubs = <<~'SWIFT'
        import AppKit
        enum FIMenuKind { case contextualMenuForItems, contextualMenuForContainer, contextualMenuForSidebar, toolbarItemMenu }
        class FIFinderSync: NSObject { func menu(for kind: FIMenuKind) -> NSMenu? { nil } }
        final class FIFinderSyncController {
            static let shared = FIFinderSyncController()
            static func `default`() -> FIFinderSyncController { shared }
            var directoryURLs: Set<URL> = []
            var selected: [URL]?
            var targeted: URL?
            func selectedItemURLs() -> [URL]? { selected }
            func targetedURL() -> URL? { targeted }
        }
        enum IOSFeatureConfiguration {
            static var enabled = Set(IOSToolsAction.allCases)
            static func enabledFeatures() -> Set<IOSToolsAction> { enabled }
        }
        enum TestWorkspace {
            static var requests: [URL] = []
            static func open(_ url: URL) -> Bool { requests.append(url); return true }
        }
        final class TestAlert {
            static func jobsMake(_ configure: (TestAlert) -> Void) -> TestAlert {
                let alert = TestAlert(); configure(alert); return alert
            }
            func byAlertStyle(_ value: NSAlert.Style) -> Self { self }
            func byMessageText(_ value: String) -> Self { self }
            func byInformativeText(_ value: String) -> Self { self }
            func byAddButton(_ value: String) -> Self { self }
            func runModal() {}
        }
      SWIFT
      checks = <<~'SWIFT'
        var assertions = 0
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            assertions += 1
            if !condition() { fatalError(message) }
        }
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let manager = FileManager.default
        let project = root.appendingPathComponent("侧边栏 ' $() 项目")
        let other = root.appendingPathComponent("主区域另一个项目")
        for folder in [project, other] {
            let xcode = folder.appendingPathComponent("App.xcodeproj")
            try manager.createDirectory(at: xcode, withIntermediateDirectories: true)
            try "SDKROOT = iphoneos;".write(to: xcode.appendingPathComponent("project.pbxproj"), atomically: true, encoding: .utf8)
            try Data().write(to: folder.appendingPathComponent("Podfile"))
            try Data().write(to: folder.appendingPathComponent("Current.podspec"))
        }
        let finder = FinderSync()
        let controller = FIFinderSyncController.default()
        for kind in [FIMenuKind.contextualMenuForItems, .contextualMenuForContainer, .contextualMenuForSidebar] {
            controller.selected = kind == .contextualMenuForItems ? [project] : [other, root]
            controller.targeted = project
            let items = finder.menu(for: kind)!.items[0].submenu!.items
            expect(items.map(\.title) == IOSToolsAction.allCases.map(\.title), "all 11 configured iOS actions")
            for original in items {
                let item = original.copy() as! NSMenuItem
                _ = (item.target as! NSObject).perform(item.action!, with: item)
                expect(IOSToolsRequest.projectURL(from: TestWorkspace.requests.last!)?.path == project.path, "copied menu targets correct project")
                expect(IOSToolsRequest.action(from: TestWorkspace.requests.last!)?.title == item.title, "stable action survives menu copy")
            }
        }
        controller.targeted = project
        let sideItems = finder.menu(for: .contextualMenuForSidebar)!.items[0].submenu!.items
        controller.selected = [other]
        _ = finder.menu(for: .contextualMenuForItems)
        for item in sideItems {
            _ = (item.target as! NSObject).perform(item.action!, with: item)
            expect(IOSToolsRequest.projectURL(from: TestWorkspace.requests.last!)?.path == project.path, "interleaved item menu cannot retarget sidebar actions")
        }
        var remote = URLComponents(url: project, resolvingAgainstBaseURL: false)!
        remote.host = "remote-host"
        for target in [nil, URL(string: "x-apple-finder:Recents"), URL(string: "https://example.com"),
                       remote.url, project.appendingPathComponent("Podfile"), root.appendingPathComponent("missing")] as [URL?] {
            controller.targeted = target
            expect(finder.menu(for: .contextualMenuForSidebar) == nil, "invalid sidebar target must not borrow selected project")
            let count = TestWorkspace.requests.count
            _ = (sideItems[0].target as! NSObject).perform(sideItems[0].action!, with: sideItems[0])
            expect(TestWorkspace.requests.count == count, "invalidated sidebar action must not dispatch")
        }
        controller.targeted = root
        expect(finder.menu(for: .contextualMenuForSidebar) == nil, "non-iOS folder has no iOS menu")
        controller.targeted = project
        IOSFeatureConfiguration.enabled = [.podUpdate]
        expect(finder.menu(for: .contextualMenuForSidebar)?.items[0].submenu?.items.map(\.title) == [IOSToolsAction.podUpdate.title], "sidebar respects partial configuration")
        IOSFeatureConfiguration.enabled = []
        expect(finder.menu(for: .contextualMenuForSidebar) == nil, "disabled menu stays hidden")
        expect(finder.menu(for: .toolbarItemMenu) == nil, "unsupported toolbar menu stays hidden")
        print("PASS: \(assertions) iOS sidebar menu assertions")
      SWIFT
      path = File.join(directory, 'main.swift')
      binary = File.join(directory, 'sidebar-tests')
      File.write(path, ([stubs] + sources + [checks]).join("\n"))
      output, status = Open3.capture2e('/usr/bin/xcrun', 'swiftc', path, '-o', binary)
      assert status.success?, output
      output, status = Open3.capture2e(binary, directory)
      assert status.success?, output
      assert_includes output, 'iOS sidebar menu assertions'
    end
  end
end
