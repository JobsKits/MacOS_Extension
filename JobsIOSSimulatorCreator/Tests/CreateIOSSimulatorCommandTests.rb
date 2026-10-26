# frozen_string_literal: true
# 两个入口共用的真实 zsh / 系统 JXA 隔离回归；命令与旧入口前置动作均替换为私有夹具。

require 'fileutils'
require 'json'
require 'minitest/autorun'
require 'open3'
require 'tmpdir'

class CreateIOSSimulatorCommandTests < Minitest::Test
  FINDER_SCRIPT = File.expand_path('../Scripts/CreateIOSSimulator.zsh', __dir__)
  SCRIPT = ENV.key?('JOBS_SIMULATOR_TEST_SCRIPT') ? File.expand_path(ENV.fetch('JOBS_SIMULATOR_TEST_SCRIPT')) : FINDER_SCRIPT
  SOURCE_SCRIPT = if ENV.key?('JOBS_SIMULATOR_SOURCE')
                    File.expand_path(ENV.fetch('JOBS_SIMULATOR_SOURCE'))
                  else
                    File.expand_path('../../../../JobsCommand@iOS/其他/【MacOS】📱双击初始化iOS模拟器.command/【MacOS】📱双击初始化iOS模拟器.command', __dir__)
                  end
  COMMON_BEGIN = '# >>> Jobs iOS simulator core >>>'
  COMMON_END = '# <<< Jobs iOS simulator core <<<'
  RUNTIME_PREFIX = 'com.apple.CoreSimulator.SimRuntime.'
  DEVICE_PREFIX = 'com.apple.CoreSimulator.SimDeviceType.'
  UDID = 'A1234567-1234-1234-1234-123456789ABC'
  UNCONFIRMED = '（未确认支持）'
  NO_RUNTIME = '（本机无可搭配系统）'

  # 构造完整但私有的 Xcode、simctl 与 Simulator 路径。
  def setup
    @root = File.realpath(Dir.mktmpdir('jobs-ios-simulator-test-'))
    @bin = File.join(@root, 'bin')
    @run = File.join(@root, 'run')
    @developer = File.join(@root, "Xcode 空格 ' $.app", 'Contents', 'Developer')
    @app = File.join(@developer, 'Applications', 'Simulator.app')
    FileUtils.mkdir_p([@bin, @run, File.join(@developer, 'usr', 'bin')])
    make_app(@app, 'com.apple.iphonesimulator', 'Simulator')
    File.write(File.join(@developer, 'usr', 'bin', 'simctl'), '')
    FileUtils.chmod(0o700, File.join(@developer, 'usr', 'bin', 'simctl'))
    @environment = {
      'HOME' => @root, 'TMPDIR' => @run + '/', 'PATH' => "#{@bin}:/usr/bin:/bin",
      'NO_COLOR' => '1', 'TEST_ROOT' => @root, 'TEST_DEVELOPER' => @developer,
      'TEST_TRACE' => File.join(@root, 'trace.jsonl'), 'TEST_UDID' => UDID
    }
    @runtimes = [runtime('18.0', 'iOS 18.0', ['iPhone-Old', 'iPad-Test']),
                 runtime('16.0', 'iOS 16.0')]
    @device_types = [device('iPhone Old', 'iPhone-Old', 18 * 65_536),
                     device('iPad Test', 'iPad-Test', 18 * 65_536, 'iPad'),
                     device('iPhone Future', 'iPhone-Future', 20 * 65_536),
                     device('iPhone Legacy', 'iPhone-Legacy', nil),
                     device('Apple TV', 'Apple-TV', nil, 'Apple TV')]
    save_catalog
    write_mock('xcrun', <<~'ZSH')
      printf '%s\0' xcrun "$@" >> "$TEST_TRACE"
      printf '\0' >> "$TEST_TRACE"
      if [[ "$1" == --find && "$2" == simctl ]]; then
        [[ "${TEST_FIND_FAIL:-0}" == 0 ]] || exit 13
        print -r -- "$TEST_DEVELOPER/usr/bin/simctl"
      elif [[ "$1" == simctl && "$2" == list ]]; then
        [[ "${TEST_LIST_FAIL:-}" != "$3" ]] || exit 15
        /bin/cat -- "$TEST_ROOT/$3.json"
      elif [[ "$1" == simctl && "$2" == create ]]; then
        if [[ -n "${TEST_CREATE_FAIL:-}" ]]; then
          print -ru2 -- "$TEST_CREATE_FAIL"
          exit 19
        fi
        print -r -- "${TEST_CREATE_OUTPUT:-$TEST_UDID}"
      elif [[ "$1" == simctl && "$2" == boot ]]; then
        [[ "${TEST_BOOT_FAIL:-0}" == 0 ]] || exit 21
      elif [[ "$1" == simctl && "$2" == bootstatus ]]; then
        [[ "${TEST_BOOTSTATUS_FAIL:-0}" == 0 ]] || exit 22
      else
        print -ru2 -- 'unexpected simctl fixture invocation'
        exit 64
      fi
    ZSH
    write_mock('open', <<~'ZSH')
      printf '%s\0' open "$@" >> "$TEST_TRACE"
      printf '\0' >> "$TEST_TRACE"
      [[ "${TEST_OPEN_FAIL:-0}" == 0 ]] || exit 23
    ZSH
    make_fzf
    @source = isolated_source(SCRIPT)
    @bootstrap = <<~'ZSH'
      setopt NO_NOMATCH PIPE_FAIL
      jobs_test_reject_legacy_wrapper() {
        printf '%s\0' legacy-wrapper "$1" >> "$TEST_TRACE"
        printf '\0' >> "$TEST_TRACE"
        print -ru2 -- "unexpected legacy wrapper action: $1"
        exit 97
      }
      cleanup_simulator_background_safely() {
        jobs_test_reject_legacy_wrapper cleanup_simulator_background_safely
      }
      install_homebrew() {
        jobs_test_reject_legacy_wrapper install_homebrew
      }
      install_fzf() {
        jobs_test_reject_legacy_wrapper install_fzf
      }
      SIM_RUN_DIR="$TEST_ROOT/run"
      SIM_APP="$TEST_DEVELOPER/Applications/Simulator.app"
      SIM_APP_KIND=com.apple.iphonesimulator
      SIM_RUNTIME_ID=com.apple.CoreSimulator.SimRuntime.iOS-18-0
      SIM_RUNTIME_NAME='iOS 18.0'
      SIM_DEVICE_ID=com.apple.CoreSimulator.SimDeviceType.iPhone-Old
      SIM_DEVICE_NAME='iPhone Old'
      SIM_NAME='iPhone Old@fixture'
    ZSH
  end

  # 只删除本测试创建的唯一私有目录。
  def teardown
    FileUtils.remove_entry(@root)
  end

  # 两个可独立复制的入口必须嵌入同一核心，缺少外仓时明确跳过跨仓一致性检查。
  def test_self_contained_entries_embed_identical_core_bytes
    require_source_script

    assert_equal common_core(SOURCE_SCRIPT), common_core(FINDER_SCRIPT), '两个入口的模拟器核心已分叉'
  end

  # 同一展示名、同一标识、不可用系统与其它架构均不会产生重复选择。
  def test_runtime_rows_deduplicate_and_filter_availability_platform_and_architecture
    @runtimes += [runtime('18.0.1', 'iOS 18.0', ['iPhone-Old'], identifier: 'iOS-18-0'),
                  runtime('17.0', 'iOS 17.0').merge('isAvailable' => false),
                  runtime('19.0', 'tvOS 19.0', identifier: 'tvOS-19-0'),
                  runtime('21.0', 'iOS 21.0').merge('supportedArchitectures' => ['x86_64'])]
    save_catalog
    output, status = execute('sim_data runtimes "$TEST_ROOT/runtimes.json" arm64')
    assert status.success?, output
    assert_equal ["iOS 18.0\t#{RUNTIME_PREFIX}iOS-18-0", "iOS 16.0\t#{RUNTIME_PREFIX}iOS-16-0"], output.lines.map(&:strip)
  end

  # 最新系统只列 Duo 时，型号列表仍保留可配其它系统的传统 iPhone 与 iPad。
  def test_duo_only_latest_runtime_does_not_hide_traditional_device_types
    use_duo_catalog
    output, status = execute('sim_data devicetypes "$TEST_ROOT/devicetypes.json"')
    assert status.success?, output
    assert_equal ["iPhone Old\t#{DEVICE_PREFIX}iPhone-Old", "iPad Test\t#{DEVICE_PREFIX}iPad-Test",
                  "iPhone Duo\t#{DEVICE_PREFIX}iPhone-Duo"], output.lines.map(&:strip)
    assert_empty trace
  end

  # 可搭配本机系统的型号排在前面；没有可搭配系统的型号保留但带标注。
  def test_preferred_device_types_prioritize_supported_then_unknown_without_hiding_models
    output, status = execute('sim_data preferred-devicetypes "$TEST_ROOT/devicetypes.json" "$TEST_ROOT/runtimes.json" arm64')
    assert status.success?, output
    assert_equal ['iPhone Old', 'iPad Test', 'iPhone Legacy', "iPhone Future#{NO_RUNTIME}"], row_names(output)
    assert_empty trace
  end

  # 新电脑只安装 Duo 专用系统时，首项改为 Duo，传统机型仍可手动选择。
  def test_duo_only_installed_runtime_makes_duo_default_and_retains_all_models
    use_duo_catalog
    @runtimes = [@runtimes.first]
    save_catalog
    output, status = execute('sim_data preferred-devicetypes "$TEST_ROOT/devicetypes.json" "$TEST_ROOT/runtimes.json" arm64')
    assert status.success?, output
    assert_equal ['iPhone Duo', "iPhone Old#{NO_RUNTIME}", "iPad Test#{NO_RUNTIME}"], row_names(output)
    assert_empty trace
  end

  # 只读汇总同时给出可搭配 / 无可搭配机型数量，以及每个系统支持的机型数。
  def test_catalog_summary_counts_matched_models_and_runtime_support
    @device_types = [device('iPhone Old', 'iPhone-Old', nil), device('iPhone Future', 'iPhone-Future', 20 * 65_536)]
    @runtimes = [runtime('18.0', 'iOS 18.0', ['iPhone-Old']), runtime('17.0', 'iOS 17.0')]
    save_catalog
    output, status = execute('sim_data catalog-summary "$TEST_ROOT/devicetypes.json" "$TEST_ROOT/runtimes.json" arm64')
    assert status.success?, output
    rows = output.lines.map(&:strip)
    assert_equal %w[models 2 1 1], rows[0].split("\t")
    assert_equal ["runtime\tiOS 18.0\t1", "runtime\tiOS 17.0\t-1"], rows[1..]
    assert_empty trace
  end

  # 已确认支持的系统优先于元数据未知的较新版本，同组仍按版本从新到旧。
  def test_compatible_runtimes_prioritize_known_support_and_exclude_known_incompatibility
    @device_types = [device('iPhone Old', 'iPhone-Old', nil)]
    @runtimes = [runtime('21.0', 'iOS 21.0', ['iPhone-Duo']),
                 runtime('20.0', 'iOS 20.0'),
                 runtime('19.0', 'iOS 19.0', ['iPhone-Old']),
                 runtime('18.0', 'iOS 18.0', ['iPhone-Old']),
                 runtime('17.0', 'iOS 17.0')]
    save_catalog
    output, status = compatible_runtimes
    assert status.success?, output
    assert_equal ['iOS 19.0', 'iOS 18.0', "iOS 20.0#{UNCONFIRMED}", "iOS 17.0#{UNCONFIRMED}"], row_names(output)
    assert_empty trace
  end

  # 未确认支持的系统在最终确认前明确提示风险，避免误以为一定可创建。
  def test_unconfirmed_runtime_warns_before_final_confirmation
    @device_types = [device('iPhone Old', 'iPhone-Old', nil)]
    @runtimes = [runtime('27.1', 'iOS 27.1')]
    save_catalog
    output, status = execute('sim_load_catalog && sim_select_combination && sim_prepare_unique_name && sim_confirm_creation',
                             input: "1\n1\n")
    assert_includes output, "iOS 27.1#{UNCONFIRMED}"
    assert_includes output, '未被 Xcode 明确列为支持该型号'
    assert_equal 130, status.exitstatus, output
    refute trace.any? { |entry| entry[2] == 'create' }
  end

  # 缺失、空或不完整白名单都不能当作明确不兼容而误删系统。
  def test_missing_empty_and_malformed_support_metadata_preserve_unknown_runtimes
    @device_types = [device('iPhone Old', 'iPhone-Old', nil)]
    [nil, [], {}, 'unknown', [{}], [{'identifier' => DEVICE_PREFIX + 'iPhone-Duo'}, {}]].each do |supported|
      @runtimes = [runtime('27.1', 'iOS 27.1')]
      @runtimes.first['supportedDeviceTypes'] = supported unless supported.nil?
      save_catalog
      output, status = compatible_runtimes
      assert status.success?, output
      assert_equal ["iOS 27.1#{UNCONFIRMED}"], row_names(output), "supportedDeviceTypes=#{supported.inspect}"
    end
    assert_empty trace
  end

  # 有效标识白名单既支持对象项，也支持字符串项；不包含所选型号时明确排除。
  def test_valid_support_identifier_whitelist_accepts_supported_and_rejects_other_models
    @device_types = [device('iPhone Old', 'iPhone-Old', nil)]
    @runtimes = [runtime('27.1', 'iOS 27.1', ['iPhone-Duo']), runtime('27.0', 'iOS 27.0')]
    @runtimes.last['supportedDeviceTypes'] = [DEVICE_PREFIX + 'iPhone-Old']
    save_catalog
    output, status = compatible_runtimes
    assert status.success?, output
    assert_equal ['iOS 27.0'], row_names(output)
    assert_empty trace
  end

  # Runtime 的明确白名单比型号通用版本范围更精确，支持结论不被旧范围推翻。
  def test_explicit_runtime_whitelist_takes_priority_over_device_version_bounds
    @device_types = [device('iPhone Old', 'iPhone-Old', 99 * 65_536)]
    @runtimes = [runtime('27.1', 'iOS 27.1', ['iPhone-Old'])]
    save_catalog
    output, status = compatible_runtimes
    assert status.success?, output
    assert_equal ['iOS 27.1'], row_names(output)
    @device_types.first.merge!('minRuntimeVersion' => 1, 'maxRuntimeVersion' => 99 * 65_536)
    @runtimes.first['supportedDeviceTypes'] = [{'identifier' => DEVICE_PREFIX + 'iPhone-Duo'}]
    save_catalog
    output, status = compatible_runtimes
    assert status.success?, output
    assert_empty output.strip
    assert_empty trace
  end

  # 数字和字符串版本范围均包含端点，补丁版本仍精确区分。
  def test_device_version_bounds_include_endpoints_and_exclude_outside_versions
    @runtimes = [runtime('27.2', 'iOS 27.2'), runtime('27.1.1', 'iOS 27.1.1'),
                 runtime('27.1', 'iOS 27.1'), runtime('27.0', 'iOS 27.0')]
    [{'minRuntimeVersion' => 27 * 65_536 + 256, 'maxRuntimeVersion' => 27 * 65_536 + 257},
     {'minRuntimeVersionString' => '27.1', 'maxRuntimeVersionString' => '27.1.1'}].each do |bounds|
      @device_types = [device('iPhone Old', 'iPhone-Old', nil).merge(bounds)]
      save_catalog
      output, status = compatible_runtimes
      assert status.success?, output
      assert_equal ["iOS 27.1.1#{UNCONFIRMED}", "iOS 27.1#{UNCONFIRMED}"], row_names(output)
    end
    assert_empty trace
  end

  # 损坏或相互矛盾的范围不构成可靠的否定证据。
  def test_invalid_or_contradictory_version_bounds_do_not_hide_runtimes
    @runtimes = [runtime('27.1', 'iOS 27.1')]
    [{'minRuntimeVersion' => -1, 'maxRuntimeVersionString' => 'unknown'},
     {'minRuntimeVersion' => 99 * 65_536, 'maxRuntimeVersion' => 1}].each do |bounds|
      @device_types = [device('iPhone Old', 'iPhone-Old', nil).merge(bounds)]
      save_catalog
      output, status = compatible_runtimes
      assert status.success?, output
      assert_equal ["iOS 27.1#{UNCONFIRMED}"], row_names(output)
    end
    assert_empty trace
  end

  # 缺失或空白名单，以及已知和未知版本范围，均留给 create 最终校验。
  def test_runtime_support_metadata_and_version_bounds_do_not_hide_device_types
    @device_types[0].merge!('minRuntimeVersion' => 99 * 65_536, 'maxRuntimeVersion' => 1,
                            'minRuntimeVersionString' => '99.0', 'maxRuntimeVersionString' => '1.0')
    [nil, []].each do |supported|
      if supported.nil?
        @runtimes[0].delete('supportedDeviceTypes')
      else
        @runtimes[0]['supportedDeviceTypes'] = supported
      end
      save_catalog
      output, status = execute('sim_data devicetypes "$TEST_ROOT/devicetypes.json"')
      assert status.success?, output
      assert_equal ['iPhone Old', 'iPad Test', 'iPhone Future', 'iPhone Legacy'],
                   output.lines.map { |line| line.split("\t").first }
    end
    assert_empty trace
  end

  # 新版家族字段变化不隐藏具名机型，同一标识去重，其它设备家族仍排除。
  def test_device_types_use_names_across_family_schema_changes_and_deduplicate_identifiers
    @device_types = [device('iPhone Old', 'iPhone-Old', nil, 1),
                     device('iPad Test', 'iPad-Test', nil, nil),
                     device('iPhone Duo', 'iPhone-Duo', nil, 'future-family'),
                     device('iPhone Duplicate', 'iPhone-Old', nil),
                     device('Apple TV', 'Apple-TV', nil, 'iPhone')]
    @device_types[1].delete('productFamily')
    save_catalog
    output, status = execute('sim_data devicetypes "$TEST_ROOT/devicetypes.json"')
    assert status.success?, output
    assert_equal ['iPhone Old', 'iPad Test', 'iPhone Duo'], output.lines.map { |line| line.split("\t").first }
    assert_empty trace
  end

  # 同一个 Runtime 标识使用首条记录，与展示去重保持一致。
  def test_duplicate_runtime_identifier_does_not_break_selection
    @runtimes << runtime('18.0.1', 'iOS 18.0.1', ['iPhone-Future'], identifier: 'iOS-18-0')
    save_catalog
    output, status = execute('sim_data runtimes "$TEST_ROOT/runtimes.json" arm64')
    assert status.success?, output
    assert_equal ["iOS 18.0\t#{RUNTIME_PREFIX}iOS-18-0", "iOS 16.0\t#{RUNTIME_PREFIX}iOS-16-0"], output.lines.map(&:strip)
  end

  # 错误 JSON 与带控制字符的数据均阻断进入创建。
  def test_malformed_json_and_control_characters_are_rejected
    File.write(File.join(@root, 'runtimes.json'), 'not-json')
    output, status = execute('sim_data runtimes "$TEST_ROOT/runtimes.json" arm64')
    refute status.success?, output
    @runtimes[0]['name'] = "iOS 18.0\nINJECTED"
    save_catalog
    output, status = execute('sim_data runtimes "$TEST_ROOT/runtimes.json" arm64')
    refute status.success?, output
    assert_empty trace
  end

  # 已有不可用设备的名称也参与冲突保护。
  def test_unique_name_checks_all_existing_devices
    File.write(File.join(@root, 'devices.json'), JSON.generate('devices' => {'unused-runtime' => [
      {'name' => 'iPhone@fixture', 'isAvailable' => false}, {'name' => 'iPhone@fixture (2)'}
    ]}))
    output, status = execute('sim_data unique-name "$TEST_ROOT/devices.json" iPhone@fixture')
    assert status.success?, output
    assert_equal 'iPhone@fixture (3)', output.strip
  end

  # fzf 返回不属于清单的行时直接失败，不能读取数字或采用首项。
  def test_unknown_fzf_row_stops_without_numeric_fallback
    output, status = execute(<<~'ZSH', input: "2\n", env: {'TEST_FZF_UNKNOWN' => '1'})
      sim_choose_row '选择' $'One\tid-one\nTwo\tid-two' || exit $?
      print -r -- "SELECTED|$SIM_SELECTED_ROW"
    ZSH
    assert_equal 1, status.exitstatus, output
    assert_includes output, '选择结果不属于当前清单'
    refute_includes output, 'SELECTED|'
    assert_empty trace
  end

  # 缺少 fzf 即安全停止，输入编号也不能绕过依赖检查。
  def test_missing_fzf_stops_without_numeric_fallback
    FileUtils.rm_f(File.join(@bin, 'fzf'))
    output, status = execute("sim_choose_row '选择' $'One\\tid-one'", input: "1\n")
    assert_equal 1, status.exitstatus, output
    assert_includes output, 'fzf 缺失或不可用，已停止交互选择'
    refute_includes output, '输入编号'
    assert_empty trace
  end

  # 选择器取消或没有匹配项时不能选中第一项。
  def test_cancel_and_no_matches_never_select_or_create
    %w[130 1].each do |result|
      output, status = execute("sim_choose_row '选择' $'One\\tid-one'", env: {'TEST_FZF_CANCEL_RESULT' => result})
      assert_equal 130, status.exitstatus, output
    end
    assert_empty trace
  end

  # 损坏的 fzf 明确失败；健康 fzf 按 Esc 可取消。
  def test_fzf_health_failure_and_cancellation
    make_fzf
    output, status = execute('sim_check_selector', env: {'TEST_FZF_BAD' => '1'})
    assert_equal 1, status.exitstatus, output
    assert_includes output, 'fzf 缺失或不可用，已停止交互选择'
    output, status = execute('SIM_FZF="$TEST_ROOT/bin/fzf"; sim_choose_row 选择 $\'One\\tid-one\'', env: {'TEST_FZF_CANCEL' => '1'})
    assert_equal 130, status.exitstatus, output
  end

  # 共享交互路由传播缺失选择器的失败，不读取清单或执行创建。
  def test_interactive_entry_propagates_missing_fzf_before_catalog_and_creation
    FileUtils.rm_f(File.join(@bin, 'fzf'))
    output, status = execute('sim_prepare_context; SIM_MODE=interactive; sim_run_requested_action')
    assert_equal 1, status.exitstatus, output
    assert_includes output, 'fzf 缺失或不可用，已停止交互选择'
    refute trace.any? { |entry| %w[list create boot bootstatus].include?(entry[2]) }
    refute trace.any? { |entry| entry[0] == 'legacy-wrapper' }
  end

  # 只读清单检查无需选择器，也不触发依赖安装。
  def test_read_only_check_without_fzf_remains_available
    FileUtils.rm_f(File.join(@bin, 'fzf'))
    output, status = execute('main --check')
    assert status.success?, output
    assert_includes output, '只读体检完成'
    refute trace.any? { |entry| %w[create boot bootstatus].include?(entry[2]) }
    refute trace.any? { |entry| entry[0] == 'legacy-wrapper' }
  end

  # 健康 fzf 的输出必须精确匹配原清单，再交给创建流程。
  def test_healthy_fzf_returns_a_catalog_row
    make_fzf
    output, status = execute(<<~'ZSH')
      SIM_FZF="$TEST_ROOT/bin/fzf"
      sim_choose_row '选择' $'One\tid-one\nTwo\tid-two' || exit $?
      print -r -- "SELECTED|$SIM_SELECTED_ROW"
    ZSH
    assert status.success?, output
    assert_includes output, "SELECTED|One\tid-one"
    assert_empty trace
  end

  # 真实只读入口必须只调用 --find / list；临时快照在退出时移除，不产生日志。
  def test_check_entry_reads_catalog_and_cleans_snapshots_without_mutation
    output, status = execute('main --check')
    assert status.success?, output
    assert_includes output, '完整机型清单：4 个 iPhone / iPad'
    assert_includes output, '可用系统：iOS 18.0'
    refute_includes output, '个兼容'
    assert_includes output, '只读体检完成'
    assert trace.all? { |entry| entry[0] == 'xcrun' && (entry[1] == '--find' || entry[2] == 'list') }, trace.inspect
    assert_empty remaining_run_files
    refute_includes output, "\e["
  end

  # 只读体检提前展示全部回车会采用的组合，但完整型号总数保持不变。
  def test_check_entry_reports_compatible_enter_default_without_mutation
    use_duo_catalog
    @runtimes = [@runtimes.first]
    save_catalog
    output, status = execute('main --check')
    assert status.success?, output
    assert_includes output, '完整机型清单：3 个 iPhone / iPad'
    assert_includes output, '✔ 回车首选组合：iPhone Duo / iOS 27.1'
    assert trace.all? { |entry| entry[0] == 'xcrun' && (entry[1] == '--find' || entry[2] == 'list') }, trace.inspect
    assert_empty remaining_run_files
  end

  # 帮助与无效参数在旧入口的清场、Homebrew 和 fzf 安装流程之前返回。
  def test_help_and_invalid_arguments_do_not_run_legacy_wrapper_or_probe_environment
    %w[--help -h].each do |option|
      output, status = execute("main #{option}")
      assert status.success?, output
      assert_includes output, '--check'
      assert_empty trace
      assert_empty remaining_run_files
    end
    output, status = execute('main --unexpected-option')
    assert_equal 64, status.exitstatus, output
    assert_includes output, '参数无效'
    assert_empty trace
    assert_empty remaining_run_files
  end

  # 整份脚本复制到复杂路径后仍能独立读取帮助，路径和日志名取真实入口。
  def test_complete_script_copied_to_special_character_path_runs_help_independently
    copied_path = File.join(@root, "可独立复制 空格 ' $.command")
    FileUtils.cp(SCRIPT, copied_path)
    output, status = Open3.capture2e(@environment, '/bin/zsh', copied_path, '--help', chdir: @root)
    assert status.success?, output
    assert_includes output, copied_path
    basename = File.basename(copied_path, '.command')
    assert_match(/日志位置：#{Regexp.escape(@run)}\/+#{Regexp.escape(basename)}\.\d+\.log/, output)
    refute_includes output, 'sim_prepare_context'
    assert_empty trace
    assert_empty remaining_run_files
  end

  # 独立入口仅在交互确认后按原顺序初始化，然后进入公共选择与创建流程。
  def test_initialization_wrapper_preserves_legacy_preflight_order
    output, status = execute(initialization_fixture, source: initialization_source)
    assert status.success?, output
    assert_equal initialization_steps.map { |step| ['initialization', step] }, trace
  end

  # 体检、清场或依赖步骤失败后立即返回，不能继续安装或进入创建流程。
  def test_initialization_wrapper_propagates_preflight_and_creation_failures
    source = initialization_source
    initialization_steps.drop(1).each do |failed|
      output, status = execute(initialization_fixture, source: source, env: {'TEST_INITIALIZATION_FAIL' => failed})
      assert_equal 71, status.exitstatus, output
      expected = initialization_steps.take(initialization_steps.index(failed) + 1)
      assert_equal expected.map { |step| ['initialization', step] }, trace
    end
  end

  # 独立入口的只读模式直接进入公共路由，保留其退出码，不触发前置动作。
  def test_initialization_wrapper_read_only_modes_bypass_legacy_preflight
    source = initialization_source
    %w[help check].each do |mode|
      output, status = execute(<<~ZSH, source: source)
        : > "$TEST_TRACE"
        sim_run_requested_action() {
          printf '%s\\0' core-read-only "$SIM_MODE" >> "$TEST_TRACE"
          printf '\\0' >> "$TEST_TRACE"
          return 37
        }
        SIM_MODE=#{mode}
        run_initialization_requested_action
      ZSH
      assert_equal 37, status.exitstatus, output
      assert_equal [['core-read-only', mode]], trace
    end
  end

  # 系统未安装 Runtime 与清单读取失败均不得触发创建。
  def test_missing_runtime_and_list_failure_stop_before_creation
    @runtimes = []
    save_catalog
    output, status = execute('main --check')
    refute status.success?, output
    assert_includes output, '没有本机可用'
    output, status = execute('main --check', env: {'TEST_LIST_FAIL' => 'runtimes'})
    refute status.success?, output
    assert_includes output, '读取模拟器清单失败'
    refute trace.any? { |entry| entry[2] == 'create' }
  end

  # 未安装 Runtime 时交互流程也必须停止，不能用虚构的默认系统创建。
  def test_missing_runtime_stops_enter_only_flow_before_selection_and_creation
    @runtimes = []
    save_catalog
    output, status = execute('sim_load_catalog && sim_interactive_loop', input: "\n\n\n")
    refute status.success?, output
    assert_includes output, '没有本机可用'
    refute_includes output, '➤ 选择 iPhone / iPad 型号'
    refute trace.any? { |entry| entry[2] == 'create' }
  end

  # 手动选择本机无兼容系统的型号时，在系统列表与创建确认前停止；不自动重弹列表。
  def test_device_with_no_compatible_installed_runtime_stops_before_creation
    use_duo_catalog
    @runtimes = [@runtimes.first]
    save_catalog
    ["\n", "yes\n", " \n", ''].each do |input|
      output, status = execute(': > "$TEST_TRACE"; sim_load_catalog && sim_interactive_loop', input: input,
                               env: {'TEST_FZF_ROWS' => '2'})
      refute status.success?, output
      assert_includes output, '没有可搭配的已安装 iOS 系统'
      refute_includes output, '➤ 选择 iOS 系统版本'
      assert_equal 1, output.scan('➤ 选择 iPhone / iPad 型号').length, output
      refute trace.any? { |entry| entry[2] == 'create' }
    end
  end

  # 选到无系统机型后只有精确 r 才回到机型选择，并能继续完成一次创建。
  def test_model_without_runtime_returns_to_selection_only_after_explicit_retry
    use_duo_catalog
    @runtimes = [@runtimes.first]
    save_catalog
    output, status = execute(': > "$TEST_TRACE"; sim_load_catalog && sim_interactive_loop', input: "r\n\n",
                             env: {'TEST_FZF_ROWS' => '2 1 1'})
    assert status.success?, output
    assert_includes output, '没有可搭配的已安装 iOS 系统'
    assert_equal 2, output.scan('➤ 选择 iPhone / iPad 型号').length, output
    assert_equal 1, output.scan('➤ 选择 iOS 系统版本').length, output
    creates = trace.select { |entry| entry[2] == 'create' }
    assert_equal 1, creates.length, trace.inspect
    assert_equal [DEVICE_PREFIX + 'iPhone-Duo', RUNTIME_PREFIX + 'iOS-27-1'], creates.first.last(2)
    refute_includes creates.first[3], NO_RUNTIME
  end

  # 只读体检给出可搭配 / 无可搭配机型数量，以及每个系统支持的机型数。
  def test_check_entry_reports_matched_model_counts_and_runtime_support
    use_duo_catalog
    output, status = execute('main --check')
    assert status.success?, output
    assert_includes output, '完整机型清单：3 个 iPhone / iPad'
    assert_includes output, '其中 3 个已有可搭配系统，0 个本机无可搭配系统'
    assert_includes output, '可用系统：iOS 27.1（支持 1 个机型）'
    assert_includes output, '可用系统：iOS 27.0（支持 2 个机型）'
    assert_empty remaining_run_files
  end

  # 缺少 iPhone / iPad 类型时，体检与交互均停止，不把其它家族当作可创建型号。
  def test_empty_device_catalog_stops_check_and_selection_before_creation
    @device_types = [device('Apple TV', 'Apple-TV', nil, 'Apple TV')]
    save_catalog
    ['main --check', 'sim_load_catalog && sim_interactive_loop'].each do |code|
      output, status = execute(code)
      refute status.success?, output
      assert_includes output, '没有 iPhone / iPad 设备类型'
    end
    refute trace.any? { |entry| entry[2] == 'create' }
  end

  # 默认入口拒绝无 TTY，确认前不探测工具链，也不写日志。
  def test_interactive_entry_rejects_non_tty_before_any_business
    output, status = execute('main')
    refute status.success?, output
    assert_includes output, '没有可交互终端'
    assert_empty trace
    assert_empty remaining_run_files
  end

  # create / boot / open / bootstatus 顺序与独立参数必须保持完整。
  def test_create_and_boot_pass_arguments_without_shell_evaluation
    dangerous_name = "iPhone ' $(touch SHOULD_NOT_EXIST)"
    @environment['TEST_NAME'] = dangerous_name
    output, status = execute('SIM_NAME="$TEST_NAME"; sim_create_and_boot')
    assert status.success?, output
    assert_equal ['xcrun', 'simctl', 'create', dangerous_name, DEVICE_PREFIX + 'iPhone-Old', RUNTIME_PREFIX + 'iOS-18-0'], trace[0]
    assert_equal ['xcrun', 'simctl', 'boot', UDID], trace[1]
    assert_equal ['open', '-a', @app], trace[2]
    assert_equal ['xcrun', 'simctl', 'bootstatus', UDID], trace[3]
    refute File.exist?(File.join(@root, 'SHOULD_NOT_EXIST'))
  end

  # 仅明确的组合不兼容返回回选状态，其它失败停止。
  def test_create_failure_only_retries_explicit_incompatibility
    output, status = execute('sim_create_and_boot', env: {'TEST_CREATE_FAIL' => 'Incompatible device'})
    assert_equal 2, status.exitstatus, output
    ['Unable to create a device for device type iPhone', 'CoreSimulator service unavailable'].each do |error|
      output, status = execute('sim_create_and_boot', env: {'TEST_CREATE_FAIL' => error})
      assert_equal 1, status.exitstatus, output
      refute_includes output, '组合不受支持'
    end
    assert trace.all? { |entry| entry[2] == 'create' }
  end

  # 失败输出或非 UUID 成功输出不能被当作新设备继续启动。
  def test_invalid_udid_stops_before_boot
    output, status = execute('sim_create_and_boot', env: {'TEST_CREATE_OUTPUT' => 'warning text'})
    refute status.success?, output
    assert_includes output, 'UDID 无效'
    assert_equal 1, trace.length
  end

  # 新设备启动失败时保留设备，禁止删除、关闭或重新创建。
  def test_boot_failure_preserves_created_device_and_reports_udid
    output, status = execute('sim_create_and_boot', env: {'TEST_BOOT_FAIL' => '1'})
    refute status.success?, output
    assert_includes output, '新设备已保留'
    assert_includes output, UDID
    assert_equal %w[create boot], trace.map { |entry| entry[2] }
  end

  # GUI 打开失败与启动等待失败均如实失败，并保留已创建的设备。
  def test_gui_and_bootstatus_failures_do_not_claim_completed_startup
    [{'TEST_OPEN_FAIL' => '1'}, {'TEST_BOOTSTATUS_FAIL' => '1'}].each do |env|
      output, status = execute('sim_create_and_boot', env: env)
      refute status.success?, output
      refute_includes output, '新模拟器已完成启动'
    end
    refute trace.any? { |entry| %w[delete shutdown erase].include?(entry[2]) }
  end

  # 新版 Xcode Device Hub 在同一 Xcode 内查找，核验 Bundle ID 及实际可执行文件。
  def test_device_hub_new_xcode_layout_and_bundle_validation
    FileUtils.remove_entry(@app)
    hub = File.join(File.dirname(@developer), 'Applications', 'DeviceHub.app')
    make_app(hub, 'com.apple.dt.Devices', 'DevicesTrampoline')
    output, status = execute('sim_check_environment; print -r -- "APP|$SIM_APP|$SIM_APP_KIND"')
    assert status.success?, output
    assert_includes output, "APP|#{hub}|com.apple.dt.Devices"
    File.write(File.join(hub, 'Contents', 'Info.plist'), app_plist('example.wrong', 'DevicesTrampoline'))
    output, status = execute('sim_check_environment')
    refute status.success?, output
    assert_includes output, '缺少健康'
  end

  # 最终确认任意非空输入和 EOF 都取消，含空格也不能绕过。
  def test_final_confirmation_cancels_nonempty_and_eof
    ["no\n", " \n", ''].each do |input|
      output, status = execute('sim_confirm_creation', input: input)
      assert_equal 130, status.exitstatus, output
    end
    assert_empty trace
  end

  # 完整选择循环只新增一次，名称包含进程编号以避免同秒并发碰撞。
  def test_complete_selection_flow_creates_once_with_process_suffix
    output, status = execute('sim_load_catalog && sim_interactive_loop', input: "\n")
    assert status.success?, output
    creates = trace.select { |entry| entry[2] == 'create' }
    assert_equal 1, creates.length
    assert_match(/iPhone Old@\d{4}\.\d\d\.\d\d \d\d:\d\d:\d\d-\d+\z/, creates.first[3])
    assert_includes output, '新模拟器已完成启动'
  end

  # 健康 fzf 正常流程只各显示一次型号和系统选择，并且只创建一次。
  def test_complete_healthy_fzf_flow_selects_each_list_once_and_creates_once
    make_fzf
    output, status = execute('SIM_FZF="$TEST_ROOT/bin/fzf"; sim_load_catalog && sim_interactive_loop',
                             input: "\n", env: {'TEST_FZF_TRACE' => '1'})
    assert status.success?, output
    selections = trace.select { |entry| entry[0] == 'fzf' }
    assert_equal 2, selections.length, selections.inspect
    assert_equal ['--prompt=选择 iPhone / iPad 型号 > ', '--prompt=选择 iOS 系统版本 > '],
                 selections.map { |entry| entry.find { |argument| argument.start_with?('--prompt=') } }
    assert_equal 1, trace.count { |entry| entry[2] == 'create' }
    assert_includes output, '新模拟器已完成启动'
  end

  # 两个已装系统分别支持传统型号与 Duo 时，全部回车可直接创建传统型号 + 27.0。
  def test_enter_only_flow_selects_traditional_iphone_with_compatible_older_runtime
    use_duo_catalog
    output, status = execute('sim_load_catalog && sim_interactive_loop', input: "\n\n\n")
    assert status.success?, output
    assert_includes output, '选择 iOS 系统版本'
    assert_operator output.index('选择 iPhone / iPad 型号'), :<, output.index('选择 iOS 系统版本')
    creates = trace.select { |entry| entry[2] == 'create' }
    assert_equal 1, creates.length
    assert_equal [DEVICE_PREFIX + 'iPhone-Old', RUNTIME_PREFIX + 'iOS-27-0'], creates.first.last(2)
    assert_includes output, '新模拟器已完成启动'
  end

  # 只安装 Duo 专用系统的新电脑，全部回车直接选择 Duo + 27.1，并且只创建一次。
  def test_enter_only_flow_defaults_to_duo_when_it_is_the_only_supported_model
    use_duo_catalog
    @runtimes = [@runtimes.first]
    save_catalog
    output, status = execute('sim_load_catalog && sim_interactive_loop', input: "\n\n\n")
    assert status.success?, output
    creates = trace.select { |entry| entry[2] == 'create' }
    assert_equal 1, creates.length
    assert_equal [DEVICE_PREFIX + 'iPhone-Duo', RUNTIME_PREFIX + 'iOS-27-1'], creates.first.last(2)
    assert_equal 1, output.scan('➤ 选择 iPhone / iPad 型号').length, output
    assert_equal 1, output.scan('➤ 选择 iOS 系统版本').length, output
    assert_includes output, '新模拟器已完成启动'
  end

  # 健康 fzf 的首项也使用兼容组合，重现用户回车选中最新不兼容系统的现场。
  def test_healthy_fzf_defaults_to_compatible_runtime_for_traditional_iphone
    use_duo_catalog
    make_fzf
    output, status = execute('SIM_FZF="$TEST_ROOT/bin/fzf"; sim_load_catalog && sim_interactive_loop',
                             input: "\n", env: {'TEST_FZF_TRACE' => '1'})
    assert status.success?, output
    creates = trace.select { |entry| entry[2] == 'create' }
    assert_equal 1, creates.length
    assert_equal [DEVICE_PREFIX + 'iPhone-Old', RUNTIME_PREFIX + 'iOS-27-0'], creates.first.last(2)
    assert_equal 2, trace.count { |entry| entry[0] == 'fzf' }
    assert_includes output, '新模拟器已完成启动'
  end

  # 用户 fzf 的反序 / 查询配置不能改变回车首选组合，父 Shell 原配置仍保留。
  def test_fzf_user_defaults_cannot_change_enter_default_or_mutate_parent_environment
    use_duo_catalog
    options_file = File.join(@root, '个人 fzf 选项.conf')
    File.write(options_file, "--tac\n--query=Duo\n")
    write_mock('fzf', <<~'ZSH')
      if [[ -n "${FZF_DEFAULT_OPTS+x}" || -n "${FZF_DEFAULT_OPTS_FILE+x}" ]]; then
        print -ru2 -- 'unexpected inherited fzf default options'
        exit 41
      fi
      for arg in "$@"; do
        [[ "$arg" != --expect=left ]] || print -r -- ''
      done
      /usr/bin/head -n 1
    ZSH
    output, status = execute(<<~'ZSH', input: "\n", env: {'FZF_DEFAULT_OPTS' => '--tac --query=Duo', 'FZF_DEFAULT_OPTS_FILE' => options_file})
      SIM_FZF="$TEST_ROOT/bin/fzf"
      sim_load_catalog && sim_interactive_loop || exit $?
      print -r -- "PARENT_OPTIONS|${FZF_DEFAULT_OPTS}|${FZF_DEFAULT_OPTS_FILE}"
    ZSH
    assert status.success?, output
    creates = trace.select { |entry| entry[2] == 'create' }
    assert_equal 1, creates.length
    assert_equal [DEVICE_PREFIX + 'iPhone-Old', RUNTIME_PREFIX + 'iOS-27-0'], creates.first.last(2)
    assert_includes output, "PARENT_OPTIONS|--tac --query=Duo|#{options_file}"
    assert_includes output, '新模拟器已完成启动'
  end

  # 在选择或最终确认取消均不创建设备。
  def test_complete_selection_flow_cancels_before_mutation
    [1, 2, 0].each do |cancel_at|
      output, status = execute('sim_load_catalog && sim_interactive_loop', input: " \n",
                               env: {'TEST_FZF_CANCEL_AT' => cancel_at.to_s})
      assert status.success?, output
      assert_includes output, '已取消，未创建模拟器'
    end
    refute trace.any? { |entry| entry[2] == 'create' }
  end

  # 明确不兼容也不自动回选；回车、任意其它输入和 EOF 都保留失败并停止。
  def test_incompatible_create_stops_without_explicit_retry
    ["\n", "yes\n", "r \n", " r\n", ''].each do |retry_input|
      output, status = execute(': > "$TEST_TRACE"; sim_load_catalog && sim_interactive_loop',
                               input: "\n" + retry_input,
                               env: {'TEST_CREATE_FAIL' => 'Incompatible device'})
      refute status.success?, output
      assert_includes output, '组合不受支持'
      assert_equal 1, output.scan('➤ 选择 iPhone / iPad 型号').length, output
      assert_equal 1, output.scan('➤ 选择 iOS 系统版本').length, output
      assert_equal 1, trace.count { |entry| entry[2] == 'create' }, trace.inspect
    end
  end

  # 只有精确 r / R 才进入第二轮，随后取消不会再次创建。
  def test_incompatible_create_returns_to_selection_only_after_explicit_retry
    %w[r R].each do |retry_input|
      output, status = execute(': > "$TEST_TRACE"; sim_load_catalog && sim_interactive_loop',
                               input: "\n#{retry_input}\n",
                               env: {'TEST_CREATE_FAIL' => 'Incompatible device', 'TEST_FZF_CANCEL_AT' => '3'})
      assert status.success?, output
      assert_includes output, '组合不受支持'
      assert_includes output, '已取消，未创建模拟器'
      refute_includes output, '请输入列表内的编号'
      assert_equal 2, output.scan('➤ 选择 iPhone / iPad 型号').length, output
      assert_equal 1, output.scan('➤ 选择 iOS 系统版本').length, output
      assert_equal 1, trace.count { |entry| entry[2] == 'create' }, trace.inspect
    end
  end

  # fzf 创建失败后继续回车也只能显示首轮两个列表，不会因重选重新创建。
  def test_incompatible_create_with_fzf_and_enter_stops_after_one_selection_round
    make_fzf
    output, status = execute('SIM_FZF="$TEST_ROOT/bin/fzf"; sim_load_catalog && sim_interactive_loop',
                             input: "\n\n", env: {'TEST_FZF_TRACE' => '1', 'TEST_CREATE_FAIL' => 'Incompatible device'})
    refute status.success?, output
    selections = trace.select { |entry| entry[0] == 'fzf' }
    assert_equal 2, selections.length, selections.inspect
    assert_equal 1, output.scan('➤ 选择 iPhone / iPad 型号').length, output
    assert_equal 1, output.scan('➤ 选择 iOS 系统版本').length, output
    assert_equal 1, trace.count { |entry| entry[2] == 'create' }
  end

  # 泛化创建失败可能来自服务或组件问题，不能把它当成兼容错误重新弹出列表。
  def test_generic_create_error_stops_without_reselection
    output, status = execute('sim_load_catalog && sim_interactive_loop', input: "\n\n",
                             env: {'TEST_CREATE_FAIL' => 'Unable to create a device for device type iPhone: CoreSimulator service unavailable'})
    refute status.success?, output
    refute_includes output, '组合不受支持'
    assert_includes output, '创建未成功确认'
    assert_equal 1, output.scan('➤ 选择 iPhone / iPad 型号').length, output
    assert_equal 1, output.scan('➤ 选择 iOS 系统版本').length, output
    assert_equal 1, trace.count { |entry| entry[2] == 'create' }
  end

  # 泛化创建失败即使预留 r 输入，也不得触发兼容性重选。
  def test_generic_create_error_does_not_offer_retry
    output, status = execute('sim_load_catalog && sim_interactive_loop', input: "\nr\n",
                             env: {'TEST_CREATE_FAIL' => 'Unable to create a device for device type'})
    refute status.success?, output
    refute_includes output, '组合不受支持'
    assert_equal 1, output.scan('➤ 选择 iPhone / iPad 型号').length, output
    assert_equal 1, trace.count { |entry| entry[2] == 'create' }
  end

  # 阻塞的外部命令被限定等待，避免损坏工具无限挂起。
  def test_command_timeout_is_bounded
    output, status = execute('sim_run_to_file "$TEST_ROOT/run/command.out" 0 /bin/sleep 10')
    assert_equal 124, status.exitstatus, output
    assert_includes output, '等待超过'
  end

  # Runtime 左键返回型号，重新选择只在最终确认后创建一次。
  def test_runtime_left_returns_to_model_before_any_creation
    make_fzf
    output, status = execute('SIM_FZF="$TEST_ROOT/bin/fzf"; sim_load_catalog && sim_interactive_loop',
                             input: "\n", env: {'TEST_FZF_TRACE' => '1', 'TEST_FZF_BACK_ONCE' => '1'})
    assert status.success?, output
    assert_includes output, '已返回型号选择，未创建模拟器'
    selections = trace.select { |entry| entry[0] == 'fzf' }
    assert_equal 4, selections.length
    assert_equal 2, selections.count { |entry| entry.include?('--expect=left') }
    assert_equal 1, trace.count { |entry| entry[2] == 'create' }
  end

  # 子层返回后在型号层取消，不能执行创建或启动。
  def test_cancel_after_runtime_left_does_not_create
    make_fzf
    output, status = execute('SIM_FZF="$TEST_ROOT/bin/fzf"; sim_load_catalog && sim_interactive_loop',
                             env: {'TEST_FZF_BACK_ONCE' => '1', 'TEST_FZF_CANCEL_AFTER_BACK' => '1'})
    assert status.success?, output
    assert_includes output, '已取消，未创建模拟器'
    refute trace.any? { |entry| %w[create boot bootstatus].include?(entry[2]) }
  end

  # fzf 在无匹配项时左键会以 1 退出，明确返回键仍应返回型号。
  def test_runtime_left_with_no_matches_returns_instead_of_cancelling
    make_fzf
    output, status = execute('SIM_FZF="$TEST_ROOT/bin/fzf"; sim_load_catalog && sim_interactive_loop',
                             input: "\n", env: {'TEST_FZF_BACK_ONCE' => '1', 'TEST_FZF_BACK_RESULT' => '1'})
    assert status.success?, output
    assert_includes output, '已返回型号选择，未创建模拟器'
    assert_equal 1, trace.count { |entry| entry[2] == 'create' }
  end

  # 选择器异常保留失败状态，不进入创建，也不伪装成用户取消。
  def test_fzf_failure_propagates_without_creation
    make_fzf
    output, status = execute('SIM_FZF="$TEST_ROOT/bin/fzf"; sim_load_catalog && sim_interactive_loop',
                             env: {'TEST_FZF_FAILURE' => '42'})
    assert_equal 42, status.exitstatus, output
    assert_includes output, '选择器执行失败（退出码 42）'
    refute trace.any? { |entry| %w[create boot bootstatus].include?(entry[2]) }
  end

  private

  # 比较列表的可见条目，完整 argv 另由创建 trace 核对。
  def row_names(output)
    output.lines.map { |line| line.strip.split("\t").first }
  end

  # 使用固定夹具型号读取可搭配系统，不访问真实 Xcode。
  def compatible_runtimes
    execute('sim_data compatible-runtimes "$TEST_ROOT/runtimes.json" arm64 "$TEST_ROOT/devicetypes.json" com.apple.CoreSimulator.SimDeviceType.iPhone-Old')
  end

  # 核心退出清理可以连同空临时目录一起移除；两种结果都不应留下日志或快照。
  def remaining_run_files
    File.directory?(@run) ? Dir.children(@run) : []
  end

  # 去掉脚本最后的自动入口，设备命令固定替换为私有替身。
  def isolated_source(path)
    source = File.read(path)
    raise "缺少预期的脚本入口：#{path}" unless source.sub!(/^main "\$@"\s*\z/, '')

    source.gsub('/usr/bin/xcrun', File.join(@bin, 'xcrun')).gsub('/usr/bin/open', File.join(@bin, 'open'))
  end

  # 缺失独立脚本时只跳过其包装层检查，不影响右键核心的本地验证。
  def initialization_source
    require_source_script

    isolated_source(SOURCE_SCRIPT)
  end

  # 默认外仓可缺省，显式指定的规范源不存在则直接报告配置错误。
  def require_source_script
    return if File.file?(SOURCE_SCRIPT)

    flunk "显式指定的 JOBS_SIMULATOR_SOURCE 不存在或不是文件：#{SOURCE_SCRIPT}" if ENV.key?('JOBS_SIMULATOR_SOURCE')
    skip "未找到独立入口 #{SOURCE_SCRIPT}；可通过 JOBS_SIMULATOR_SOURCE 指定规范源"
  end

  # 这里只验证入口编排，所有步骤都替换成私有 trace，不执行原清场或安装。
  def initialization_fixture
    <<~'ZSH'
      : > "$TEST_TRACE"
      jobs_test_initialization_step() {
        printf '%s\0' initialization "$1" >> "$TEST_TRACE"
        printf '\0' >> "$TEST_TRACE"
        [[ "${TEST_INITIALIZATION_FAIL:-}" != "$1" ]] || return 71
        return 0
      }
      sim_initialize_runtime() { jobs_test_initialization_step initialize; }
      sim_check_environment() { jobs_test_initialization_step environment; }
      cleanup_simulator_background_safely() { jobs_test_initialization_step cleanup; }
      install_homebrew() { jobs_test_initialization_step homebrew; }
      install_fzf() { jobs_test_initialization_step fzf; }
      sim_check_selector() { jobs_test_initialization_step selector; }
      sim_load_catalog() { jobs_test_initialization_step catalog; }
      sim_interactive_loop() { jobs_test_initialization_step interactive; }
      SIM_MODE=interactive
      run_initialization_requested_action
    ZSH
  end

  # 独立初始化入口的预期执行顺序，用于成功与失败边界检查。
  def initialization_steps
    %w[initialize environment cleanup homebrew fzf selector catalog interactive]
  end

  # 按唯一边界提取原始字节，不归一化空白或换行，避免细微修改静默分叉。
  def common_core(path)
    content = File.binread(path)
    first = (COMMON_BEGIN + "\n").b
    last = (COMMON_END + "\n").b
    assert_equal 1, content.scan(first).length, "核心起始标记必须唯一：#{path}"
    assert_equal 1, content.scan(last).length, "核心结束标记必须唯一：#{path}"
    start = content.index(first) + first.bytesize
    finish = content.index(last)
    assert_operator finish, :>, start, "核心标记顺序无效或内容为空：#{path}"
    content.byteslice(start, finish - start)
  end

  # 最新 Runtime 的型号白名单与完整 devicetypes 不一致的跨机器问题夹具。
  def use_duo_catalog
    @runtimes = [runtime('27.1', 'iOS 27.1', ['iPhone-Duo']),
                 runtime('27.0', 'iOS 27.0', ['iPhone-Old', 'iPad-Test'])]
    @device_types = [device('iPhone Old', 'iPhone-Old', 18 * 65_536),
                     device('iPad Test', 'iPad-Test', 18 * 65_536, 'iPad'),
                     device('iPhone Duo', 'iPhone-Duo', 27 * 65_536)]
    save_catalog
  end

  # 生成 Runtime 夹具，nil 表示旧版 Xcode 缺少 supportedDeviceTypes。
  def runtime(version, name, devices = nil, identifier: nil)
    value = {'name' => name, 'version' => version, 'isAvailable' => true,
             'identifier' => RUNTIME_PREFIX + (identifier || "iOS-#{version.tr('.', '-')}"),
             'supportedArchitectures' => ['arm64', 'x86_64']}
    value['supportedDeviceTypes'] = devices.map { |d| {'identifier' => DEVICE_PREFIX + d} } unless devices.nil?
    value
  end

  # 生成设备类型夹具。
  def device(name, identifier, minimum, family = 'iPhone')
    value = {'name' => name, 'identifier' => DEVICE_PREFIX + identifier, 'productFamily' => family}
    value['minRuntimeVersion'] = minimum unless minimum.nil?
    value
  end

  # 写入 simctl 原生 JSON 格式。
  def save_catalog
    File.write(File.join(@root, 'runtimes.json'), JSON.generate('runtimes' => @runtimes))
    File.write(File.join(@root, 'devicetypes.json'), JSON.generate('devicetypes' => @device_types))
    File.write(File.join(@root, 'devices.json'), JSON.generate('devices' => {}))
  end

  # 为 NSBundle 核验准备一个最小合法应用包。
  def make_app(path, identifier, executable)
    FileUtils.mkdir_p(File.join(path, 'Contents', 'MacOS'))
    File.write(File.join(path, 'Contents', 'Info.plist'), app_plist(identifier, executable))
    File.write(File.join(path, 'Contents', 'MacOS', executable), "#!/bin/zsh\nexit 0\n")
    FileUtils.chmod(0o700, File.join(path, 'Contents', 'MacOS', executable))
  end

  # 使用明确的包字段，避免测试依赖本机已安装应用。
  def app_plist(identifier, executable)
    %(<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>#{identifier}</string><key>CFBundleExecutable</key><string>#{executable}</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>)
  end

  # 写入私有 zsh 假命令，避免 Ruby 启动体检反向调用被替换的 xcrun。
  def write_mock(name, body)
    path = File.join(@bin, name)
    File.write(path, "#!/bin/zsh\n" + body)
    FileUtils.chmod(0o700, path)
  end

  # fzf 的版本探测、返回与 Esc 取消均在私有进程中模拟。
  def make_fzf
    write_mock('fzf', <<~'ZSH')
      if [[ "$1" == --version ]]; then
        [[ "${TEST_FZF_BAD:-0}" == 0 ]]
        exit $?
      fi
      if [[ "${TEST_FZF_TRACE:-0}" == 1 ]]; then
        printf '%s\0' fzf "$@" >> "$TEST_TRACE"
        printf '\0' >> "$TEST_TRACE"
      fi
      round=0
      [[ ! -f "$TEST_ROOT/fzf-round" ]] || round="$(<"$TEST_ROOT/fzf-round")"
      (( round++ ))
      print -r -- "$round" > "$TEST_ROOT/fzf-round"
      [[ -z "${TEST_FZF_CANCEL_RESULT:-}" ]] || exit "$TEST_FZF_CANCEL_RESULT"
      [[ "${TEST_FZF_CANCEL_AT:-0}" != "$round" ]] || exit 130
      [[ "${TEST_FZF_CANCEL:-0}" == 0 ]] || exit 130
      [[ "${TEST_FZF_FAILURE:-0}" == 0 ]] || exit "$TEST_FZF_FAILURE"
      if [[ "${TEST_FZF_UNKNOWN:-0}" == 1 ]]; then
        print -r -- unknown-row
        exit 0
      fi
      if [[ -f "$TEST_ROOT/fzf-returned" && "${TEST_FZF_CANCEL_AFTER_BACK:-0}" == 1 ]]; then
        exit 130
      fi
      for arg in "$@"; do
        if [[ "$arg" == --expect=left ]]; then
          if [[ "${TEST_FZF_BACK_ONCE:-0}" == 1 && ! -f "$TEST_ROOT/fzf-returned" ]]; then
            : > "$TEST_ROOT/fzf-returned"
            print -r -- left
            exit "${TEST_FZF_BACK_RESULT:-0}"
          fi
          print -r -- ''
        fi
      done
      row_choices=(${=TEST_FZF_ROWS})
      row_index="${row_choices[round]:-1}"
      /usr/bin/sed -n "${row_index}p"
    ZSH
  end

  # 执行真实函数正文；设备命令、GUI 及旧入口的清场和安装函数均由夹具隔离。
  def execute(code, input: '', env: {}, source: @source)
    FileUtils.mkdir_p(@run)
    FileUtils.rm_f([File.join(@root, 'fzf-round'), File.join(@root, 'fzf-returned')])
    Open3.capture2e(@environment.merge(env), '/bin/zsh', '-c', source + "\n" + @bootstrap + "\n" + code,
                   stdin_data: input, chdir: @root)
  end

  # 读取完整 argv，以发现命令拼接或意外写操作。
  def trace
    return [] unless File.exist?(@environment['TEST_TRACE'])
    File.binread(@environment['TEST_TRACE']).force_encoding(Encoding::UTF_8).split("\0\0").map { |record| record.split("\0") }
  end
end
