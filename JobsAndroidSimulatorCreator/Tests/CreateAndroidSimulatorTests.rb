# frozen_string_literal: true
# 隔离 SDK / HOME / PATH 回归；不调用真实 Android 组件安装、AVD 创建或启动。
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'pty'
require 'timeout'
require 'digest'
require 'json'
require 'shellwords'

class CreateAndroidSimulatorTests < Minitest::Test
  SCRIPT = File.expand_path('../Scripts/CreateAndroidSimulator.zsh', __dir__)
  STANDALONE = File.expand_path('../../../../JobsCommand@Flutter/运行/【MacOS】🚀双击启动Android模拟器.command/【MacOS】🚀双击启动Android模拟器.command', __dir__)
  PACKAGE = "system-images;android-36;google_apis;#{`/usr/sbin/sysctl -n hw.optional.arm64 2>/dev/null`.strip == '1' ? 'arm64-v8a' : 'x86_64'}"

  def setup
    @root = Dir.mktmpdir('Android SDK 中文 空格 ')
    @sdk = File.join(@root, 'SDK 中文')
    @avd = File.join(@root, 'AVD 空格')
    @jdk = File.join(@root, 'JDK 中文')
    @events = File.join(@root, 'events')
    @emulator_template = File.join(@root, 'fake-emulator')
    FileUtils.mkdir_p([File.join(@sdk, 'cmdline-tools', 'latest', 'bin'), @avd, File.join(@jdk, 'bin'), File.join(@root, 'logs')])
    File.write(File.join(@avd, 'list'), '')
    executable(File.join(@jdk, 'bin', 'java'), <<~'ZSH')
      #!/bin/zsh
      print -r -- 'fake Java version 21' >&2
    ZSH
    executable(@emulator_template, <<~'ZSH')
      #!/bin/zsh
      print -r -- "emulator:$*" >> "$FIXTURE_EVENTS"
      case "$1" in
        -version) [[ "${FIXTURE_EMULATOR_BROKEN:-0}" != 1 ]] || exit 8; print -r -- 'Android emulator fake version 36' ;;
        -list-avds) /bin/cat "$ANDROID_AVD_HOME/list" ;;
        -avd) print -r -- "launch:$2" >> "$FIXTURE_EVENTS"; exec /bin/sleep 3 ;;
        *) exit 9 ;;
      esac
    ZSH
    install_emulator
    executable(File.join(@sdk, 'cmdline-tools', 'latest', 'bin', 'sdkmanager'), <<~'ZSH')
      #!/bin/zsh
      print -r -- "sdk:$*" >> "$FIXTURE_EVENTS"
      if [[ "$*" == *--version* ]]; then
        if [[ "${FIXTURE_REQUIRE_JAVA21:-0}" == 1 && "$JAVA_HOME" == "$FIXTURE_OLD_JAVA" ]]; then
          print -r -- 'UnsupportedClassVersionError: only recognizes class file versions' >&2
          exit 13
        fi
        [[ "${FIXTURE_TOOLS_BROKEN:-0}" != 1 ]] || exit 7
        print -r -- 19.0
      elif [[ "$*" == *--list* ]]; then
        [[ "${FIXTURE_LIST_FAIL:-0}" != 1 ]] || { print -r -- 'network fixture failed' >&2; exit 6; }
        print -r -- 'Available Packages:'
        print -r -- "$FIXTURE_PACKAGE | 1 | Android image"
        print -r -- 'system-images;android-99-preview;google_apis;arm64-v8a | 1 | preview'
        print -r -- 'system-images;android-38;android-wear;arm64-v8a | 1 | watch'
      elif [[ "$*" == *--install* ]]; then
        [[ "${FIXTURE_INSTALL_FAIL:-0}" != 1 ]] || { print -r -- 'download fixture failed' >&2; exit 5; }
        [[ "${FIXTURE_INSTALL_BROKEN:-0}" != 1 ]] || exit 0
        if [[ "$*" == *'--install emulator'* ]]; then
          /bin/mkdir -p "$ANDROID_HOME/emulator"
          /bin/cp "$FIXTURE_EMULATOR_TEMPLATE" "$ANDROID_HOME/emulator/emulator"
        else
          image_dir="$ANDROID_HOME/${(j:/:)${(s:;:)FIXTURE_PACKAGE}}"
          /bin/mkdir -p "$image_dir"
          : > "$image_dir/system.img"
          : > "$image_dir/source.properties"
        fi
      elif [[ "$*" == *'--uninstall emulator'* ]]; then
        [[ "${FIXTURE_UNINSTALL_FAIL:-0}" != 1 ]] || exit 12
        /bin/rm -r "$ANDROID_HOME/emulator"
      else
        exit 9
      fi
    ZSH
    executable(File.join(@sdk, 'cmdline-tools', 'latest', 'bin', 'avdmanager'), <<~'ZSH')
      #!/bin/zsh
      print -r -- "avd:$*" >> "$FIXTURE_EVENTS"
      if [[ "$*" == 'list device' ]]; then
        print -r -- 'id: 0 or "pixel_9"'
        print -r -- '    Name: Pixel 9'
        print -r -- 'id: 1 or "pixel_10"'
        print -r -- '    Name: Pixel 10'
        print -r -- 'id: 2 or "pixel_watch"'
        print -r -- '    Name: Pixel Watch'
        print -r -- 'id: 3 or "Nexus_10"'
        print -r -- '    Name: Nexus 10'
      elif [[ "$1 $2" == 'create avd' ]]; then
        name=''
        while (( $# )); do
          [[ "$1" != -n ]] || name="$2"
          shift
        done
        [[ "${FIXTURE_CREATE_FAIL:-0}" != 1 ]] || exit 4
        [[ "$name" != '' ]] || exit 3
        if [[ "${FIXTURE_CREATE_NO_RESULT:-0}" != 1 ]]; then
          print -r -- "$name" >> "$ANDROID_AVD_HOME/list"
          /bin/mkdir "$ANDROID_AVD_HOME/$name.avd"
          : > "$ANDROID_AVD_HOME/$name.ini"
        fi
        print -r -- "Created $name"
      else
        exit 9
      fi
    ZSH
    @env = {
      'HOME' => @root, 'JAVA_HOME' => @jdk, 'ANDROID_HOME' => @sdk,
      'ANDROID_SDK_ROOT' => @sdk, 'ANDROID_AVD_HOME' => @avd,
      'ANDROID_USER_HOME' => File.join(@root, '.android'), 'TMPDIR' => File.join(@root, 'logs'),
      'PATH' => '/usr/bin:/bin:/usr/sbin:/sbin', 'NO_COLOR' => '1', 'TERM' => 'dumb',
      'ANDROID_SIM_PROXY' => 'direct', 'https_proxy' => nil, 'HTTPS_PROXY' => nil,
      'all_proxy' => nil, 'ALL_PROXY' => nil, 'no_proxy' => nil, 'NO_PROXY' => nil,
      'FIXTURE_EVENTS' => @events, 'FIXTURE_PACKAGE' => PACKAGE,
      'FIXTURE_EMULATOR_TEMPLATE' => @emulator_template
    }
    add_image
  end

  def teardown
    FileUtils.remove_entry(@root) if @root && File.directory?(@root)
  end

  def executable(path, content)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
    File.chmod(0o755, path)
  end

  def install_emulator
    FileUtils.mkdir_p(File.join(@sdk, 'emulator'))
    FileUtils.cp(@emulator_template, File.join(@sdk, 'emulator', 'emulator'))
  end

  def add_image(package = PACKAGE)
    path = File.join(@sdk, package.tr(';', '/'))
    FileUtils.mkdir_p(path)
    File.write(File.join(path, 'source.properties'), 'Pkg.Revision=1')
    File.write(File.join(path, 'system.img'), '')
  end

  def events
    File.exist?(@events) ? File.read(@events) : ''
  end

  def bootstrap_fixture(checksum: nil, archive_name: nil)
    package_root = File.join(@root, 'official archive')
    FileUtils.mkdir_p(package_root)
    FileUtils.cp_r(File.join(@sdk, 'cmdline-tools', 'latest'), File.join(package_root, 'cmdline-tools'))
    FileUtils.mkdir_p(File.join(package_root, 'cmdline-tools', 'lib'))
    File.write(File.join(package_root, 'cmdline-tools', 'source.properties'), 'Pkg.Revision=21.0')
    archive = File.join(@root, 'official-tools.zip')
    _out, zip_status = Open3.capture2e('/usr/bin/zip', '-qr', archive, 'cmdline-tools', chdir: package_root)
    assert zip_status.success?
    checksum ||= Digest::SHA1.file(archive).hexdigest
    xml = File.join(@root, 'repository.xml')
    host_arch = PACKAGE.end_with?('arm64-v8a') ? 'aarch64' : 'x64'
    archive_name ||= PACKAGE.end_with?('arm64-v8a') ? 'commandlinetools-mac_arm64-123_latest.zip' : 'commandlinetools-mac_x86_64-123_latest.zip'
    File.write(xml, <<~XML)
      <repository><remotePackage path="cmdline-tools;21.0"><revision><major>21</major><minor>0</minor></revision>
      <channelRef ref="channel-0"/><archives><archive><host-os>macosx</host-os><host-arch>#{host_arch}</host-arch>
      <complete><size>#{File.size(archive)}</size><checksum type="sha1">#{checksum}</checksum><url>#{archive_name}</url></complete>
      </archive></archives></remotePackage></repository>
    XML
    @env['FIXTURE_BOOTSTRAP_XML'] = xml
    @env['FIXTURE_BOOTSTRAP_ZIP'] = archive
    write_download_fixture
    FileUtils.rm_rf(File.join(@sdk, 'cmdline-tools', 'latest'))
  end

  def write_download_fixture
    fakebin = File.join(@root, 'bin')
    executable(File.join(fakebin, 'curl'), <<~'ZSH')
      #!/bin/zsh
      target='' url='' headers=''
      [[ "$1" == --disable ]] || exit 17
      while (( $# )); do
        if [[ "$1" == --output ]]; then target="$2"; shift; fi
        if [[ "$1" == --dump-header ]]; then headers="$2"; shift; fi
        if [[ "$1" == https://* ]]; then url="$1"; fi
        shift
      done
      print -r -- "curl:$url" >> "$FIXTURE_EVENTS"
      print -r -- "curl-target:$target" >> "$FIXTURE_EVENTS"
      print -r -- "stage-mode:$(/usr/bin/stat -f %Lp "${target:h}")" >> "$FIXTURE_EVENTS"
      if [[ "$url" == https://dl.google.com/android/repository/repository2-3.xml ]]; then
        /bin/cp "$FIXTURE_BOOTSTRAP_XML" "$target"
      elif [[ "$url" == https://api.adoptium.net/* ]]; then
        /bin/cp "$FIXTURE_JAVA_JSON" "$target"
      elif [[ "$url" == https://github.com/* || "$url" == https://release-assets.githubusercontent.com/* ]]; then
        [[ "${FIXTURE_JAVA_DOWNLOAD_FAIL:-0}" != 1 ]] || exit 22
        if [[ "${FIXTURE_JAVA_REDIRECT:-0}" == 1 && "$url" == https://github.com/* ]]; then
          print -r -- $'HTTP/1.1 302 Found\r\nLocation: https://release-assets.githubusercontent.com/fixture/java.tar.gz?signature=private-token\r\n' > "$headers"
          print -rn -- 302
          exit 0
        fi
        /bin/cp "$FIXTURE_JAVA_TAR" "$target"
      else
        [[ "${FIXTURE_BOOTSTRAP_DOWNLOAD_FAIL:-0}" != 1 ]] || exit 22
        /bin/cp "$FIXTURE_BOOTSTRAP_ZIP" "$target"
      fi
      print -rn -- 200
    ZSH
    @env['PATH'] = "#{fakebin}:/usr/bin:/bin:/usr/sbin:/sbin"
  end

  def java_fixture(checksum: nil, unsafe_link: nil)
    contents = File.join(@root, 'java archive', 'jdk-21.0.13+9', 'Contents', 'Home')
    FileUtils.mkdir_p(File.join(contents, 'bin'))
    FileUtils.cp(File.join(@jdk, 'bin', 'java'), File.join(contents, 'bin', 'java'))
    File.symlink(unsafe_link, File.join(contents, 'unsafe')) if unsafe_link
    archive = File.join(@root, 'official-java.tar.gz')
    _output, result = Open3.capture2e('/usr/bin/tar', '-czf', archive, '-C', File.join(@root, 'java archive'), 'jdk-21.0.13+9')
    assert result.success?
    arch = PACKAGE.end_with?('arm64-v8a') ? 'aarch64' : 'x64'
    json = File.join(@root, 'official-java.json')
    File.write(json, JSON.generate([{ vendor: 'eclipse', version: { major: 21 }, release_name: 'jdk-21.0.13+9', binary: { os: 'mac', architecture: arch, image_type: 'jdk', jvm_impl: 'hotspot', package: { link: "https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.13%2B9/OpenJDK21U-jdk_#{arch}_mac_hotspot_21.0.13_9.tar.gz", checksum: checksum || Digest::SHA256.file(archive).hexdigest, size: File.size(archive) } } }]))
    @env['FIXTURE_JAVA_JSON'] = json
    @env['FIXTURE_JAVA_TAR'] = archive
    write_download_fixture
  end

  def java_bootstrap
    command = <<~'ZSH'
      source <(/usr/bin/sed '$d' "$1")
      android_prepare_context
      ANDROID_SIM_MODE=prepare
      android_detect_architecture
      android_find_java() {
        [[ "${FIXTURE_JAVA_POSTFAIL:-0}" != 1 ]] && [[ "${JAVA_HOME:-}" == "$HOME/Library/Java/JavaVirtualMachines/temurin-21-"* ]] && [[ -x "$JAVA_HOME/bin/java" ]] && "$JAVA_HOME/bin/java" -version
      }
      android_ensure_java
    ZSH
    Open3.capture2e(@env, '/bin/zsh', '-c', command, 'test', SCRIPT)
  end

  def interactive(input, *args)
    output = +''
    process_status = nil
    PTY.spawn(@env, '/bin/zsh', SCRIPT, *args) do |reader, writer, pid|
      writer.write(input)
      Timeout.timeout(14) do
        begin
          loop { output << reader.readpartial(8192) }
        rescue Errno::EIO, EOFError
          _, process_status = Process.wait2(pid)
        end
      end
    end
    [output.force_encoding(Encoding::UTF_8), process_status]
  end

  def check(*args)
    Open3.capture2e(@env, '/bin/zsh', SCRIPT, *(args.empty? ? ['--check'] : args))
  end

  def test_standalone_and_finder_script_are_identical
    assert File.exist?(STANDALONE), STANDALONE
    assert_equal File.binread(STANDALONE), File.binread(SCRIPT)
  end

  def test_full_health_check_is_read_only
    output, result = check
    assert result.success?, output
    assert_includes output, '创建依赖已就绪'
    assert_includes output, SCRIPT
    refute_includes output, "\e["
    refute_match(/--install|create avd|--list --channel/, events)
    assert_empty Dir.children(File.join(@root, 'logs'))
    assert_empty File.read(File.join(@avd, 'list'))
  end

  def launcher_fixture
    executable(File.join(@sdk, 'cmdline-tools', 'latest', 'bin', 'sdkmanager'), <<~'ZSH')
      #!/bin/zsh
      # Official v23 wrapper dispatches using ANDROID_CLI_BIN / run_android_cli.
      print -r -- 'UNEXPECTED_CLI_DOWNLOAD' >> "$FIXTURE_EVENTS"
      exit 1
    ZSH
    executable(File.join(@sdk, 'cmdline-tools', 'latest', 'bin', 'avdmanager'), "#!/bin/zsh\nexit 99\n")
  end

  def test_check_never_executes_the_new_cli_download_launcher
    launcher_fixture
    output, result = check
    refute result.success?, output
    assert_includes output, '跳过 Android CLI 下载启动器'
    refute_includes events, 'UNEXPECTED_CLI_DOWNLOAD'
    refute_includes events, 'curl:'
    assert_empty Dir.children(File.join(@root, 'logs'))
  end

  def test_cli_launcher_does_not_hide_a_working_legacy_installation
    FileUtils.cp_r(File.join(@sdk, 'cmdline-tools', 'latest'), File.join(@sdk, 'cmdline-tools', '21.0'))
    launcher_fixture
    output, result = check
    assert result.success?, output
    assert_includes output, '21.0/bin'
    refute_includes events, 'UNEXPECTED_CLI_DOWNLOAD'
  end

  def test_cli_launcher_is_preserved_and_compatible_tools_are_added_once
    bootstrap_fixture
    launcher_fixture
    2.times do
      output, result = interactive("\n", '--prepare')
      assert result.success?, output
    end
    assert File.executable?(File.join(@sdk, 'cmdline-tools', 'latest', 'bin', 'sdkmanager'))
    assert_equal 1, Dir.glob(File.join(@sdk, 'cmdline-tools', 'jobs-*')).length
    assert_equal 1, events.scan('curl:https://dl.google.com/android/repository/repository2-3.xml').length
    refute_includes events, 'UNEXPECTED_CLI_DOWNLOAD'
  end

  def test_metadata_without_the_compatible_package_stops_before_archive_download
    bootstrap_fixture
    xml = @env.fetch('FIXTURE_BOOTSTRAP_XML')
    File.write(xml, File.read(xml).sub('cmdline-tools;21.0', 'cmdline-tools;latest').sub('<major>21', '<major>23'))
    output, result = interactive("\n", '--prepare')
    refute result.success?, output
    assert_includes output, '缺少兼容版'
    refute_match(/curl:.*\.zip/, events)
    assert_empty Dir.glob(File.join(@sdk, 'cmdline-tools', 'jobs-*'))
  end

  def network_probe(source_transform: nil)
    source = File.read(SCRIPT).sub(/^main "\$@"\s*\z/, '')
    source = source_transform.call(source) if source_transform
    library = File.join(@root, 'network.zsh')
    File.write(library, source + <<~'ZSH')
      android_prepare_context
      android_configure_network || exit $?
      print -rl -- "${ANDROID_SIM_CURL_PROXY[@]}" "${ANDROID_SIM_SDK_PROXY[@]}"
    ZSH
    Open3.capture2e(@env, '/bin/zsh', '-f', library)
  end

  def test_explicit_proxy_reaches_sdk_list_and_install
    @env['ANDROID_SIM_PROXY'] = 'http://127.0.0.1:7990'
    FileUtils.rm_rf(File.join(@sdk, 'system-images'))
    output, result = interactive("\n\n\n\n\n", '--create')
    assert result.success?, output
    operations = events.lines.select { |line| line.start_with?('sdk:') && line.match?(/--list |--install /) }
    assert_equal 2, operations.length
    operations.each { |line| assert_includes line, '--proxy=http --proxy_host=127.0.0.1 --proxy_port=7990' }
    refute_match(/sdk:.*--version.*--proxy/, events)
  end

  def test_network_uses_environment_and_system_static_proxy_without_writing_settings
    @env['ANDROID_SIM_PROXY'] = nil
    @env['HTTPS_PROXY'] = 'socks5://localhost:1080'
    output, result = network_probe
    assert result.success?, output
    assert_includes output, '--proxy=socks'
    assert_includes output, '--proxy_host=localhost'
    @env['HTTPS_PROXY'] = nil
    scutil = File.join(@root, 'scutil')
    executable(scutil, "#!/bin/zsh\nprint -r -- $'HTTPSEnable : 1\nHTTPSProxy : 127.0.0.1\nHTTPSPort : 7990'\n")
    output, result = network_probe(source_transform: ->(source) { source.gsub('/usr/sbin/scutil', scutil.shellescape) })
    assert result.success?, output
    assert_includes output, '--proxy=http'
    assert_includes output, '--proxy_port=7990'
  end

  def test_proxy_errors_do_not_leak_credentials_or_start_repairs
    ['http://user:private-password@localhost:7890', 'http://localhost:65536', 'http://localhost:0'].each do |proxy|
      @env['ANDROID_SIM_PROXY'] = proxy
      output, result = interactive("\n", '--prepare')
      refute result.success?, output
      refute_includes output, 'private-password'
      assert_empty events
    end
  end

  def test_no_proxy_is_respected_for_sdk_repository
    @env['ANDROID_SIM_PROXY'] = 'http://localhost:7990'
    @env['NO_PROXY'] = '.google.com'
    output, result = network_probe
    assert result.success?, output
    refute_includes output, '--proxy_host='
    assert_includes output, '使用直连'
  end

  def test_check_does_not_install_missing_emulator
    FileUtils.rm(File.join(@sdk, 'emulator', 'emulator'))
    output, result = check
    refute result.success?
    assert_includes output, 'emulator 缺失'
    refute_includes events, '--install'
    assert_empty Dir.children(File.join(@root, 'logs'))
  end

  def test_check_missing_sdk_stops_before_downstream
    @env['ANDROID_HOME'] = File.join(@root, '不存在')
    output, result = check
    refute result.success?
    assert_includes output, 'SDK 根目录未就绪'
    assert_empty events
  end

  def test_check_multiple_missing_layers_has_no_download
    FileUtils.rm_rf(File.join(@sdk, 'cmdline-tools'))
    FileUtils.rm(File.join(@sdk, 'emulator', 'emulator'))
    FileUtils.rm_rf(File.join(@sdk, 'system-images'))
    output, result = check
    refute result.success?
    assert_includes output, 'Command-line Tools 缺失'
    assert_includes output, 'emulator 缺失'
    assert_empty events
  end

  def test_broken_sdk_tools_fail_health_check
    @env['FIXTURE_TOOLS_BROKEN'] = '1'
    output, result = check
    refute result.success?
    assert_includes output, '失败命令'
    refute_includes events, 'create avd'
  end

  def test_help_and_invalid_argument_do_not_probe_or_write
    output, result = check('--help')
    assert result.success?, output
    assert_empty events
    output, result = check('--bad')
    refute result.success?
    assert_includes output, '不支持的参数'
    assert_empty events
    assert_empty Dir.children(File.join(@root, 'logs'))
  end

  def test_noninteractive_write_mode_rejects_before_probe
    output, result = check('--create')
    refute result.success?
    assert_includes output, '可交互终端'
    assert_empty events
    assert_empty Dir.children(File.join(@root, 'logs'))
  end

  def test_intro_cancellation_has_no_side_effect
    output, result = interactive("cancel\n", '--create')
    assert result.success?, output
    assert_empty events
    assert_empty Dir.children(File.join(@root, 'logs'))
  end

  def test_create_uses_current_arch_image_and_all_enter_defaults
    output, result = interactive("\n\n\n\n\n", '--create')
    assert result.success?, output
    assert_includes events, "create avd -n pixel_10_API_36_#{PACKAGE.split(';').last.tr('-', '_')} -k #{PACKAGE} --device pixel_10"
    refute_includes events, '--install'
    assert_includes output, '已新增 AVD'
    assert_includes output, 'Android 开机仍需等待'
    refute_match(/-f\b|--force|-wipe-data/, events)
  end

  def test_existing_name_and_orphan_directory_cannot_be_overwritten
    name = "pixel_10_API_36_#{PACKAGE.split(';').last.tr('-', '_')}"
    FileUtils.mkdir_p(File.join(@avd, "#{name}.avd"))
    output, result = interactive("\n\n\n\nSafe_New\n\n", '--create')
    assert result.success?, output
    assert_includes output, '已存在同名 AVD'
    assert File.directory?(File.join(@avd, "#{name}.avd"))
    assert_includes events, 'create avd -n Safe_New'
  end

  def test_unsafe_name_is_rejected_before_create
    output, result = interactive("\n\n\n../escape\nbad name\nSafe\n\n", '--create')
    assert result.success?, output
    assert_includes output, '名称须为'
    assert_includes events, 'create avd -n Safe'
    refute_includes events, '../escape'
  end

  def test_final_cancellation_does_not_create
    output, result = interactive("\n\n\n\ncancel\n", '--create')
    assert result.success?, output
    refute_includes events, 'create avd'
    assert_includes output, '已取消'
  end

  def test_empty_avds_enters_creation_and_selection_cancel_is_safe
    output, result = interactive("\nq\n")
    assert result.success?, output
    assert_includes output, '当前没有 AVD'
    refute_includes events, 'create avd'
  end

  def test_existing_avd_launch_checks_entire_toolchain_without_installing
    File.write(File.join(@avd, 'list'), "Existing\n")
    output, result = interactive("\n2\n")
    assert result.success?, output
    assert_includes events, 'launch:Existing'
    assert_includes events, '--version'
    refute_includes events, '--install'
  end

  def test_emulator_missing_installs_once_and_rechecks
    FileUtils.rm(File.join(@sdk, 'emulator', 'emulator'))
    output, result = interactive("\nq\n", '--create')
    assert result.success?, output
    assert_equal 1, events.scan('--install emulator').length
    assert_includes output, '来源｜SDK 组件安装'
    assert_operator output.index('来源｜SDK 组件安装'), :<, output.index('自动安装本次必要组件')
    refute_includes events, 'create avd'
  end

  def test_emulator_install_failure_stops_downstream
    FileUtils.rm(File.join(@sdk, 'emulator', 'emulator'))
    @env['FIXTURE_INSTALL_FAIL'] = '1'
    output, result = interactive("\n", '--create')
    refute result.success?, output
    assert_includes output, '组件安装失败'
    assert_equal 1, events.scan('--install emulator').length
    refute_includes events, 'create avd'
  end

  def test_emulator_post_install_health_failure_stops
    FileUtils.rm(File.join(@sdk, 'emulator', 'emulator'))
    @env['FIXTURE_INSTALL_BROKEN'] = '1'
    output, result = interactive("\n", '--create')
    refute result.success?, output
    assert_includes output, '安装后复检仍失败'
    assert_equal 1, events.scan('--install emulator').length
    refute_includes events, 'create avd'
  end

  def test_missing_image_automatically_reads_remote_list_and_can_cancel_selection
    FileUtils.rm_rf(File.join(@sdk, 'system-images'))
    output, result = interactive("\n\nq\n", '--create')
    assert result.success?, output
    assert_includes output, '查询稳定系统映像'
    assert_includes events, '--list --channel'
    refute_includes events, '--install'
    refute_includes events, 'create avd'
  end

  def test_remote_list_failure_does_not_create
    FileUtils.rm_rf(File.join(@sdk, 'system-images'))
    @env['FIXTURE_LIST_FAIL'] = '1'
    output, result = interactive("\n\n", '--create')
    refute result.success?, output
    assert_includes output, '读取 Google SDK 清单失败'
    refute_includes events, '--install'
    refute_includes events, 'create avd'
  end

  def test_image_download_and_creation
    FileUtils.rm_rf(File.join(@sdk, 'system-images'))
    output, result = interactive("\n\n\n\n\n", '--create')
    assert result.success?, output
    assert_includes events, "--install #{PACKAGE}"
    assert_includes events, 'create avd'
    assert_includes output, '已新增 AVD'
  end

  def test_image_post_install_failure_does_not_create
    FileUtils.rm_rf(File.join(@sdk, 'system-images'))
    @env['FIXTURE_INSTALL_BROKEN'] = '1'
    output, result = interactive("\n\n\n", '--create')
    refute result.success?, output
    assert_includes output, '映像安装后复检失败'
    refute_includes events, 'create avd'
  end

  def test_avd_creation_failure_does_not_launch
    @env['FIXTURE_CREATE_FAIL'] = '1'
    output, result = interactive("\n\n\n\n\n", '--create')
    refute result.success?, output
    assert_includes output, '创建失败'
    refute_includes events, 'launch:'
  end

  def test_avd_success_without_metadata_is_not_announced_as_created
    @env['FIXTURE_CREATE_NO_RESULT'] = '1'
    output, result = interactive("\n\n\n\n\n", '--create')
    refute result.success?, output
    assert_includes output, '列表未检出'
    refute_includes events, 'launch:'
  end

  def test_wrong_arch_and_preview_images_are_excluded
    FileUtils.rm_rf(File.join(@sdk, 'system-images'))
    opposite = PACKAGE.end_with?('arm64-v8a') ? 'x86_64' : 'arm64-v8a'
    add_image("system-images;android-37;google_apis;#{opposite}")
    add_image("system-images;android-99-preview;google_apis;#{PACKAGE.split(';').last}")
    output, result = check
    refute result.success?
    assert_includes output, '尚无完整'
  end

  def test_broken_fzf_falls_back_to_number_selection
    fakebin = File.join(@root, 'bin')
    executable(File.join(fakebin, 'fzf'), "#!/bin/zsh\nexit 7\n")
    @env['PATH'] = "#{fakebin}:#{@env['PATH']}"
    output, result = interactive("\nq\n", '--create')
    assert result.success?, output
    assert_includes output, 'fzf 缺失或不可用'
  end

  def test_missing_command_tools_is_automatically_prepared_after_single_entry_confirmation
    bootstrap_fixture
    output, result = interactive("\n", '--prepare')
    assert result.success?, output
    assert_includes events, 'curl:'
    refute_includes events, 'create avd'
    assert_equal 1, Dir.glob(File.join(@sdk, 'cmdline-tools', 'jobs-*')).length
    refute_includes output, '回车跳过'
  end

  def test_official_bootstrap_adds_a_version_and_rechecks
    bootstrap_fixture
    output, result = interactive("\nq\n", '--create')
    assert result.success?, output
    assert_equal 1, events.scan('curl:https://dl.google.com/android/repository/repository2-3.xml').length
    assert_equal 1, Dir.glob(File.join(@sdk, 'cmdline-tools', 'jobs-*')).length
    assert_includes output, '已新增官方命令行工具'
    assert_includes output, 'SDK 命令行工具'
    assert_match(%r{curl-target:.*SDK 中文/cmdline-tools/\.jobs-staging\.[^/]+/repository\.xml}, events)
    assert_includes events, 'stage-mode:700'
    assert_empty Dir.glob(File.join(@sdk, 'cmdline-tools', '.jobs-staging.*'))
    assert_empty Dir.glob(File.join(@root, 'logs', 'jobs-android-tools.*'))
    refute_includes events, 'create avd'
  end

  def test_official_bootstrap_checksum_failure_leaves_sdk_untouched
    bootstrap_fixture(checksum: '0' * 40)
    output, result = interactive("\n", '--create')
    refute result.success?, output
    assert_includes output, '工具归档校验失败'
    assert_empty Dir.glob(File.join(@sdk, 'cmdline-tools', 'jobs-*'))
    assert_empty Dir.glob(File.join(@root, 'logs', 'jobs-android-tools.*'))
    refute_includes events, 'create avd'
  end

  def test_official_bootstrap_rejects_external_archive_url
    bootstrap_fixture(archive_name: 'https://example.invalid/tools.zip')
    output, result = interactive("\n", '--create')
    refute result.success?, output
    assert_includes output, '元数据格式或归档地址不符合预期'
    assert_equal 1, events.scan('curl:').length
    assert_empty Dir.glob(File.join(@sdk, 'cmdline-tools', 'jobs-*'))
  end

  def test_official_bootstrap_download_failure_stops_without_retries
    bootstrap_fixture
    @env['FIXTURE_BOOTSTRAP_DOWNLOAD_FAIL'] = '1'
    output, result = interactive("\n", '--create')
    refute result.success?, output
    assert_includes output, 'Google 官方下载失败'
    assert_equal 2, events.scan('curl:').length
    assert_empty Dir.glob(File.join(@sdk, 'cmdline-tools', 'jobs-*'))
  end

  def test_bootstrap_preserves_broken_existing_tools_and_stops_if_recheck_fails
    bootstrap_fixture
    preserved = File.join(@sdk, 'cmdline-tools', 'old-version', 'keep.txt')
    FileUtils.mkdir_p(File.dirname(preserved))
    File.write(preserved, 'keep original')
    @env['FIXTURE_TOOLS_BROKEN'] = '1'
    output, result = interactive("\n", '--create')
    refute result.success?, output
    assert_includes output, '命令行工具安装后复检失败'
    assert_equal 'keep original', File.read(preserved)
    assert_equal 1, Dir.glob(File.join(@sdk, 'cmdline-tools', 'jobs-*')).length
    assert_equal 1, events.scan('repository2-3.xml').length
    refute_includes events, 'create avd'
  end

  def test_check_never_bootstraps_command_tools
    bootstrap_fixture
    output, result = check
    refute result.success?, output
    refute_includes events, 'curl:'
    assert_empty Dir.children(File.join(@root, 'logs'))
    assert_empty Dir.glob(File.join(@sdk, 'cmdline-tools', 'jobs-*'))
  end

  def test_stable_minor_and_extension_api_images_are_supported
    FileUtils.rm_rf(File.join(@sdk, 'system-images'))
    add_image("system-images;android-36.1;google_apis;#{PACKAGE.split(';').last}")
    add_image("system-images;android-36-ext19;google_apis;#{PACKAGE.split(';').last}")
    output, result = check
    assert result.success?, output
    assert_includes output, '系统映像：2 个'
  end

  def test_registered_broken_emulator_repairs_once_and_stops_if_recheck_still_fails
    File.write(File.join(@sdk, 'emulator', 'source.properties'), 'Pkg.Revision=36')
    @env['FIXTURE_EMULATOR_BROKEN'] = '1'
    output, result = interactive("\n", '--create')
    refute result.success?, output
    assert_includes output, '自动通过官方 sdkmanager 卸载'
    assert_includes output, '保留已有 AVD'
    assert_equal 1, events.scan('--uninstall emulator').length
    assert_equal 1, events.scan('--install emulator').length
    assert_includes output, '安装后复检仍失败'
    refute_includes events, 'create avd'
  end

  def test_directory_publish_rejects_existing_destination_instead_of_nesting
    source = File.join(@sdk, 'cmdline-tools', '.jobs-staging.collision', 'cmdline-tools')
    destination = File.join(@sdk, 'cmdline-tools', 'jobs-existing')
    FileUtils.mkdir_p([source, destination])
    File.write(File.join(source, 'source.properties'), 'new')
    File.write(File.join(destination, 'keep.txt'), 'original')
    command = %q{source <(/usr/bin/sed '$d' "$1"); android_publish_tools_directory "$2" "$3"}
    _output, result = Open3.capture2e(@env, '/bin/zsh', '-c', command, 'test', SCRIPT, source, destination)
    refute result.success?
    assert File.directory?(source)
    assert_equal 'original', File.read(File.join(destination, 'keep.txt'))
    refute File.exist?(File.join(destination, 'cmdline-tools'))
  end

  def test_prepare_healthy_uses_only_the_entry_confirmation_and_never_queries_images
    output, result = interactive("\n", '--prepare')
    assert result.success?, output
    assert_includes output, '--prepare 已完成'
    refute_includes events, '--install'
    refute_includes events, '--list --channel'
    refute_includes events, 'create avd'
    refute_includes output, 'T//'
  end

  def test_prepare_recovers_missing_sdk_tools_and_emulator_without_extra_input
    bootstrap_fixture
    FileUtils.rm_rf(@sdk)
    output, result = interactive("\n", '--prepare')
    assert result.success?, output
    assert_includes output, '自动补齐 SDK 根目录'
    assert_includes output, '--prepare 已完成'
    assert_equal 1, events.scan('--install emulator').length
    assert_equal 1, events.scan('repository2-3.xml').length
    refute_includes events, '--list --channel'
    refute_includes events, 'create avd'
  end

  def test_invalid_sdk_root_is_preserved_and_failure_shows_stage_and_log
    FileUtils.rm_rf(@sdk)
    File.write(@sdk, 'original data')
    output, result = interactive("\n", '--prepare')
    refute result.success?, output
    assert_equal 'original data', File.read(@sdk)
    assert_includes output, 'SDK 根目录补齐'
    assert_includes output, '操作结束；日志'
  end

  def test_registered_damaged_emulator_is_reinstalled_once_and_preserves_avds
    executable(File.join(@sdk, 'emulator', 'emulator'), "#!/bin/zsh\nprint -r -- 'broken emulator' >&2\nexit 8\n")
    File.write(File.join(@sdk, 'emulator', 'source.properties'), 'Pkg.Revision=36')
    File.write(File.join(@avd, 'keep.txt'), 'my device data')
    output, result = interactive("\n", '--prepare')
    assert result.success?, output
    assert_equal 1, events.scan('--uninstall emulator').length
    assert_equal 1, events.scan('--install emulator').length
    assert_equal 'my device data', File.read(File.join(@avd, 'keep.txt'))
    assert_includes output, '--prepare 已完成'
  end

  def test_damaged_emulator_uninstall_failure_prevents_install_and_creation
    executable(File.join(@sdk, 'emulator', 'emulator'), "#!/bin/zsh\nexit 8\n")
    @env['FIXTURE_UNINSTALL_FAIL'] = '1'
    output, result = interactive("\n", '--prepare')
    refute result.success?, output
    assert_includes output, '官方卸载失败'
    refute_includes events, '--install emulator'
    assert_includes output, '操作结束；日志'
  end

  def test_installation_and_remote_query_have_no_secondary_read_gates
    source = File.read(SCRIPT)
    refute_includes source, 'android_ask_install'
    refute_includes source, '回车跳过'
    refute_includes source, '是否联网'
    refute_includes source, '是否下载'
    refute_match(/yes\s*\|/, source)
  end

  def test_temurin_java_is_downloaded_verified_and_published_in_user_directory
    java_fixture
    output, result = java_bootstrap
    assert result.success?, output
    assert_includes output, '已补齐官方 Temurin 21'
    assert_equal 1, Dir.glob(File.join(@root, 'Library', 'Java', 'JavaVirtualMachines', 'temurin-21-*.jdk')).length
    assert_empty Dir.glob(File.join(@root, 'Library', 'Java', 'JavaVirtualMachines', '.jobs-staging.*'))
    assert_includes events, 'stage-mode:700'
  end

  def test_temurin_checksum_mismatch_does_not_publish
    java_fixture(checksum: '0' * 64)
    output, result = java_bootstrap
    refute result.success?, output
    assert_includes output, 'SHA256 与官方元数据不符'
    assert_empty Dir.glob(File.join(@root, 'Library', 'Java', 'JavaVirtualMachines', 'temurin-21-*.jdk'))
  end

  def test_temurin_download_failure_is_not_retried_or_published
    java_fixture
    @env['FIXTURE_JAVA_DOWNLOAD_FAIL'] = '1'
    output, result = java_bootstrap
    refute result.success?, output
    assert_includes output, 'Temurin 官方下载失败'
    assert_equal 1, events.scan('curl:https://github.com/').length
    assert_empty Dir.glob(File.join(@root, 'Library', 'Java', 'JavaVirtualMachines', 'temurin-21-*.jdk'))
  end

  def test_temurin_official_redirect_is_checked_and_signed_query_is_not_logged
    java_fixture
    @env['FIXTURE_JAVA_REDIRECT'] = '1'
    output, result = java_bootstrap
    assert result.success?, output
    assert_includes output, 'release-assets.githubusercontent.com'
    refute_includes output, 'private-token'
    assert_equal 1, events.scan('curl:https://release-assets.githubusercontent.com/').length
  end

  def test_temurin_dangling_external_symlink_is_rejected
    java_fixture(unsafe_link: '/tmp/jobs-nonexistent-outside-jdk')
    output, result = java_bootstrap
    refute result.success?, output
    assert_includes output, '悬空或绝对符号链接'
    assert_empty Dir.glob(File.join(@root, 'Library', 'Java', 'JavaVirtualMachines', 'temurin-21-*.jdk'))
  end

  def test_temurin_internal_existing_symlink_is_allowed
    java_fixture(unsafe_link: 'bin/java')
    output, result = java_bootstrap
    assert result.success?, output
    assert_includes output, '已补齐官方 Temurin 21'
  end

  def test_temurin_post_install_health_failure_stops_without_recursive_install
    java_fixture
    @env['FIXTURE_JAVA_POSTFAIL'] = '1'
    output, result = java_bootstrap
    refute result.success?, output
    assert_includes output, 'Java 安装后复检仍失败'
    assert_equal 1, events.scan('curl:https://github.com/').length
  end

  def test_new_command_tools_can_switch_java_after_first_post_install_class_error
    fallback_java = File.join(@root, 'Applications', 'Android Studio.app', 'Contents', 'jbr', 'Contents', 'Home', 'bin', 'java')
    executable(fallback_java, "#!/bin/zsh\nprint -r -- 'fake Java version 21' >&2\n")
    executable(File.join(@jdk, 'bin', 'java'), "#!/bin/zsh\nprint -r -- 'fake Java version 17' >&2\n")
    @env['FIXTURE_REQUIRE_JAVA21'] = '1'
    @env['FIXTURE_OLD_JAVA'] = File.realpath(@jdk)
    bootstrap_fixture
    output, result = interactive("\n", '--prepare')
    assert result.success?, output
    assert_includes output, '新命令行工具需要更高 Java'
    assert_equal 1, events.scan('repository2-3.xml').length
    refute_includes events, 'api.adoptium.net'
    assert_includes output, '--prepare 已完成'
  end
end
