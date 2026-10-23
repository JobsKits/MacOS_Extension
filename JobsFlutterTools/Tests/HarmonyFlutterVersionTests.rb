# frozen_string_literal: true
# 真实 zsh / JXA 隔离回归；Git、FVM、Homebrew、SDK 都是临时假命令，不安装真实工具。

require 'fileutils'
require 'json'
require 'minitest/autorun'
require 'open3'
require 'pty'
require 'tmpdir'

class HarmonyFlutterVersionTests < Minitest::Test
  SCRIPT = File.expand_path('../Scripts/Tools/ManageHarmonyFlutterVersion.zsh', __dir__)
  SHA = 'b' * 40
  TAG = '3.41.10-ohos-1.0.1'
  REPO = 'https://gitcode.com/CPF-Flutter/flutter_flutter.git'

  def setup
    @root = File.realpath(Dir.mktmpdir('jobs-harmony-sdk-'))
    @project = File.join(@root, "项目 空格 ' $(touch SHOULD_NOT_EXIST)")
    @bin = File.join(@root, 'bin')
    @run = File.join(@root, 'run')
    @cache = File.join(@root, 'Library/Caches/JobsFlutter/fvm/harmony')
    @trace = File.join(@root, 'trace')
    FileUtils.mkdir_p([@project, @bin, @run])
    File.write(File.join(@project, 'pubspec.yaml'), "name: example\ndependencies:\n  flutter:\n    sdk: flutter\n")
    @environment = {
      'HOME' => @root, 'TMPDIR' => @run + '/', 'PATH' => "#{@bin}:/usr/bin:/bin",
      'NO_COLOR' => '1', 'TERM' => 'dumb', 'FAKE_ROOT' => @root, 'FAKE_BIN' => @bin,
      'FAKE_PROJECT' => @project, 'FAKE_TRACE' => @trace, 'FAKE_SHA' => SHA, 'FAKE_REPO' => REPO
    }
    write_mock('git', <<~'ZSH')
      print -r -- "git|${(j: :)@}" >> "$FAKE_TRACE"
      while [[ "$1" == -c ]]; do shift 2; done
      if [[ "$1" == ls-remote ]]; then
        [[ "${FAKE_OFFLINE:-0}" != 1 ]] || exit 23
        print -- "${FAKE_SHA}\trefs/tags/3.41.10-ohos-1.0.1"
        print -- 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\trefs/tags/3.47.7+ohos-0.0.1-pre'
        print -- 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\trefs/tags/3.35.7+ohos-1.0.5'
        print -- 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\trefs/tags/evil;touch injected'
        exit 0
      fi
      if [[ "$1" == clone ]]; then
        [[ "${FAKE_CLONE_FAIL:-0}" != 1 ]] || exit 41
        local target="${@[-1]}"
        /bin/mkdir -p "$target/.git" "$target/bin"
        print -r -- "$FAKE_SHA" > "$target/.commit"
        /bin/cp "$FAKE_BIN/.flutter-template" "$target/bin/flutter"
        /bin/chmod +x "$target/bin/flutter"
        exit 0
      fi
      if [[ "$1" == -C ]]; then
        local target="$2"; shift 2
        case "$1" in
          checkout) exit 0 ;;
          rev-parse) /bin/cat "$target/.commit" ;;
          remote) print -r -- "${FAKE_WRONG_SOURCE:-$FAKE_REPO}" ;;
          status) [[ "${FAKE_DIRTY:-0}" != 1 ]] || print -r -- ' M packages/flutter/lib/widget.dart' ;;
          *) exit 3 ;;
        esac
        exit 0
      fi
      exit 4
    ZSH
    write_mock('.flutter-template', <<~'ZSH')
      print -r -- "sdk|${(j: :)@}" >> "$FAKE_TRACE"
      if [[ "$1" == --version ]]; then
        [[ "${FAKE_SDK_FAIL:-0}" != 1 ]] || exit 42
        print -r -- 'Flutter OH fixture'
      elif [[ "$1" == build && "$2" == -h ]]; then
        [[ "${FAKE_NO_HAP:-0}" == 1 ]] || print -r -- 'hap'
      else
        exit 5
      fi
    ZSH
    write_mock('fvm', <<~'ZSH')
      print -r -- "fvm|${(j: :)@}" >> "$FAKE_TRACE"
      case "$1" in
        --version) print -r -- '4.0.0' ;;
        use)
          if [[ "$2" == --help ]]; then print -r -- '--skip-pub-get --skip-setup'; exit 0; fi
          [[ "$PWD" != "$FAKE_PROJECT" ]] || exit 80
          /bin/mkdir -p .fvm/versions .vscode
          /bin/ln -sfn "$FVM_CACHE_PATH/versions/${2}" .fvm/flutter_sdk
          /bin/ln -sfn "$FVM_CACHE_PATH/versions/${2}" ".fvm/versions/$2"
          print -r -- "{\"flutter\":\"$2\"}" > .fvmrc
          print -r -- 'shadow IDE only' > .vscode/settings.json
          print -r -- 'shadow ignore only' > .gitignore
          if [[ "${FAKE_CONCURRENT:-0}" == 1 ]]; then
            print -r -- '{"flutter":"external-new-value"}' > "$FAKE_PROJECT/.fvmrc"
          fi
          [[ "${FAKE_USE_FAIL:-0}" != 1 ]] || exit 43
          [[ "${FAKE_WRONG_LINK:-0}" != 1 ]] || /bin/ln -sfn /tmp .fvm/flutter_sdk
          ;;
        *) exit 6 ;;
      esac
    ZSH
    FileUtils.cp(File.join(@bin, 'fvm'), File.join(@bin, '.fvm-template'))
    write_mock('brew', <<~'ZSH')
      print -r -- "brew|${(j: :)@}" >> "$FAKE_TRACE"
      case "$1" in
        --prefix) print -r -- "$FAKE_ROOT" ;;
        install)
          /bin/cp "$FAKE_BIN/.fvm-template" "$FAKE_BIN/fvm"
          /bin/chmod +x "$FAKE_BIN/fvm"
          ;;
        *) exit 7 ;;
      esac
    ZSH
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def test_check_is_local_read_only_and_never_calls_tools
    write_original_binding
    before = tree(@project)
    output, status = invoke('--check', input: '')
    assert status.success?, output
    assert_includes output, '当前绑定：3.35.7'
    assert_includes output, '本机没有带来源记录'
    assert_equal before, tree(@project)
    assert_empty Dir.children(@run)
    refute File.exist?(@trace)
  end

  def test_intro_cancel_and_eof_do_not_query_or_install
    ["cancel\n", ''].each do |input|
      output, status = invoke(input: input)
      refute status.success?, output
      refute File.exist?(@trace)
      assert_empty Dir.children(@run)
    end
  end

  def test_final_cancel_never_runs_fvm_brew_or_changes_project
    before = tree(@project)
    output, status = invoke(input: "\n\nNO\n")
    assert_equal 130, status.exitstatus, output
    assert_equal before, tree(@project)
    assert_includes trace, 'git|'
    refute_match(/fvm\||brew\||git\|clone/, trace)
    refute_includes output, 'evil;touch'
  end

  def test_success_from_no_fvm_project_uses_custom_cache_and_preserves_ide
    FileUtils.mkdir_p(File.join(@project, '.vscode'))
    File.write(File.join(@project, '.vscode/settings.json'), '{"fontSize":15}')
    File.write(File.join(@project, '.gitignore'), "build/\n")
    output, status = invoke
    assert status.success?, output
    config = JSON.parse(File.read(File.join(@project, '.fvmrc')))
    assert_equal "custom_jobs_ohos_#{SHA}", config['flutter']
    assert_equal @cache, config['cachePath']
    assert_equal REPO, config['flutterUrl']
    assert_equal "build/\n", File.read(File.join(@project, '.gitignore'))
    assert_equal '{"fontSize":15}', File.read(File.join(@project, '.vscode/settings.json'))
    assert_equal sdk_path, File.realpath(File.join(@project, '.fvm/flutter_sdk'))
    assert_equal sdk_path, File.realpath(File.join(@project, ".fvm/versions/custom_jobs_ohos_#{SHA}"))
    assert_equal TAG, JSON.parse(File.read(File.join(sdk_path, '.jobs-harmony-source.json')))['tag']
    assert_includes trace, '--skip-setup --skip-pub-get'
    refute_match(/fvm\|global|fvm\|fork|pub get|\.zshrc|\.zprofile/, trace)
    refute File.exist?(File.join(@project, '.jobs-harmony-fvm.lock'))
    refute File.exist?(File.join(@project, 'SHOULD_NOT_EXIST'))
  end

  def test_success_preserves_unknown_config_and_existing_preferences
    write_original_binding
    output, status = invoke
    assert status.success?, output
    config = JSON.parse(File.read(File.join(@project, '.fvmrc')))
    assert_equal true, config['updateVscodeSettings']
    assert_equal({ 'custom' => ['keep'] }, config['extra'])
    assert_equal 'original metadata', File.read(File.join(@project, '.fvm/note'))
  end

  def test_missing_fvm_install_is_after_explicit_confirmation
    FileUtils.rm(File.join(@bin, 'fvm'))
    output, status = invoke(input: "\n\nNO\n")
    refute status.success?, output
    refute_match(/brew\|install/, trace)
    output, status = invoke
    assert status.success?, output
    assert_includes trace, 'brew|install btwld/fvm/fvm'
    assert_operator output.index('来源地址：https://github.com/btwld/homebrew-fvm'), :<, output.index('✔ 项目已绑定')
  end

  def test_clone_and_sdk_failures_leave_original_binding_byte_identical
    write_original_binding
    before = tree(@project)
    %w[FAKE_CLONE_FAIL FAKE_SDK_FAIL].each do |flag|
      output, status = invoke(environment: { flag => '1' })
      refute status.success?, output
      assert_equal before, tree(@project)
      refute File.exist?(File.join(@project, '.jobs-harmony-fvm.lock'))
    end
  end

  def test_fvm_failure_or_wrong_link_only_changes_shadow
    write_original_binding
    before = tree(@project)
    %w[FAKE_USE_FAIL FAKE_WRONG_LINK].each do |flag|
      output, status = invoke(environment: { flag => '1' })
      refute status.success?, output
      assert_equal before, tree(@project)
    end
  end

  def test_concurrent_project_edit_is_preserved_and_publish_is_cancelled
    write_original_binding
    original_link = File.readlink(File.join(@project, '.fvm/flutter_sdk'))
    output, status = invoke(environment: { 'FAKE_CONCURRENT' => '1' })
    refute status.success?, output
    assert_includes output, '准备期间项目绑定已被修改'
    assert_equal 'external-new-value', JSON.parse(File.read(File.join(@project, '.fvmrc')))['flutter']
    assert_equal original_link, File.readlink(File.join(@project, '.fvm/flutter_sdk'))
  end

  def test_existing_project_lock_stops_without_fvm_or_download
    FileUtils.mkdir(File.join(@project, '.jobs-harmony-fvm.lock'))
    output, status = invoke
    refute status.success?, output
    assert_includes output, '操作锁'
    refute_match(/fvm\||brew\||git\|clone/, trace)
    assert File.directory?(File.join(@project, '.jobs-harmony-fvm.lock'))
  end

  def test_cache_symlink_is_rejected_before_download
    FileUtils.mkdir_p(File.join(@root, 'elsewhere'))
    File.symlink(File.join(@root, 'elsewhere'), File.join(@root, 'Library'))
    output, status = invoke('--check', input: '')
    assert status.success?, output
    refute File.exist?(@trace)
    assert_empty Dir.children(File.join(@root, 'elsewhere'))
    output, status = invoke
    refute status.success?, output
    assert_includes output, '缓存路径不是普通目录'
    refute_includes trace, 'git|clone'
    assert_empty Dir.children(File.join(@root, 'elsewhere'))
  end

  def test_offline_uses_recorded_local_cache_and_rejects_wrong_source
    create_cached_sdk
    output, status = invoke(environment: { 'FAKE_OFFLINE' => '1' })
    assert status.success?, output
    assert_includes output, '只提供带来源记录的本机缓存'
    refute_includes trace, 'git|clone'
    output, status = invoke(environment: { 'FAKE_OFFLINE' => '1', 'FAKE_WRONG_SOURCE' => 'https://example.invalid/fork.git' })
    refute status.success?, output
    assert_includes output, '缓存来源 / commit / 源码状态不符'
  end

  def test_parser_reuses_menu_detector_for_flow_yaml_and_rejects_comment_only
    File.write(File.join(@project, 'pubspec.yaml'), "name: sample\ndependencies: {flutter: {sdk: flutter}}\n")
    output, status = invoke('--check', input: '')
    assert status.success?, output
    File.write(File.join(@project, 'pubspec.yaml'), "name: sample\n# dependencies:\n#   flutter:\n#     sdk: flutter\n")
    output, status = invoke('--check', input: '')
    refute status.success?, output
    refute File.exist?(@trace)
  end

  def test_symlinked_project_config_and_real_sdk_directory_are_preserved
    external = File.join(@root, 'external.json')
    File.write(external, '{}')
    File.symlink(external, File.join(@project, '.fvmrc'))
    output, status = invoke('--check', input: '')
    refute status.success?, output
    assert_equal '{}', File.read(external)
    FileUtils.rm(File.join(@project, '.fvmrc'))
    FileUtils.mkdir_p(File.join(@project, '.fvm/flutter_sdk'))
    output, status = invoke('--check', input: '')
    refute status.success?, output
    assert_includes output, '真实目录'
  end

  def test_fzf_selects_first_row_and_escape_cancels_without_tools
    write_mock('fzf', <<~'ZSH')
      print -r -- 'fzf|select' >> "$FAKE_TRACE"
      [[ "${FAKE_FZF_CANCEL:-0}" != 1 ]] || exit 130
      /usr/bin/head -n 1
    ZSH
    output, status = invoke_tty("\nYES\n")
    assert status.success?, output
    assert_includes trace, 'fzf|select'
    assert_includes output, "✔ 项目已绑定 Flutter OH #{TAG}"
    FileUtils.rm(@trace)
    output, status = invoke_tty("\n", 'FAKE_FZF_CANCEL' => '1')
    assert_equal 130, status.exitstatus, output
    refute_match(/fvm\||brew\||git\|clone/, trace)
  end

  def test_failed_publish_restores_original_file_identity
    write_original_binding
    identity = File.stat(File.join(@project, '.fvmrc')).ino
    original = File.read(File.join(@project, '.fvmrc'))
    output, status = invoke_recovery(false)
    assert_equal 27, status.exitstatus, output
    assert_equal original, File.read(File.join(@project, '.fvmrc'))
    assert_equal identity, File.stat(File.join(@project, '.fvmrc')).ino
    assert_includes output, '原项目绑定已恢复'
  end

  def test_rollback_conflict_preserves_external_file_and_backup
    write_original_binding
    output, status = invoke_recovery(true)
    refute status.success?, output
    assert_includes output, '恢复发现并发修改'
    assert_equal "external after publish\n", File.read(File.join(@project, '.fvmrc'))
    assert File.file?(File.join(@root, 'recovery/displaced/.fvmrc'))
  end

  def test_control_character_path_is_rejected_without_changes
    bad = File.join(@root, "bad\nproject")
    FileUtils.mkdir(bad)
    output, status = Open3.capture2e(@environment, '/bin/zsh', SCRIPT, '--project', bad, '--check')
    refute status.success?, output
    assert_includes output, '路径含控制字符'
    refute File.exist?(@trace)
  end

  private

  def invoke(*arguments, input: "\n\nYES\n", environment: {})
    Open3.capture2e(@environment.merge(environment), '/bin/zsh', SCRIPT, '--project', @project, *arguments, stdin_data: input)
  end

  def invoke_tty(input, environment = {})
    output = +''
    status = nil
    PTY.spawn(@environment.merge(environment), '/bin/zsh', SCRIPT, '--project', @project) do |reader, writer, pid|
      writer.write(input)
      writer.flush
      begin
        loop { output << reader.readpartial(4096) }
      rescue Errno::EIO, EOFError
        # macOS PTY 在子进程退出时返回 EIO。
      end
      Process.wait(pid)
      status = $CHILD_STATUS || $?
    end
    [output.force_encoding(Encoding::UTF_8), status]
  end

  def invoke_recovery(concurrent)
    source = File.read(SCRIPT).sub(/^main "\$@"\s*\z/, '')
    source += <<~'ZSH'
      FH_PROJECT="$FAKE_PROJECT"
      FH_RUN="$FAKE_ROOT/recovery"
      /bin/mkdir -p "$FH_RUN/before" "$FH_RUN/displaced" "$FH_RUN/produced"
      FH_LOG="$FH_RUN/action.log"
      /bin/cp "$FH_PROJECT/.fvmrc" "$FH_RUN/before/.fvmrc"
      /bin/mv "$FH_PROJECT/.fvmrc" "$FH_RUN/displaced/.fvmrc"
      print -r -- 'produced by this run' > "$FH_PROJECT/.fvmrc"
      FH_EXPECTED_CONFIG="$(fh_data fingerprint "$FH_PROJECT/.fvmrc")"
      FH_CHANGED=(.fvmrc)
      FH_MUTATED=1
      [[ "$FAKE_ROLLBACK_CONCURRENT" != 1 ]] || print -r -- 'external after publish' > "$FH_PROJECT/.fvmrc"
      fh_finish 27
    ZSH
    Open3.capture2e(@environment.merge('FAKE_ROLLBACK_CONCURRENT' => concurrent ? '1' : '0'), '/bin/zsh', '-c', source)
  end

  def write_mock(name, body)
    path = File.join(@bin, name)
    File.write(path, "#!/bin/zsh\n#{body}")
    FileUtils.chmod(0o755, path)
  end

  def trace
    File.exist?(@trace) ? File.read(@trace) : ''
  end

  def sdk_path
    File.join(@cache, "versions/custom_jobs_ohos_#{SHA}")
  end

  def create_cached_sdk
    FileUtils.mkdir_p([File.join(sdk_path, '.git'), File.join(sdk_path, 'bin')])
    File.write(File.join(sdk_path, '.commit'), SHA)
    FileUtils.cp(File.join(@bin, '.flutter-template'), File.join(sdk_path, 'bin/flutter'))
    File.write(File.join(sdk_path, '.jobs-harmony-source.json'), JSON.generate({ tag: TAG, commit: SHA, repo: REPO }))
  end

  def write_original_binding
    old_sdk = File.join(@root, 'old sdk')
    FileUtils.mkdir_p([old_sdk, File.join(@project, '.fvm')])
    File.symlink(old_sdk, File.join(@project, '.fvm/flutter_sdk'))
    File.write(File.join(@project, '.fvm/note'), 'original metadata')
    File.write(File.join(@project, '.fvmrc'), JSON.generate({ flutter: '3.35.7', updateVscodeSettings: true, extra: { custom: ['keep'] } }))
  end

  def tree(root)
    Dir.glob(File.join(root, '**', '*'), File::FNM_DOTMATCH).reject { |p| %w[. ..].include?(File.basename(p)) }.sort.map do |path|
      [path.delete_prefix(root), File.symlink?(path) ? [:link, File.readlink(path)] : File.file?(path) ? [:file, File.binread(path)] : [:directory]]
    end
  end
end
