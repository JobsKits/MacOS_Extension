# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'json'
require 'open3'
require 'timeout'

class FlutterRunnerLogTests < Minitest::Test
  HELPER = File.expand_path('../Scripts/FlutterRunner.jxa', __dir__)

  def setup
    @tmp = Dir.mktmpdir('jobs-flutter-log-')
    @log = File.join(@tmp, 'run.log')
    @exit = File.join(@tmp, 'exitcode')
  end

  def teardown
    FileUtils.remove_entry(@tmp)
  end

  def format(text)
    File.write(@log, text)
    out, err, result = Open3.capture3('/usr/bin/osascript', '-l', 'JavaScript', HELPER, 'format-log', @log)
    assert result.success?, err
    out
  end

  def test_success_and_warnings_are_distinct_from_machine_noise
    out = format(<<~LOG)
      Resolving dependencies...
      Downloading packages...
        analyzer 10.0.1 (14.6.0 available)
      Got dependencies!
      1 package is discontinued.
      1 package has newer versions incompatible with dependency constraints.
      [{"event":"daemon.connected","params":{"pid":12}}]
      [{"event":"device.removed","params":{"name":"unrelated phone"}}]
      [{"event":"app.start","params":{"deviceId":"sim","mode":"debug"}}]
      [{"event":"app.progress","params":{"appId":"a","id":"1","message":"Running Xcode build...","finished":false}}]
      [{"event":"app.progress","params":{"appId":"a","id":"1","finished":true}}]
      Xcode build done. 12.0s
      [{"event":"app.started","params":{"appId":"a"}}]
      Errored: 0
    LOG
    assert_includes out, '[依赖] 解析依赖'
    assert_includes out, '已折叠 1 条版本明细'
    assert_includes out, '[警告]'
    assert_includes out, '[进行] Xcode 编译'
    assert_includes out, '[进行] 正在确认构建结果'
    assert_includes out, '[成功] 应用已启动'
    refute_includes out, '[错误]'
    refute_includes out, '"event"'
    refute_includes out, 'unrelated phone'
  end

  def test_build_start_does_not_claim_success_and_errors_survive
    out = format(<<~'LOG')
      [{"event":"app.start","params":{"deviceId":"sim"}}]
      [{"event":"app.progress","params":{"appId":"a","id":"1","message":"Running Xcode build...","finished":false}}]
      [{"event":"app.progress","params":{"appId":"a","id":"1","finished":true}}]
      Xcode build done. 12.0s
      [{"event":"app.log","params":{"error":true,"log":"Compiler failed\n  at main.dart:12"}}]
      [{"id":1,"error":{"message":"reload denied"}}]
      [{"event":"new.protocol.event","params":{"detail":"keep me"}}]
      [{"event":"broken json"
      Error (Xcode): missing symbol
      #0 main (main.dart:12)
    LOG
    refute_includes out, '[成功]'
    refute_includes out, '[完成]'
    assert_includes out, '[错误] Compiler failed'
    assert_includes out, '[错误]   at main.dart:12'
    assert_includes out, 'reload denied'
    assert_includes out, 'keep me'
    assert_includes out, 'broken json'
    assert_includes out, 'missing symbol'
    assert_includes out, '#0 main'
  end

  def test_spm_warning_preserves_plugin_names_and_explanation
    out = format(<<~LOG)
      The following plugins do not support Swift Package Manager for ios:
        - plugin_a
        - plugin_b
      This will become an error in a future version of Flutter.
    LOG
    assert_includes out, 'CocoaPods'
    assert_includes out, 'plugin_a'
    assert_includes out, 'plugin_b'
    assert_includes out, '未来 Flutter'
    refute_includes out, '[错误]'
  end

  def test_known_macos_shortcuts_index_diagnostics_are_folded_once
    # 夹具取自现场日志，去掉旧格式化器添加的 [错误] / [日志] 标签。
    raw = <<~LOG
      Failed to index parameter type: <WFMailSenderPickerParameter: 0x10a7efd80> in is.workflow.actions.sendemail: (extension in ActionKit):__C.WFParameter.ToolKitConversionError.missingIntentDescription for locale: en
      Failed to index parameter type: <WFMailSenderPickerParameter: 0x10a7efd80> in is.workflow.actions.sendemail: (extension in ActionKit):__C.WFParameter.ToolKitConversionError.missingIntentDescription for locale: zh_CN
      Failed to index action parameter: <WFConfiguredSystemActionParameter: 0x10b1d4c00> due to (extension in ActionKit):__C.WFParameter.ToolKitConversionError.incompatibleParameterType(WFConfiguredSystemActionParameter)
      Failed to check availability in Spotlight for action is.workflow.actions.sendemail: Error Domain=NSOSStatusErrorDomain Code=-10814 "(null)" UserInfo={NSDebugDescription=Unable to find this application extension record in the Launch Services database.}
      Skipping: <WFUnionParameter: 0x109cc7900> in com.apple.MobileSMS.DraftMessageIntent because union values themselves are not treated as a type
      is.workflow.actions.conditional WFConditionalAction: Skipped because: [control flow]
      is.workflow.actions.sirikit.donation.handle WFHandleDonatedIntentAction: Skipped because: [donation-based action]
      Skipped: [donation-based action: 2, control flow: 4]
         donation-based action: 2
         control flow: 4
      Indexed: 100
      Errored: 0
      Bundle cache: 2 hits
      Finished in 1.2s
    LOG
    out = format(raw)
    assert_equal 1, out.scan('[提示] macOS 快捷指令 / Spotlight 系统索引诊断已折叠').length
    refute_includes out, '[错误]'
    refute_includes out, 'Failed to index'
    refute_includes out, 'NSOSStatusErrorDomain'
    refute_includes out, 'Skipping:'
    refute_includes out, 'Skipped:'
    refute_includes out, 'donation-based action:'
    refute_includes out, 'Indexed:'
    refute_includes out, 'Errored:'
    refute_includes out, 'Bundle cache:'
    refute_includes out, 'Finished in'
    assert_equal raw, File.read(@log), '折叠显示不得改写原始 run.log'
  end

  def test_unknown_and_real_build_errors_survive_system_index_filter
    lines = [
      '[WFCompiler] error: missing symbol in user source',
      'Failed to index parameter type: <WFUserParameter: 0x123> in user.compiler: unexpected conversion failure',
      'Failed to index parameter type: <WFUserParameter: 0x123> in user.compiler: ToolKitConversionError.userFailure',
      'Failed to index parameter type: <UserParameter: 0x123> in user.compiler: ToolKitConversionError.userFailure',
      'Failed to check availability in Spotlight for action is.workflow.actions.sendemail: Error Domain=NSOSStatusErrorDomain Code=-10815',
      'Failed to check availability in Spotlight for action user.action: Error Domain=NSOSStatusErrorDomain Code=-10814',
      'Error (Xcode): missing symbol',
      "lib/main.dart:12: Error: Type 'MissingType' not found.",
      'Errored: 2'
    ]
    out = format(lines.join("\n") + "\n")
    lines.each { |line| assert_includes out, "[错误] #{line}" }
    refute_includes out, '系统索引诊断已折叠'
  end

  def test_machine_app_errors_with_system_index_text_are_never_folded
    lines = [
      'Failed to index action parameter: <WFConfiguredSystemActionParameter: 0x10b1d4c00> due to (extension in ActionKit):__C.WFParameter.ToolKitConversionError.incompatibleParameterType(WFConfiguredSystemActionParameter)',
      'Failed to check availability in Spotlight for action is.workflow.actions.sendemail: Error Domain=NSOSStatusErrorDomain Code=-10814 "(null)"',
      '[WFCompiler] error: failed to compile application'
    ]
    events = lines.map { |line| [{ event: 'app.log', params: { error: true, log: line } }].to_json }
    out = format(events.join("\n") + "\n")
    lines.each { |line| assert_includes out, "[错误] #{line}" }
    refute_includes out, '系统索引诊断已折叠'
  end

  def test_stream_preserves_split_utf8_partial_lines_and_failure_exit
    File.write(@log, '')
    Open3.popen3('/usr/bin/osascript', '-l', 'JavaScript', HELPER, 'watch-log', @log, @exit) do |input, output, errors, process|
      input.close
      captured = String.new
      reader = Thread.new { captured << output.read }
      begin
        # 留出启动时间，再模拟 worker 将 UTF-8 中文字符分两次写入。
        sleep 0.5
        bytes = "错误：中文完整\n最后一行".b
        File.open(@log, 'ab') { |f| f.write(bytes.byteslice(0, 2)) }
        sleep 0.3
        File.open(@log, 'ab') { |f| f.write(bytes.byteslice(2..-1)) }
        sleep 0.3
        File.write(@exit, '7')
        Timeout.timeout(10) { process.value; reader.join }
        assert process.value.success?, errors.read
        assert_includes captured, '错误：中文完整'
        assert_includes captured, '最后一行'
        assert_includes captured, '[错误] Flutter 退出，退出码：7'
        assert_equal 1, captured.scan('最后一行').length
      ensure
        Process.kill('TERM', process.pid) if process.alive?
        reader.join(2)
      end
    end
  end
end
