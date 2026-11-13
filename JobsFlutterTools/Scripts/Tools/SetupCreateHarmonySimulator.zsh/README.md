# Flutter 工具随包新建 Harmony 模拟器

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

> [随包脚本](./SetupCreateHarmonySimulator.zsh) 复用[桌面创建内核](../../../../JobsHarmonySimulatorCreator/Scripts/CreateHarmonySimulator.zsh)，内容逐字节一致，随 `Tools` 资源复制到本次 [**Flutter**](https://flutter.dev/) 终端请求。

## 一、<span id="usage">运行与影响</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

```shell
/bin/zsh ./SetupCreateHarmonySimulator.zsh --create
/bin/zsh ./SetupCreateHarmonySimulator.zsh --prepare
/bin/zsh ./SetupCreateHarmonySimulator.zsh --check
```

- `--create` 选择设备类型、已下载 Release 镜像和唯一名称，最终确认后创建并核验实例，再交给 [**HarmonyOS**](https://developer.huawei.com/consumer/cn/) 官方工具启动；不覆盖、删除或重置已有设备。
- 首屏回车继续，非空输入 / `Ctrl+C` 取消。缺工具或镜像时保留桌面入口的准备、下载、持续重试、许可和账号授权流程。`--prepare` 只准备工具和镜像，`--check` / `--help` 只读。
- 支持 `--name 名称`、`--no-start`，以及 `HARMONY_EMULATOR_BIN`、`DEVECO_STUDIO_HOME` / `TOOL_HOME` 显式工具来源；日志位置显示在终端。
- 运行器在调用结束后重新查询设备；官方启动命令返回不等于开机完成，尚未出现时等待后重新加载。取消不视为创建成功。

**终端配色保护：** 独立运行时，在支持完整保存与恢复配色的交互终端中临时使用黑底白字及统一强调色；正常结束、失败或可捕获中断后恢复进入前的配色，不修改终端全局偏好或 Shell 启动配置。不支持完整保护、无交互终端、`NO_COLOR`、既有纯文本模式和 Sourcetree 场景不切换配色，并沿用纯文本输出约定。强制终止（如 `kill -9`）无法由脚本自身保证恢复，请使用运行时显示的独立恢复入口。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
