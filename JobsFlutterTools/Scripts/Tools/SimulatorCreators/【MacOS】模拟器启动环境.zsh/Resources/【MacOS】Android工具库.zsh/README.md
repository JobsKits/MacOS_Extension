# Android 工具库

从 Jobs 的 `CreateAndroidSimulator.zsh` 受控提取函数与常量，移除入口执行，仅由模拟器启动环境模块在隔离子 Shell 中调用准备函数。不会调用新建流程。
