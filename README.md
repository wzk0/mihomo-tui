# 🧭 mihomo-tui

> mihomo（Clash.Meta）核心的终端控制台 —— 订阅管理、进程控制、控制器面板三合一，鼠标键盘都能用。

原 [clash_tui](https://github.com/wzk0/clash_tui) 的 Dart 重写版：内核换成 mihomo，界面重做成带侧栏的 TUI，并接入了 mihomo 的 RESTful 控制器。

```
 mihomo-tui v1.0                                                              运行中 v1.19.33
 ╭─ 导航 ───────────────╮ ╭─ 核心状态 ────────────────────────────────────────────────────────╮
 │> 概览              1 │ │ 二进制     /home/me/bin/mihomo                                    │
 │  订阅              2 │ │ 版本       v1.19.33                                               │
 │  代理              3 │ │ 进程       运行中 | pid 4242 | 已运行 1h 12m                       │
 │  日志              4 │ │ 配置       pm                                                     │
 │  设置              5 │ │ 端口       mixed 7890 | socks 7891                                │
 │                      │ │ 控制器     127.0.0.1:9090 | 已连接 v1.19.33                       │
 │                      │ │ 模式       rule                                                   │
 │                      │ │ 当前节点   香港 01                                                │
 │                      │ │ 流量       连接 14 | 上行 1.2 MB | 下行 8.4 MB                    │
 │                      │ ╰───────────────────────────────────────────────────────────────────╯
 │                      │ ╭─ 快捷操作 ────────────────────────────────────────────────────────╮
 │                      │ │ > 停止核心               结束 mihomo 进程                         │
 │                      │ │   重启核心               重新加载配置并重启进程                   │
 │                      │ │   切换模式：rule         当前模式                          当前  │
 │                      │ │   编辑生效配置           用编辑器打开 config.yaml                 │
 │                      │ │   切换系统代理           一键写入/撤销系统代理                    │
 │                      │ ╰───────────────────────────────────────────────────────────────────╯
 │──────────────────────│
 │ 状态    运行中       │
 │ 版本    v1.19.33     │
 │ 配置    pm           │
 │ 控制器  已连接       │
 ╰──────────────────────╯
  ↑↓ 选择操作  Enter 执行  s 启动/停止  R 重启  r 重载配置        Esc 侧栏 | h 后台 | ? 帮助
```

## ✨ 特性

- 📦 **订阅**：添加、更新、全部更新、重命名、删除、一键启用（自动备份 `config.yaml.bak`）；`e` 改订阅信息，`E` 改配置文件
- ⚙️ **核心**：自动探测 mihomo、后台启动（关掉 TUI 也不停）、停止、重启、热重载、日志查看
- 📊 **面板**：模式切换、当前节点、连接与流量、代理组/节点切换、单点/整组测速、延迟排序
- 🖱️ **交互**：鼠标点击、滚轮、双击启用；`>` 光标 + 加粗；`Tab` 切栏、`1-5` 跳页、`?` 帮助
- 🎨 **外观**：跟随终端深浅色，6 种强调色，不画背景色块，只显示终端自己的背景
- 🚀 **顺手事**：一键开关系统代理、一键开机自启（systemd 用户服务 / Windows 启动项）、复制代理环境变量
- 💾 **备份**：把设置、订阅索引和全部配置打包成 zip
- 🖥️ **平台**：Linux（amd64 / arm64 / armv7）与 Windows（amd64 / arm64），单文件无依赖

## 📥 安装

### 下载预编译版本

从 [Releases](../../releases) 下载对应平台，解压即用：

| 平台 | 文件 |
| --- | --- |
| 🐧 Linux x86_64 | `mihomo-tui-vX.Y-linux-amd64.tar.gz` |
| 🐧 Linux arm64 | `mihomo-tui-vX.Y-linux-arm64.tar.gz` |
| 🐧 Linux armv7 | `mihomo-tui-vX.Y-linux-armv7.tar.gz` |
| 🪟 Windows x64 | `mihomo-tui-vX.Y-windows-amd64.zip` |
| 🪟 Windows arm64 | `mihomo-tui-vX.Y-windows-arm64.zip` |

### 从源码构建

```sh
dart pub get
dart compile exe bin/mihomo_tui.dart -o build/mihomo-tui   # Windows 用 -o build/mihomo-tui.exe
./build/mihomo-tui
```

需要 Dart 3.5+。

## 🔌 内核

程序不内置内核，需要自己准备 mihomo 二进制。查找顺序：

`--bin` → 设置页 → `MIHOMO_BIN` → 程序目录 → `mihomo/`、`core/` 子目录 → `PATH` 与常见路径。

显式指定但文件不存在时会直接报错，不会悄悄换用别的内核。

## 🚀 使用

```sh
mihomo-tui
```

首次使用：`2` 进订阅页 → `a` 添加订阅 → `Enter` 启用 → `1` 回概览 → `s` 启动核心。

### ⌨️ 快捷键

| 位置 | 按键 | 作用 |
| --- | --- | --- |
| 全局 | `1`–`5` | 跳转 概览 / 订阅 / 代理 / 日志 / 设置 |
| 全局 | `Tab` | 侧栏与内容区切换 |
| 全局 | `h` | 隐藏面板，核心继续后台运行 |
| 全局 | `?` / `q` | 帮助 / 退出（核心不停） |
| 概览 | `↑↓` `jk` `g` `G` `Enter` | 选择并执行快捷操作 |
| 概览 | `s` `R` `r` `m` `o` `p` | 启动停止 / 重启 / 热重载 / 循环模式 / 面板 / 系统代理 |
| 订阅 | `Enter` / 双击 | 启用订阅 |
| 订阅 | `a` `u` `U` `r` `d` `i` | 添加 / 更新 / 全部更新 / 重命名 / 删除 / 详情 |
| 订阅 | `e` / `E` | 编辑订阅信息 / 编辑配置文件 |
| 代理 | `Tab` `←→` | 代理组与节点列切换 |
| 代理 | `Enter` / 点击 / `t` / `T` | 选择节点 / 测单点 / 测整组（`Esc` 取消） |
| 代理 | `s` | 排序：默认 → 延迟低到高 → 延迟高到低 |
| 日志 | `s` `f` `r` `c` `g` `G` | 密度（标准/精简/极简）/ 跟随 / 刷新 / 清空 / 首尾 |
| 设置 | `Enter` `d` `i` | 编辑或切换 / 重新检测核心 / 关于 |

弹窗内：`Tab` 换字段、`Enter` 提交、`Esc` 取消、`Ctrl+A/E/U/W/K` 行编辑。

## 📁 文件与目录

| 路径 | 内容 |
| --- | --- |
| `~/.config/mihomo-tui/`（Windows：`%APPDATA%\mihomo-tui\`） | 数据目录，`--data` 可覆盖 |
| `…/profiles/<名称>.yaml` | 每个订阅的原始配置 |
| `…/data.json` | 订阅索引与当前启用项 |
| `…/settings.json` | 内核路径、编辑器、下载代理、主题等 |
| `…/logs/mihomo.log` | 核心输出（超 5 MB 自动轮转） |
| `…/run/mihomo.pid` | 由本程序启动的核心进程号 |
| `~/.config/mihomo/config.yaml` | 核心读取的配置，`--home` 或 `MIHOMO_HOME` 可覆盖 |

订阅下载会遵守 `http_proxy` / `https_proxy`（回环地址除外），也可在设置里单独指定代理。

### 📤 导出

```sh
mihomo-tui --export               # ~/mihomo-tui-export-<时间戳>.zip
mihomo-tui --export backup.zip
```

内含 `manifest.json`、`settings.json`、`data.json`、`profiles/*.yaml`、`mihomo/config.yaml` 与一份说明。

## 💻 命令行

```sh
mihomo-tui --status [--json]     # 状态，退出码 0=运行中 1=未运行
mihomo-tui --list                # 订阅列表
mihomo-tui --info [名称]         # 订阅详情
mihomo-tui --start | --stop | --restart
mihomo-tui --export [路径]       # 导出数据
mihomo-tui --selftest            # 自检
mihomo-tui --import-legacy ./我的配置   # 导入旧版数据
```

通用参数：`--data`、`--home`、`--bin`、`--editor`。

## 🔁 从 clash_tui 迁移

```sh
mihomo-tui --import-legacy ./我的配置
```

订阅、地址、更新时间都会带过来，启用逻辑与旧版一致。

## 🛠️ 开发与发布

- `dart test` / `dart analyze` / `dart format`
- CI：`.github/workflows/build.yml`，矩阵编译 Linux amd64/arm64/armv7 与 Windows amd64/arm64
- 发布：推送 `v*` 标签自动构建并发 Release

```sh
git tag v1.0 && git push origin v1.0
```

## ⚠️ 已知限制

- 深浅色跟随依赖终端背景探测（OSC 11 / `COLORFGBG`），探测不到时默认按深色，可在设置里强制
- 系统代理一键开关支持 GNOME 与 Windows，其他桌面环境会提示手动配置
- 由其他工具（如 mihomo-party）启动的核心会标记为"外部进程"，停止前需要确认
- 代理页依赖配置里的 `external-controller`

## 🙏 致谢

思路来自 [wzk0/clash_tui](https://github.com/wzk0/clash_tui)，内核为 [MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo)。