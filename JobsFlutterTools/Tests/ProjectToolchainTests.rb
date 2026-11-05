# frozen_string_literal: true
# Created by Jobs on 2026年11月4日，星期三。
# 隔离目录、已有 Node 和假安装器验证工具链准备；不联网、不安装真实软件、不操作系统配置。
require 'fileutils'
require 'digest'
require 'json'
require 'minitest/autorun'
require 'open3'
require 'shellwords'
require 'tmpdir'

class ProjectToolchainTests < Minitest::Test
  TOOLS = File.expand_path('../Scripts/Tools', __dir__)
  HELPER = File.join(TOOLS, '【MacOS】工程依赖工具链.zsh/【MacOS】工程依赖工具链.zsh')

  def setup
    @root = File.realpath(Dir.mktmpdir('jobs-project-toolchain-'))
    @project = File.join(@root, 'project 中文')
    @bin = File.join(@root, 'bin')
    @run = File.join(@root, 'run')
    @home = File.join(@root, 'home')
    @tool = File.join(@root, 'DevEco.app/Contents')
    @trace = File.join(@root, 'trace')
    FileUtils.mkdir_p([@project, @bin, @run, @home])
    File.write(File.join(@project, 'package.json'), '{}')
    @node = ['/opt/homebrew/bin/node', '/usr/local/bin/node'].find { |p| File.executable?(p) }
    @npm = @node && File.join(File.dirname(@node), 'npm')
    @env = { 'HOME' => @home, 'PATH' => "#{@bin}:/usr/bin:/bin:/usr/sbin:/sbin", 'PT_TEST_PROJECT' => @project,
             'PT_TEST_RUN' => @run, 'PT_TEST_TOOLS' => TOOLS, 'PT_TEST_HELPER' => HELPER, 'PT_TEST_TRACE' => @trace,
             'PT_TEST_NODE' => @node.to_s, 'PT_TEST_NPM' => @npm.to_s, 'PT_TEST_ROOT' => @root,
             'DEVECO_STUDIO_HOME' => '', 'TOOL_HOME' => '', 'DEVECO_SDK_HOME' => '', 'HOS_SDK_HOME' => '',
             'OHOS_SDK_HOME' => '', 'NODE_HOME' => '', 'JAVA_HOME' => '' }
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def command(path, body)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "#!/bin/zsh\n#{body}\n")
    File.chmod(0o755, path)
  end

  def shell(body, env: {}, input: '')
    bootstrap = <<~'ZSH'
      source "$PT_TEST_TOOLS/ProjectEnvironment.zsh" || exit $?
      source "$PT_TEST_HELPER" || exit $?
      SF_PROJECT="$PT_TEST_PROJECT" PE_RUN_DIR="$PT_TEST_RUN" PE_TOOLS_DIR="$PT_TEST_TOOLS"
      PE_LOG_FILE="$PE_RUN_DIR/environment.log"
      pe_select() { PE_SELECTION="${PT_TEST_CHOICE:-stop}"; }
      jobs_sdk_retry() { shift 2; "$@"; }
      sf_run_diagnostic() {
        local name="$1" result=0; shift
        print -r -- "$name|$*" >> "$PT_TEST_TRACE"
        if [[ "$name" == node-shasums || "$name" == node-download ]]; then
          local destination="" parameter="" previous=""
          for parameter in "$@"; do [[ "$previous" != --output ]] || destination="$parameter"; previous="$parameter"; done
          [[ -n "$destination" ]] || return 97
          if [[ "$name" == node-shasums ]]; then /bin/cp "$PT_TEST_SHASUMS" "$destination"; else /bin/cp "$PT_TEST_ARCHIVE" "$destination"; fi
          return $?
        fi
        [[ "$1" != /usr/bin/curl && "$1" != /usr/bin/open ]] || return 98
        if [[ "$name" == *-install && "${1:A}" == "${PT_TEST_NPM:A}" ]]; then return 98; fi
        (cd "${SF_COMMAND_DIRECTORY:-$SF_PROJECT}" && "$@") > "$PE_RUN_DIR/$name.log" 2>&1 || result=$?
        return "$result"
      }
    ZSH
    Open3.capture3(@env.merge(env), '/bin/zsh', '-f', '-c', bootstrap + body, stdin_data: input)
  end

  def assert_success(result)
    out, err, status = result
    assert status.success?, out + err
    result
  end

  def native_node
    skip '需要已有 Node/npm；测试不安装它们' unless @node && File.executable?(@npm)
    File.symlink(@node, File.join(@bin, 'node'))
    File.symlink(@npm, File.join(@bin, 'npm'))
  end

  def ohos_toolchain
    %w[ets native toolchains].each { |part| FileUtils.mkdir_p(File.join(@tool, 'sdk/default/openharmony', part)) }
    { 'node/bin/node' => "print v22.11.0", 'ohpm/bin/ohpm' => 'print 5.0.0',
      'hvigor/bin/hvigorw' => 'echo 5.0.0', 'sdk/default/openharmony/toolchains/hdc' => 'print 3.1.0',
      'jbr/Contents/Home/bin/java' => 'print 21.0.0' }.each { |p, body| command(File.join(@tool, p), body) }
    FileUtils.mkdir_p(File.join(@project, 'ohos'))
    command(File.join(@bin, 'flutter'), 'print "Harmony HAP build help"')
  end

  def test_native_node_engine_and_version_file_are_checked_without_install
    native_node
    version, = Open3.capture2(@node, '-p', 'process.versions.node')
    major = version.split('.').first
    File.write(File.join(@project, 'package.json'), JSON.generate('engines' => { 'node' => ">=#{major}.0.0 <#{major.to_i + 1}.0.0" }))
    File.write(File.join(@project, '.nvmrc'), version)
    assert_success shell('pt_read_node_requirements "$SF_PROJECT" && pt_probe_node "$(command -v node)"')
    refute File.read(@trace).include?('install')
    File.write(File.join(@project, '.nvmrc'), '1.0.0')
    _, _, status = shell('pt_read_node_requirements "$SF_PROJECT" && pt_probe_node "$(command -v node)"')
    assert_equal 3, status.exitstatus
  end

  def test_locked_package_manager_must_match_lock_type_before_install
    native_node
    File.write(File.join(@project, 'package.json'), '{"packageManager":"yarn@4.9.0"}')
    _, _, status = shell('pt_prepare_web_toolchain "$SF_PROJECT" pnpm-lock.yaml')
    assert_equal 3, status.exitstatus
    refute File.read(@trace).include?(' install ')
  end

  def test_missing_exact_package_manager_is_installed_only_in_user_version_directory_and_verified
    native_node
    File.delete(File.join(@bin, 'npm'))
    command(File.join(@bin, 'npm'), <<~'ZSH')
      [[ "$1" != --version ]] || { print 10.0.0; exit 0; }
      [[ "$1" == install && "$2" == --prefix ]] || exit 90
      /bin/mkdir -p "$3/node_modules/.bin"
      /usr/bin/printf '#!/bin/zsh\nprint 9.15.4\n' > "$3/node_modules/.bin/pnpm"
      /bin/chmod 755 "$3/node_modules/.bin/pnpm"
    ZSH
    File.write(File.join(@project, 'package.json'), '{"packageManager":"pnpm@9.15.4"}')
    assert_success shell('pt_prepare_web_toolchain "$SF_PROJECT" pnpm-lock.yaml; result=$?; print -r -- "$PT_PACKAGE_MANAGER"; exit "$result"', env: { 'PT_TEST_CHOICE' => 'install' })
    installed = File.join(@home, 'Library/Application Support/JobsFlutterTools/package-managers/pnpm/9.15.4/node_modules/.bin/pnpm')
    assert File.executable?(installed)
    trace = File.read(@trace)
    assert_includes trace, 'pnpm@9.15.4'
    refute_includes trace, '--global'
    refute File.exist?(File.join(@project, 'node_modules'))
  end

  def test_install_failure_and_failed_post_install_health_stop_the_chain
    native_node
    File.delete(File.join(@bin, 'npm'))
    command(File.join(@bin, 'npm'), '[[ "$1" != --version ]] || { print 10.0.0; exit 0; }; exit 47')
    File.write(File.join(@project, 'package.json'), '{"packageManager":"pnpm@9.15.4"}')
    _, _, status = shell('pt_prepare_web_toolchain "$SF_PROJECT" pnpm-lock.yaml && touch "$PT_TEST_ROOT/BUSINESS"', env: { 'PT_TEST_CHOICE' => 'install' })
    assert_equal 47, status.exitstatus
    refute File.exist?(File.join(@root, 'BUSINESS'))
    command(File.join(@bin, 'npm'), <<~'ZSH')
      [[ "$1" != --version ]] || { print 10.0.0; exit 0; }
      /bin/mkdir -p "$3/node_modules/.bin"
      /usr/bin/printf '#!/bin/zsh\nprint 99.0.0\n' > "$3/node_modules/.bin/pnpm"
      /bin/chmod 755 "$3/node_modules/.bin/pnpm"
    ZSH
    _, _, status = shell('pt_prepare_web_toolchain "$SF_PROJECT" pnpm-lock.yaml && touch "$PT_TEST_ROOT/BUSINESS"', env: { 'PT_TEST_CHOICE' => 'install' })
    assert_equal 3, status.exitstatus
    refute File.exist?(File.join(@root, 'BUSINESS'))
  end

  def test_cancel_missing_tool_does_not_install_or_start_business
    native_node
    File.write(File.join(@project, '.nvmrc'), '1.0.0')
    _, _, status = shell('pt_prepare_web_toolchain "$SF_PROJECT" pnpm-lock.yaml && touch "$PT_TEST_ROOT/BUSINESS"')
    assert_equal 3, status.exitstatus
    refute File.exist?(File.join(@root, 'BUSINESS'))
    refute File.exist?(File.join(@home, 'Library'))
  end

  def test_ohos_discovers_selected_studio_and_activates_complete_toolchain_in_same_process
    ohos_toolchain
    out, = assert_success shell(<<~'ZSH', env: { 'DEVECO_STUDIO_HOME' => File.dirname(@tool) })
      SF_FLUTTER="$(command -v flutter)"
      pt_prepare_ohos_toolchain || exit $?
      print -r -- "$OHOS_SDK_HOME|$DEVECO_SDK_HOME|$PT_OHPM|$PT_HVIGOR|$SF_JAVA_HOME"
    ZSH
    assert_includes out, File.join(@tool, 'sdk/default/openharmony')
    %w[ohos-node ohpm-version hvigor-version hdc-version ohos-java ohos-sdk].each { |name| assert_includes File.read(@trace), name }
    refute File.exist?(File.join(@home, '.zshrc'))
  end

  def test_ohos_missing_sdk_component_never_executes_package_tools
    ohos_toolchain
    FileUtils.remove_entry(File.join(@tool, 'sdk/default/openharmony/native'))
    _, _, status = shell('SF_FLUTTER="$(command -v flutter)"; pt_prepare_ohos_toolchain && touch "$PT_TEST_ROOT/BUSINESS"', env: { 'DEVECO_STUDIO_HOME' => @tool })
    assert_equal 3, status.exitstatus
    refute File.exist?(@trace)
    refute File.exist?(File.join(@root, 'BUSINESS'))
  end

  def test_ohos_unhealthy_tool_requires_repair_and_does_not_run_business
    ohos_toolchain
    command(File.join(@tool, 'ohpm/bin/ohpm'), 'exit 54')
    _, _, status = shell('SF_FLUTTER="$(command -v flutter)"; pt_prepare_ohos_toolchain && touch "$PT_TEST_ROOT/BUSINESS"', env: { 'DEVECO_STUDIO_HOME' => @tool })
    assert_equal 3, status.exitstatus
    assert_includes File.read(@trace), 'ohpm-version'
    refute_includes File.read(@trace), 'hvigor-version'
    refute File.exist?(File.join(@root, 'BUSINESS'))
  end

  def test_failed_ohos_selection_restores_environment_before_next_root
    ohos_toolchain
    command(File.join(@tool, 'ohpm/bin/ohpm'), 'exit 54')
    out, = assert_success shell(<<~'ZSH', env: { 'DEVECO_STUDIO_HOME' => @tool })
      SF_FLUTTER="$(command -v flutter)"
      original="$PATH"
      PT_OHOS_ROOT="$DEVECO_STUDIO_HOME"
      pt_try_ohos_root
      [[ "$PATH" == "$original" && -z "$DEVECO_SDK_HOME" && -z "$OHOS_SDK_HOME" && -z "$TOOL_HOME" && -z "$SF_JAVA_HOME" ]] || exit 91
      print restored
    ZSH
    assert_includes out, 'restored'
  end

  def test_exact_node_archive_is_checksum_verified_reused_and_does_not_use_brew
    architecture, = Open3.capture2('/usr/bin/uname', '-m')
    architecture = architecture.strip == 'arm64' ? 'arm64' : 'x64'
    folder = "node-v1.2.3-darwin-#{architecture}"
    payload = File.join(@root, 'payload')
    command(File.join(payload, folder, 'bin/node'), 'print v1.2.3')
    command(File.join(payload, folder, 'bin/npm'), 'print 1.0.0')
    archive = File.join(@root, 'node.tar.gz')
    _, _, status = Open3.capture3('/usr/bin/tar', '-czf', archive, '-C', payload, folder)
    assert status.success?
    shasums = File.join(@root, 'SHASUMS256.txt')
    File.write(shasums, "#{Digest::SHA256.file(archive).hexdigest}  #{folder}.tar.gz\n")
    assert_success shell(<<~'ZSH', env: { 'PT_TEST_ARCHIVE' => archive, 'PT_TEST_SHASUMS' => shasums })
      pt_probe_node() {
        [[ -x "$1" && "$("$1" --version)" == v1.2.3 ]] || return 1
        PT_NODE="$1"
      }
      pt_install_node_exact 1.2.3 && pt_install_node_exact 1.2.3
    ZSH
    trace = File.read(@trace)
    assert_equal 1, trace.lines.count { |line| line.start_with?('node-download|') }
    assert_equal 1, trace.lines.count { |line| line.start_with?('node-shasums|') }
    assert File.executable?(File.join(@home, "Library/Caches/JobsFlutterTools/node/v1.2.3/#{architecture}/#{folder}/bin/node"))
    refute_includes trace, 'brew'
  end

  def test_spm_merge_rejects_target_ancestor_link_before_copying_any_file
    source = File.join(@root, 'spm-source')
    target = File.join(@root, 'spm-target')
    external = File.join(@root, 'external')
    FileUtils.mkdir_p([File.join(source, 'nested'), target, external])
    File.write(File.join(source, 'a-first'), 'must stay absent')
    File.write(File.join(source, 'nested/private.swift'), 'private')
    File.symlink(external, File.join(target, 'nested'))
    _, _, status = shell("pt_merge_spm_cache #{source.shellescape} #{target.shellescape}")
    refute status.success?
    assert_empty Dir.children(external)
    refute File.exist?(File.join(target, 'a-first'))
    assert File.symlink?(File.join(target, 'nested'))
  end
end
