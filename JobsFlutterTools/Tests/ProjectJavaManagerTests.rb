# frozen_string_literal: true
# 隔离 Java / jEnv / Homebrew，验证项目声明、取消、失败恢复和 Gradle 进程环境。
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'shellwords'
require 'pty'

class ProjectJavaManagerTests < Minitest::Test
  SCRIPT = File.expand_path('../Scripts/Tools/ManageProjectJava.zsh', __dir__)
  PACKAGE = File.expand_path('../Scripts/Tools/PackageFlutter.zsh', __dir__)
  RUNNER = File.expand_path('../Scripts/Tools/FlutterRunner.jxa', __dir__)

  def setup
    @root = File.realpath(Dir.mktmpdir('project-java-fixture-'))
    @project = File.join(@root, '中文 Project $(touch INJECTED) `touch BACKTICK`')
    @bin = File.join(@root, 'bin')
    @home = File.join(@root, 'home')
    @run = File.join(@root, 'run')
    @jdk = File.join(@root, 'JDK 中文 空格')
    @brew_prefix = File.join(@root, 'brew')
    @trace = File.join(@root, 'trace')
    FileUtils.mkdir_p([@project, @bin, @home, @run, @brew_prefix])
    File.write(File.join(@project, 'pubspec.yaml'), "name: fixture\ndependencies:\n  flutter:\n    sdk: flutter\n")
    create_jdk(@jdk, '17.0.17')
    @env = { 'HOME' => @home, 'TMPDIR' => @run, 'PATH' => "#{@bin}:/usr/bin:/bin:/usr/sbin:/sbin",
             'JAVA_HOME' => @jdk, 'JT_JDK_HOME' => @jdk, 'JT_TRACE' => @trace,
             'JT_BREW_PREFIX' => @brew_prefix, 'JT_STATE' => File.join(@root, 'state'),
             'NO_COLOR' => '1', 'TERM' => 'dumb', 'JENV_VERSION' => nil, 'GRADLE_OPTS' => nil }
    FileUtils.mkdir_p(@env['JT_STATE'])
    File.write(File.join(@env['JT_STATE'], 'jenv-installed'), '')
    write_mock('jenv', <<~'ZSH')
      print -r -- "jenv|$*|${JENV_VERSION:-}|$PWD" >> "$JT_TRACE"
      case "$1" in
        --version) [[ -e "$JT_STATE/jenv-installed" ]] || exit 69; print 'jenv 0.6.0' ;;
        versions) print '17'; print '17.0.17'; [[ ! -f "$JT_STATE/alias" ]] || cat "$JT_STATE/alias" ;;
        prefix)
          case "$JENV_VERSION" in
            17|17.0.17) [[ "${JT_NO_ALIAS:-0}" != 1 ]] || exit 1; print -r -- "$JT_JDK_HOME" ;;
            *) [[ -f "$JT_STATE/alias" && "$(cat "$JT_STATE/alias")" == "$JENV_VERSION" ]] || exit 1; cat "$JT_STATE/jdk" ;;
          esac ;;
        add) print -r -- "$2" > "$JT_STATE/alias"; print -r -- "$3" > "$JT_STATE/jdk" ;;
        local)
          [[ "$PWD" == "$JT_PROJECT" ]] || exit 89
          print -r -- "$2" > .java-version
          if [[ "${JT_LOCAL_MODE:-}" == conflict ]]; then print '21' > .java-version; exit 47; fi
          if [[ "${JT_LOCAL_MODE:-}" == interrupt ]]; then kill -INT "$PPID"; sleep 0.2; exit 130; fi
          exit "${JT_LOCAL_EXIT:-0}" ;;
        *) exit 91 ;;
      esac
    ZSH
    write_mock('brew', <<~'ZSH')
      print -r -- "brew|$*" >> "$JT_TRACE"
      case "$1" in
        --version) print 'Homebrew fixture' ;;
        --prefix)
          if [[ $# == 1 ]]; then print -r -- "$JT_BREW_PREFIX"; else print -r -- "$JT_BREW_PREFIX/opt/$2"; fi ;;
        install)
          [[ "${JT_BREW_EXIT:-0}" == 0 ]] || exit "$JT_BREW_EXIT"
          if [[ "$3" == jenv ]]; then touch "$JT_STATE/jenv-installed"; else
            target="$JT_BREW_PREFIX/opt/$3/libexec/openjdk.jdk/Contents/Home"
            mkdir -p "$target/bin"
            cp "$JT_INSTALL_JDK/bin/java" "$JT_INSTALL_JDK/bin/javac" "$target/bin/"
          fi ;;
        *) exit 92 ;;
      esac
    ZSH
    @env['JT_PROJECT'] = @project
    tools = File.join(@root, 'tools')
    FileUtils.mkdir_p(tools)
    @package_library = File.join(tools, 'PackageFlutter.zsh')
    File.write(@package_library, File.read(PACKAGE).sub(/^main "\$@"\s*\z/, ''))
    FileUtils.cp(SCRIPT, tools)
    FileUtils.cp(File.join(File.dirname(SCRIPT), 'CleanBuildArtifacts.zsh'), tools)
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def write_mock(name, body)
    target = name.start_with?('/') ? name : File.join(@bin, name)
    FileUtils.mkdir_p(File.dirname(target))
    File.write(target, "#!/bin/zsh\n#{body}\n")
    FileUtils.chmod(0o755, target)
  end

  def create_jdk(target, version)
    write_mock(File.join(target, 'bin/java'), "print -u2 'openjdk version \"#{version}\"'; print -u2 'OpenJDK 64-Bit Server VM'")
    write_mock(File.join(target, 'bin/javac'), "print -u2 'javac #{version}'")
  end

  def shell(code, env: {})
    Open3.capture3(@env.merge(env), '/bin/zsh', '-c', "source #{SCRIPT.shellescape}\npj_system_jdk_homes() { return 0; }\n#{code}", chdir: @root)
  end

  def interactive(input, env: {}, prefix: '')
    output = +''
    process_status = nil
    code = "source #{SCRIPT.shellescape}\npj_system_jdk_homes() { return 0; }\n#{prefix}\nmain --project #{Shellwords.escape(@project)}"
    PTY.spawn(@env.merge(env), '/bin/zsh', '-c', code, chdir: @root) do |reader, writer, pid|
      writer.write(input)
      writer.flush
      begin
        loop { output << reader.readpartial(4096) }
      rescue EOFError, Errno::EIO
        # Darwin PTY closes the stream with EIO after child exit.
      end
      _, process_status = Process.wait2(pid)
    end
    [output.force_encoding('UTF-8'), process_status]
  end

  def config
    File.join(@project, '.java-version')
  end

  def calls
    File.exist?(@trace) ? File.read(@trace) : ''
  end

  def test_source_has_no_execution_or_environment_changes
    out, err, status = shell('print -r -- "${JAVA_HOME}|${GRADLE_OPTS-unset}|${PJ_LOG_FILE}"')
    assert status.success?, out + err
    assert_equal "#{@jdk}|unset|\n", out
    assert_empty calls
    assert_empty Dir.children(@run)
  end

  def test_check_is_read_only_and_resolves_numeric_and_full_jenv_alias
    %w[17 17.0.17].each do |version|
      File.write(config, "#{version}\n")
      before = File.stat(config)
      out, err, status = Open3.capture3(@env, '/bin/zsh', SCRIPT, '--project', @project, '--check', chdir: @root)
      assert status.success?, out + err
      assert_includes out, 'java / javac 主版本：17'
      assert_equal before.mtime, File.mtime(config)
      assert_empty Dir.children(@run)
      refute_includes calls, 'brew|'
      refute_includes calls, 'jenv|add'
      refute_includes calls, 'jenv|local'
    end
  end

  def test_cancel_before_final_confirmation_does_not_mutate
    File.write(config, "17\n")
    out, status = interactive("\nq\n")
    assert_equal 130, status.exitstatus, out
    assert_equal "17\n", File.read(config)
    refute_includes calls, 'brew|install'
    refute_includes calls, 'jenv|local'
    out, status = interactive("\n1\nCANCEL\n")
    assert_equal 130, status.exitstatus, out
    refute_includes calls, 'jenv|local'
  end

  def test_existing_jdk_switch_uses_only_selected_project_and_does_not_install
    File.write(config, "17\n")
    out, status = interactive("\n1\n\n")
    assert status.success?, out
    assert_equal "17.0.17\n", File.read(config)
    refute_includes calls, 'brew|'
    refute_includes calls, 'jenv|global'
    refute File.exist?(File.join(@project, '.java-version.jobs-lock'))
    %w[INJECTED BACKTICK JAVA_INJECTED JAVA_BACKTICK].each { |name| refute File.exist?(File.join(@root, name)) }
  end

  def test_missing_jenv_and_jdk_are_installed_once_from_brew
    install_jdk = File.join(@root, 'install-jdk')
    create_jdk(install_jdk, '21.0.9')
    FileUtils.rm_f(File.join(@env['JT_STATE'], 'jenv-installed'))
    # Only the fixture command may count as jEnv; host tools must not participate.
    override = 'pj_find_jenv() { PJ_JENV=""; if "$HOME/../bin/jenv" --version >/dev/null 2>&1; then PJ_JENV="$HOME/../bin/jenv"; return 0; fi; return 1; }'
    out, status = interactive("\nn\n21\n\n", prefix: override, env: { 'JT_INSTALL_JDK' => install_jdk, 'JT_NO_ALIAS' => '1' })
    assert status.success?, out
    assert_equal 1, calls.scan('brew|install --formula jenv').length
    assert_equal 1, calls.scan('brew|install --formula openjdk@21').length
    assert_match(/\Ajobs-21\.0\.9-[a-f0-9]{12}\n\z/, File.read(config))
    assert_operator out.index('来源｜安装'), :<, out.index('✔ 已绑定项目 Java')
  end

  def test_brew_failure_keeps_exit_code_and_original_config
    File.write(config, "17\n")
    out, status = interactive("\nn\n21\n\n", env: { 'JT_BREW_EXIT' => '43' })
    assert_equal 43, status.exitstatus, out
    assert_equal "17\n", File.read(config)
    refute_includes calls, 'jenv|local'
  end

  def test_missing_jenv_reuses_healthy_jdk_without_reinstalling_it
    FileUtils.rm_f(File.join(@env['JT_STATE'], 'jenv-installed'))
    override = 'pj_find_jenv() { PJ_JENV=""; if "$HOME/../bin/jenv" --version >/dev/null 2>&1; then PJ_JENV="$HOME/../bin/jenv"; return 0; fi; return 1; }'
    out, status = interactive("\n1\n\n", prefix: override)
    assert status.success?, out
    assert_equal 1, calls.scan('brew|install --formula jenv').length
    refute_includes calls, 'brew|install --formula openjdk'
  end

  def test_installed_jdk_is_rechecked_and_wrong_version_stops_before_local_write
    install_jdk = File.join(@root, 'wrong-install-jdk')
    create_jdk(install_jdk, '22.0.1')
    File.write(config, "17\n")
    out, status = interactive("\nn\n21\n\n", env: { 'JT_INSTALL_JDK' => install_jdk })
    refute status.success?, out
    assert_includes out, '安装后的 JDK 主版本与选择不一致'
    assert_equal "17\n", File.read(config)
    refute_includes calls, 'jenv|local'
  end

  def test_concurrent_change_before_write_is_preserved
    File.write(config, "17\n")
    override = 'pj_confirm_selection() { print 21 > "$PJ_PROJECT/.java-version"; }'
    out, status = interactive("\n1\n", prefix: override)
    refute status.success?, out
    assert_includes out, '在选择期间发生变化'
    assert_equal "21\n", File.read(config)
    refute_includes calls, 'jenv|local'
    refute File.exist?(File.join(@project, '.java-version.jobs-lock'))
  end

  def test_local_failure_restores_original_and_removes_lock
    File.write(config, "17\n")
    out, status = interactive("\n1\n\n", env: { 'JT_LOCAL_EXIT' => '47' })
    assert_equal 47, status.exitstatus, out
    assert_equal "17\n", File.read(config)
    assert_includes out, '已恢复原 .java-version'
    refute File.exist?(File.join(@project, '.java-version.jobs-lock'))
  end

  def test_local_failure_restores_absence_and_preserves_concurrent_changes
    out, status = interactive("\n1\n\n", env: { 'JT_LOCAL_EXIT' => '47' })
    assert_equal 47, status.exitstatus, out
    refute File.exist?(config)
    File.write(config, "17\n")
    out, status = interactive("\n1\n\n", env: { 'JT_LOCAL_MODE' => 'conflict' })
    assert_equal 47, status.exitstatus, out
    assert_equal "21\n", File.read(config)
    assert_includes out, '可能存在并发编辑'
  end

  def test_interruption_restores_original_config
    File.write(config, "17\n")
    out, status = interactive("\n1\n\n", env: { 'JT_LOCAL_MODE' => 'interrupt' })
    assert_equal 130, status.exitstatus, out
    assert_equal "17\n", File.read(config)
    refute File.exist?(File.join(@project, '.java-version.jobs-lock'))
  end

  def test_invalid_config_and_symlink_are_rejected_without_execution
    File.write(config, "$(touch INJECTED)\n")
    out, err, status = shell("PJ_PROJECT=#{@project.shellescape}; pj_read_config")
    refute status.success?, out + err
    refute File.exist?(File.join(@root, 'INJECTED'))
    FileUtils.rm_f(config)
    victim = File.join(@root, 'victim')
    File.write(victim, "17\n")
    File.symlink(victim, config)
    out, err, status = shell("PJ_PROJECT=#{@project.shellescape}; pj_read_config")
    refute status.success?, out + err
    assert_equal "17\n", File.read(victim)
  end

  def test_binder_no_declaration_preserves_environment_and_jre_is_rejected
    out, err, status = shell("pj_bind_project_java #{@project.shellescape}; print -r -- \"$JAVA_HOME|${GRADLE_OPTS-unset}\"")
    assert status.success?, out + err
    assert_equal "#{@jdk}|unset\n", out
    File.write(config, "17\n")
    FileUtils.rm_f(File.join(@jdk, 'bin/javac'))
    out, err, status = shell("pj_bind_project_java #{@project.shellescape}")
    refute status.success?, out + err
  end

  def test_gradle_criteria_conflict_is_not_reported_as_bound
    File.write(config, "17\n")
    criteria = File.join(@project, 'android/gradle/gradle-daemon-jvm.properties')
    FileUtils.mkdir_p(File.dirname(criteria))
    File.write(criteria, 'toolchainVersion=21')
    out, err, status = shell("pj_bind_project_java #{@project.shellescape}")
    refute status.success?, out + err
    assert_includes out, 'JVM criteria 优先于项目 Java 选择'
    refute_includes calls, 'jenv|local'
  end

  def test_gradle_opts_keep_literal_special_path_and_packager_does_not_replace_declared_java
    File.write(config, "17\n")
    code = "source #{@package_library.shellescape}\nFP_PROJECT=#{@project.shellescape}; FP_LOG_FILE=/dev/null; fp_check_java17 || exit $?\nprint -r -- \"$JAVA_HOME\"\neval \"set -- $GRADLE_OPTS\"\nprint -r -- \"$1\"\nprint -r -- \"$GRADLE_OPTS\" | /usr/bin/xargs -n1"
    out, err, status = shell(code)
    assert status.success?, out + err
    assert_includes out, "-Dorg.gradle.java.home=#{@jdk}"
    refute File.exist?(File.join(@root, 'JAVA_INJECTED'))
    refute File.exist?(File.join(@root, 'JAVA_BACKTICK'))
    assert_includes File.read(RUNNER), "'JAVA_HOME', 'GRADLE_OPTS'"
  end

  def test_binder_rejects_jdk_paths_that_gradle_wrappers_interpret_inconsistently
    special_jdk = File.join(@root, 'JDK $(touch JAVA_INJECTED) `touch JAVA_BACKTICK`')
    create_jdk(special_jdk, '17.0.17')
    File.write(config, "17\n")
    out, err, status = shell("pj_bind_project_java #{@project.shellescape}", env: { 'JAVA_HOME' => special_jdk, 'JT_JDK_HOME' => special_jdk })
    refute status.success?, out + err
    assert_includes out, '无法兼容各代 Gradle wrapper'
    refute File.exist?(File.join(@root, 'JAVA_INJECTED'))
    refute File.exist?(File.join(@root, 'JAVA_BACKTICK'))
  end
end
