# frozen_string_literal: true
# 桌面菜单已经聚合，验证原叶 ID 仍可独立选择、安装和卸载。
require_relative '../JobsDesktopTools/Tests/RootIntegrationAssertions'

class HarmonySimulatorInstallerIntegrationTests < Minitest::Test
  include DesktopRootIntegrationAssertions
  def desktop_leaf
    'harmony-simulator-create'
  end
end
