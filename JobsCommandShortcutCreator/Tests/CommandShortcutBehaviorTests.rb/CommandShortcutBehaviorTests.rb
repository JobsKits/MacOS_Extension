# frozen_string_literal: true
# 编译真实业务逻辑并仅运行临时夹具；不注册扩展、不安装、不修改用户脚本或偏好。

require 'open3'
require 'tmpdir'
require 'securerandom'

module CommandShortcutBehaviorRunner
  ROOT = File.expand_path('../..', __dir__)

  def self.run
    sources = [
      'Shared/CommandShortcutContext/CommandShortcutContext.swift',
      'Shared/CommandShortcutRequest/CommandShortcutRequest.swift',
      'Shared/CommandShortcutFactories/CommandShortcutFactories.swift',
      'JobsCommandShortcutCreator/CommandShortcutService/CommandShortcutService.swift',
      'JobsCommandShortcutCreator/CommandShortcutController/CommandShortcutController.swift',
      'Tests/CommandShortcutBehaviorTests.swift/CommandShortcutBehaviorTests.swift'
    ].map { |path| File.join(ROOT, path) }
    Dir.mktmpdir('jobs-command-shortcut-build-') do |directory|
      test_suite = "com.jobs.command-shortcut.tests.#{SecureRandom.uuid}"
      environment = { 'JOBS_SHORTCUT_TEST_SUITE' => test_suite }
      localization = File.join(directory, 'CommandShortcutLocalization.swift')
      template = File.read(File.join(ROOT, 'Shared/CommandShortcutLocalization/CommandShortcutLocalization.swift'))
      raise '无法隔离测试偏好。' unless template.scan('com.jobs.finderextensions.managementpanel.preferences').length == 1
      File.write(localization, template.sub('com.jobs.finderextensions.managementpanel.preferences', test_suite))
      binary = File.join(directory, 'behavior-tests')
      output, result = Open3.capture2e('/usr/bin/xcrun', 'swiftc', *sources, localization, '-o', binary)
      abort output unless result.success?
      begin
        output, result = Open3.capture2e(environment, binary)
        puts output
        abort '脚本快捷入口隔离行为测试失败。' unless result.success?
      ensure
        cleanup, cleaned = Open3.capture2e(environment, binary, '--cleanup')
        abort cleanup unless cleaned.success?
      end
    end
    ui_sources = [
      'Shared/CommandShortcutFactories/CommandShortcutFactories.swift',
      'Shared/CommandShortcutLocalization/CommandShortcutLocalization.swift',
      'JobsCommandShortcutCreator/CommandShortcutDialog/CommandShortcutDialog.swift',
      'JobsCommandShortcutCreator/CommandShortcutInterface/CommandShortcutInterface.swift'
    ].map { |path| File.join(ROOT, path) }
    output, result = Open3.capture2e('/usr/bin/xcrun', 'swiftc', '-typecheck', *ui_sources)
    abort output unless result.success?
    puts 'PASS: native dialog typecheck'
  end
end

CommandShortcutBehaviorRunner.run if $PROGRAM_NAME == __FILE__
