# 工程依赖工具链模块

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

## 🔥 <span id="前言">前言</span>

供 [分层依赖内核](../ProjectDependencies.zsh) 加载的函数模块，服务一键配置和独立依赖入口；不直接运行，加载时不执行安装。上级入口见 [Tools 说明](../README.md)。

## 一、工具准备与作用范围 <a href="#前言">🔼</a> <a href="#🔚">🔽</a>

- [**Node.js**](https://nodejs.org/)：按 `.nvmrc`、`.node-version` 和 `engines.node` 检查 Node 与同套 npm。优先复用健康候选；精确版本从官方归档下载并校验 SHA-256，保存到用户缓存；其它版本约束可使用已有 Homebrew。安装后重新读取版本并验证约束，失败停止。
- npm / pnpm / Yarn：按唯一锁文件及 `packageManager` 选择。缺少指定版本时安装到用户独立版本目录，不改全局 npm 或项目版本声明；未锁定且无健康工具时停止，避免猜测最新版。
- [**OpenHarmony**](https://www.openharmony.cn/)：发现 DevEco / CLT，检查 SDK 组件以及 Node、OHPM、Hvigor、HDC、Java 的实际可运行性。只改变当前进程环境；失败尝试恢复本次激活前的环境，再允许重新选择。专有组件和许可通过华为官方安装 / SDK Manager 完成，之后在原流程复检。
- [**Swift Package Manager**](https://www.swift.org/documentation/package-manager/)：定位当前 Flutter / Xcode 使用的 SourcePackages，把它连接到项目 `.jobs/dependencies/spm`。相对链接可随工程迁移；已有目录先完整预检冲突，再融合并保留备份。异常链接、越界或内容冲突均停止。

安装前显示来源、版本和目标位置，保留现有确认及 SDK 获取重试规则。不会改系统代理、Shell 配置、全局 SDK 或工程签名；取消和复检失败不继续下游构建。

## 二、验证边界 <a href="#前言">🔼</a> <a href="#🔚">🔽</a>

配套回归使用临时工程、假命令及隔离环境检查健康复用、缺失安装、安装失败、复检失败、取消与缓存冲突。源码检查和隔离回归不代表已安装的 Finder 菜单资源更新，也不代表真实 SDK 下载、签名或用户工程构建通过。

<a id="🔚" href="#前言">返回前言</a>
