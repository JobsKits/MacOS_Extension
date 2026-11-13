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

require 'fileutils'
require 'minitest/autorun'
require 'open3'
require 'tmpdir'

class BuildArtifactCleanerTests < Minitest::Test
  SCRIPT = File.expand_path('../Scripts/CleanBuildArtifacts.zsh', __dir__)

  def self.detector
    return @detector if @detector
    build = Dir.mktmpdir('jobs-build-detector-')
    @detector = File.join(build, 'detector')
    output, status = Open3.capture2e('/usr/bin/swiftc',
      File.expand_path('../JobsTerminalShared/DependencyProjectValidator.swift', __dir__),
      File.join(__dir__, 'DependencyProjectValidatorTests.swift'), '-o', @detector)
    raise output unless status.success?
    Minitest.after_run { FileUtils.remove_entry(build) }
    @detector
  end

  def setup
    @temporary = File.realpath(Dir.mktmpdir('jobs-build-clean-'))
    @root = File.join(@temporary, "工程 [test] ' $(touch SHOULD_NOT_EXIST)\n第二行")
    @home = File.join(@temporary, 'home')
    FileUtils.mkdir_p([@root, @home])
  end

  def teardown
    FileUtils.remove_entry(@temporary)
  end

  def file(path, text = 'keep')
    path = File.join(@root, path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, text)
    path
  end

  def flutter
    file('pubspec.yaml', "name: demo\ndependencies:\n  flutter:\n    sdk: flutter\n")
    file('lib/main.dart')
  end

  def android(prefix = '')
    file(File.join(prefix, 'settings.gradle.kts'), 'include(":app", ":feature:chat")')
    file(File.join(prefix, 'app/build.gradle.kts'), 'plugins { id("com.android.application") }')
    file(File.join(prefix, 'feature/chat/build.gradle'), "apply plugin: 'com.android.library'")
  end

  def ios(prefix = '')
    file(File.join(prefix, 'Demo.xcodeproj/project.pbxproj'), 'SDKROOT = iphoneos;')
  end

  def harmony(prefix = '')
    file(File.join(prefix, 'hvigorfile.ts'), "throw new Error('must never execute project scripts');")
    file(File.join(prefix, 'build-profile.json5'), '{ app: {}, modules: [{name: "entry", srcPath: "./entry"}] }')
    file(File.join(prefix, 'oh-package.json5'), '{}')
    file(File.join(prefix, 'AppScope/app.json5'), '{ app: { bundleName: "com.example.demo" } }')
    %w[entry features/chat].each do |mod|
      file(File.join(prefix, mod, 'build-profile.json5'), '{}')
      file(File.join(prefix, mod, 'src/main/module.json5'), '{ module: { type: "entry" } }')
      file(File.join(prefix, mod, 'hvigorfile.ts'), 'export default {};')
      file(File.join(prefix, mod, 'oh-package.json5'), '{}')
    end
  end

  def run_clean(mode = '--yes', input = '', target = @root, scope = nil)
    # 用相同磁盘夹具核对真实 Finder 检测器与终端脚本，防止标题和删除范围分歧。
    kind, swift_status = Open3.capture2e(self.class.detector, '--build-artifact-kind', target)
    assert swift_status.success?, kind
    detected, detect_status = Open3.capture2e({ 'HOME' => @home }, '/bin/zsh', SCRIPT, target, '--detect', *[scope].compact)
    assert_equal kind.strip, detect_status.success? ? detected.strip : 'unknown', detected
    Open3.capture2e({ 'HOME' => @home }, '/bin/zsh', SCRIPT, target, *[mode, scope].compact, stdin_data: input)
  end

  def test_harmony_native_multimodule_preserves_dependencies_signing_and_nested_projects
    harmony
    outputs = %w[build .hvigor entry/build entry/.hvigor features/chat/build]
    outputs.each { |p| file(p + '/artifact') }
    preserved = %w[oh_modules/library/build/keep node_modules/package/build/keep oh-package-lock.json5 entry/oh-package-lock.json5 entry/libs/flutter.har signing/key.p12 hvigor/hvigor-config.json5 unrelated/build/keep]
    preserved.each { |p| file(p) }
    harmony('independent')
    file('independent/entry/build/keep')
    %w[vendored generated_flutter].each do |nested|
      harmony(nested)
      FileUtils.rm_f(File.join(@root, nested, 'AppScope/app.json5'))
      file(File.join(nested, nested == 'vendored' ? '.git' : 'pubspec.yaml'))
      file(File.join(nested, 'entry/build/keep'))
    end
    global = File.join(@home, '.hvigor/cache/keep')
    FileUtils.mkdir_p(File.dirname(global))
    File.write(global, 'global cache')
    output, status = run_clean
    assert status.success?, output
    assert_includes output, '工程类型：OpenHarmony'
    outputs.each { |p| refute File.exist?(File.join(@root, p)), p }
    (preserved + %w[independent/entry/build/keep vendored/entry/build/keep generated_flutter/entry/build/keep]).each { |p| assert File.exist?(File.join(@root, p)), p }
    assert File.exist?(global)
  end

  def test_flutter_cleans_recognized_ohos_and_native_entry_does_not_touch_flutter_parent
    flutter
    harmony('ohos')
    outputs = %w[build/ohos .dart_tool ohos/build ohos/.hvigor ohos/entry/build ohos/features/chat/build]
    outputs.each { |p| file(p + '/artifact') }
    file('ohos/entry/libs/flutter.har')
    output, status = run_clean('--yes', '', File.join(@root, 'ohos'))
    assert status.success?, output
    assert_includes output, '工程类型：OpenHarmony'
    assert File.exist?(File.join(@root, 'build/ohos/artifact'))
    assert File.exist?(File.join(@root, '.dart_tool/artifact'))
    outputs.each { |p| file(p + '/artifact') }
    output, status = run_clean
    assert status.success?, output
    assert_includes output, '工程类型：Flutter'
    outputs.each { |p| refute File.exist?(File.join(@root, p)), p }
    assert File.exist?(File.join(@root, 'ohos/entry/libs/flutter.har'))
  end

  def test_harmony_module_can_be_selected_and_invalid_or_linked_ohos_is_preserved
    harmony
    file('entry/build/artifact')
    file('features/chat/build/keep')
    output, status = run_clean('--yes', '', File.join(@root, 'entry'))
    assert status.success?, output
    assert_includes output, '工程类型：OpenHarmony'
    assert File.exist?(File.join(@root, 'features/chat/build/keep'))
    flutter
    file('ohos/build/keep')
    output, status = run_clean
    assert status.success?, output
    assert File.exist?(File.join(@root, 'ohos/build/keep'))
    FileUtils.rm_r(File.join(@root, 'ohos'))
    outside = File.join(@temporary, 'native-outside')
    FileUtils.mkdir_p(outside)
    File.symlink(outside, File.join(@root, 'ohos'))
    output, status = run_clean
    assert status.success?, output
    assert File.symlink?(File.join(@root, 'ohos'))
  end

  def test_harmony_incomplete_markers_and_module_output_links_are_safe
    harmony
    file('build/keep')
    FileUtils.rm_f(File.join(@root, 'AppScope/app.json5'))
    output, status = run_clean
    refute status.success?, output
    assert File.exist?(File.join(@root, 'build/keep'))
    harmony
    outside = File.join(@temporary, 'outside')
    FileUtils.mkdir_p(outside)
    File.write(File.join(outside, 'keep'), 'safe')
    File.symlink(outside, File.join(@root, 'entry/build'))
    output, status = run_clean
    refute status.success?, output
    assert File.exist?(File.join(@root, 'build/keep'))
    assert File.exist?(File.join(outside, 'keep'))
  end

  def test_flutter_has_priority_and_cleans_only_recognized_platforms
    flutter
    android('android')
    ios('ios')
    outputs = %w[build .dart_tool android/build android/.gradle android/app/build android/feature/chat/build android/app/.cxx ios/build ios/DerivedData ios/Flutter/ephemeral windows/flutter/ephemeral]
    outputs.each { |p| file(p + '/artifact') }
    preserved = %w[pubspec.lock ios/Podfile.lock ios/Pods/source ios/Flutter/Generated.xcconfig android/local.properties unknown/build/user.txt]
    preserved.each { |p| file(p) }
    output, status = run_clean
    assert status.success?, output
    assert_includes output, '工程类型：Flutter'
    outputs.each { |p| refute File.exist?(File.join(@root, p)), p }
    preserved.each { |p| assert File.exist?(File.join(@root, p)), p }
    assert File.exist?(File.join(@root, 'lib/main.dart'))
    refute File.exist?(File.join(@root, 'SHOULD_NOT_EXIST'))
  end

  def test_android_kotlin_multimodule_and_nested_project_boundary
    android
    outputs = %w[build .gradle .kotlin app/build feature/chat/build feature/chat/.externalNativeBuild]
    outputs.each { |p| file(p + '/artifact') }
    file('independent/settings.gradle', 'include(":app")')
    file('independent/build.gradle', 'plugins { id("com.android.application") }')
    file('independent/build/keep')
    file('gradle/wrapper/gradle-wrapper.properties')
    output, status = run_clean
    assert status.success?, output
    assert_includes output, '工程类型：Android'
    outputs.each { |p| refute File.exist?(File.join(@root, p)), p }
    assert File.exist?(File.join(@root, 'independent/build/keep'))
    assert File.exist?(File.join(@root, 'gradle/wrapper/gradle-wrapper.properties'))
  end

  def test_flutter_android_openharmony_scope_preserves_ios_desktop_and_shared_artifacts
    flutter
    android('android')
    harmony('ohos')
    ios('ios')
    outputs = %w[android/build android/.gradle android/.kotlin android/app/build android/feature/chat/.cxx build/app build/ohos ohos/build ohos/.hvigor ohos/entry/build]
    preserved = %w[build/ios/artifact build/windows/artifact build/shared/artifact .dart_tool/artifact ios/build/artifact ios/DerivedData/artifact ios/Flutter/ephemeral/artifact windows/flutter/ephemeral/artifact pubspec.lock ohos/entry/libs/flutter.har]
    outputs.each { |path| file(path + '/artifact') }
    preserved.each { |path| file(path) }

    output, status = run_clean('--dry-run', '', @root, '--android-openharmony')
    assert status.success?, output
    assert_includes output, '清理范围：Android / OpenHarmony'
    outputs.each { |path| assert File.exist?(File.join(@root, path)), path }
    output, status = run_clean(nil, "CLEAN\n", @root, '--android-openharmony')
    assert status.success?, output
    outputs.each { |path| refute File.exist?(File.join(@root, path)), path }
    preserved.each { |path| assert File.exist?(File.join(@root, path)), path }
  end

  def test_flutter_android_openharmony_scope_is_empty_without_recognized_platforms
    flutter
    %w[build/app/keep build/ohos/keep android/build/keep ohos/build/keep .dart_tool/keep].each { |path| file(path) }
    output, status = run_clean('--yes', '', @root, '--android-openharmony')
    assert status.success?, output
    assert_includes output, '没有可清理'
    assert File.exist?(File.join(@root, 'build/app/keep'))
    assert File.exist?(File.join(@root, 'ohos/build/keep'))
    assert File.exist?(File.join(@root, '.dart_tool/keep'))
  end

  def test_android_openharmony_scope_rejects_native_ios_and_unknown_flags_before_deleting
    ios
    file('build/keep')
    [['--yes', '--android-openharmony'], ['--yes', '--unknown'], ['--yes', '--dry-run']].each do |arguments|
      output, status = Open3.capture2e({ 'HOME' => @home }, '/bin/zsh', SCRIPT, @root, *arguments)
      refute status.success?, output
      assert File.exist?(File.join(@root, 'build/keep'))
    end
  end

  def test_android_version_catalog_project_uses_manifest_evidence
    file('settings.gradle.kts')
    file('app/build.gradle.kts', 'plugins { alias(libs.plugins.android.application) }')
    file('app/src/main/AndroidManifest.xml', '<manifest/>')
    file('app/build/artifact')
    output, status = run_clean
    assert status.success?, output
    refute File.exist?(File.join(@root, 'app/build'))
  end

  def test_ios_preserves_pods_locks_and_global_cache
    ios
    file('build/artifact')
    file('DerivedData/artifact')
    file('Pods/source')
    file('Podfile.lock')
    global = File.join(@home, 'Library/Developer/Xcode/DerivedData/Other/Build/keep')
    FileUtils.mkdir_p(File.dirname(global))
    File.write(global, 'other project')
    output, status = run_clean
    assert status.success?, output
    assert_includes output, '工程类型：iOS'
    refute File.exist?(File.join(@root, 'build'))
    refute File.exist?(File.join(@root, 'DerivedData'))
    %w[Pods/source Podfile.lock Demo.xcodeproj/project.pbxproj].each { |p| assert File.exist?(File.join(@root, p)) }
    assert File.exist?(global)
  end

  def test_only_owned_xcode_derived_data_build_is_deleted
    ios
    own = File.join(@home, 'Library/Developer/Xcode/DerivedData/Demo-123')
    FileUtils.mkdir_p([File.join(own, 'Build'), File.join(own, 'SourcePackages')])
    File.write(File.join(own, 'Build/artifact'), 'generated')
    File.write(File.join(own, 'SourcePackages/keep'), 'dependency')
    # Generate a real plist without interpolating path text into XML.
    output, status = Open3.capture2e('/usr/bin/plutil', '-create', 'xml1', File.join(own, 'info.plist'))
    assert status.success?, output
    output, status = Open3.capture2e('/usr/bin/plutil', '-insert', 'WorkspacePath', '-string', File.join(@root, 'Demo.xcodeproj'), File.join(own, 'info.plist'))
    assert status.success?, output
    output, status = run_clean
    assert status.success?, output
    refute File.exist?(File.join(own, 'Build'))
    assert File.exist?(File.join(own, 'SourcePackages/keep'))
    assert File.exist?(File.join(own, 'info.plist'))
  end

  def test_unknown_java_gradle_and_macos_are_rejected_without_deleting
    file('build/keep')
    [nil, ['build.gradle', 'plugins { id("java") }'], ['Mac.xcodeproj/project.pbxproj', 'SDKROOT = macosx;']].each do |fixture|
      file(*fixture) if fixture
      output, status = run_clean
      refute status.success?, output
      assert File.exist?(File.join(@root, 'build/keep'))
    end
  end

  def test_no_ancestor_or_child_project_search
    flutter
    file('build/keep')
    file('lib/build/keep')
    output, status = run_clean('--yes', '', File.join(@root, 'lib'))
    refute status.success?, output
    assert File.exist?(File.join(@root, 'lib/build/keep'))
    output, status = run_clean('--yes', '', @temporary)
    refute status.success?, output
    assert File.exist?(File.join(@root, 'build/keep'))
  end

  def test_preview_cancel_eof_and_idempotence
    flutter
    file('build/artifact')
    [['--dry-run', ''], [nil, "no\n"], [nil, '']].each do |mode, input|
      run_clean(mode, input)
      assert File.exist?(File.join(@root, 'build/artifact'))
    end
    output, status = run_clean(nil, "CLEAN\n")
    assert status.success?, output
    refute File.exist?(File.join(@root, 'build'))
    output, status = run_clean
    assert status.success?, output
    assert_includes output, '没有可清理'
  end

  def test_link_target_rejected_before_any_deletion_and_internal_link_never_followed
    flutter
    outside = File.join(@temporary, 'outside')
    FileUtils.mkdir_p(outside)
    File.write(File.join(outside, 'keep'), 'safe')
    file('build/artifact')
    File.symlink(outside, File.join(@root, '.dart_tool'))
    output, status = run_clean
    refute status.success?, output
    assert File.exist?(File.join(@root, 'build/artifact'))
    File.unlink(File.join(@root, '.dart_tool'))
    File.symlink(outside, File.join(@root, 'build/link'))
    output, status = run_clean
    assert status.success?, output
    assert File.exist?(File.join(outside, 'keep'))
    refute File.exist?(File.join(@root, 'build'))
  end

  def test_file_named_build_is_never_deleted
    flutter
    file('build', 'user file')
    output, status = run_clean
    refute status.success?, output
    assert_equal 'user file', File.read(File.join(@root, 'build'))
  end
end
