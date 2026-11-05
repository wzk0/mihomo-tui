# mihomo-tui

> [mihomo](https://github.com/MetaCubeX/mihomo)（Clash.Meta）核心的终端控制台：订阅管理、进程控制、控制器面板三合一，鼠标与键盘都能操作。

本仓库是原 [clash_tui](https://github.com/wzk0/clash_tui)（Python）的 Dart 重写版：核心由 clash 换成 mihomo，界面重做成带侧栏的 TUI，并接入了 mihomo 的 RESTful 控制器。

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
 │                      │ │ 控制面板   https://metacubex.github.io/metacubexd/?hostname=1~    │
 │                      │ │ 流量       连接 14 | 上行 1.2 MB | 下行 8.4 MB                    │
 │                      │ ╰───────────────────────────────────────────────────────────────────╯
 │                      │ ╭─ 快捷操作 ────────────────────────────────────────────────────────╮
 │                      │ │ > 停止核心               结束 mihomo 进程                         │
 │                      │ │   重启核心               重新加载配置并重启进程                   │
 │                      │ │   重新加载配置           让运行中的 mihomo 热重载 config.yaml     │
 │                      │ │   切换模式：rule         当前模式                          当前  │
 │                      │ │   编辑生效配置           用编辑器打开核心读取的 config.yaml        │
 │                      │ │   切换系统代理           一键写入/撤销 GNOME 或 Windows 系统代理  │
 │                      │ ╰───────────────────────────────────────────────────────────────────╯
 │──────────────────────│
 │ 状态    运行中       │
 │ 版本    v1.19.33     │
 │ 配置    pm           │
 │ 控制器  已连接       │
 ╰──────────────────────╯
  ↑↓ 选择操作  Enter 执行  s 启动/停止  R 重启  r 重载配置        Esc 侧栏 | h 后台 | ? 帮助
```

## 特性

**界面**

- 不涂任何背景色（终端透明）：只画文字、边框与强调色；深浅配色跟随终端（OSC 11 → `COLORFGBG` → 默认深色，可在设置里强制）
- 6 种强调色（蓝 / 紫 / 绿 / 橙 / 青 / 玫红），取值类文字（路径、端口、订阅名）用强调色的同色系变体，不再出现固定的青色
- 光标与悬停只用 `>` 标记 + 加粗，**不绘制任何背景色块**，不会盖住边框或破坏终端背景
- 布局只有一层边框：视图自己拥有外框，订阅页的列表与详情是两块独立的卡片；界面只用窄字符（`-`、`|`、`~` 代替 `—`、`·`、`…`）
- 渲染层对非 ASCII 字形单独定位并先清空占位：即使终端把 emoji / 旗帜 / 组合 emoji 渲染成与 wcwidth 不同的宽度，行内对齐和边框也不会错位（滚动时不会留下残字）
- 鼠标：移到行上即移动光标，点击选中，滚轮滚动（光标跟随），双击订阅行直接启用，侧栏悬停高亮
- 键盘：方向键 / `hjkl` / `g` `G`、`Tab` 切焦点、`1-5` 跳页、`?` 帮助浮层
- 弹窗表单支持输入框（CJK 光标定位、长文本横向滚动跟随光标、`Ctrl+A/E/U/W/K` 行编辑）、复选框、校验提示、`Esc` 取消

**订阅**

- 添加（地址 + 名称，下载后校验 YAML 与节点数）、更新、全部更新、重命名、删除
- `e` 编辑订阅信息（名称 / 订阅地址，可勾选保存后重新下载）；`E` 编辑订阅配置文件（`profiles/<名称>.yaml`）
- 启用 = 复制为 mihomo 的 `config.yaml`，原文件自动备份为 `config.yaml.bak`
- 列表显示节点数、端口、更新时间；列表卡片占满剩余空间，详情卡片固定在底部、按内容取最小高度（`i` 可看完整字段）

**核心**

- 自动探测 mihomo 可执行文件与版本，支持多平台路径规则（见下文）
- 后台启动（POSIX 用 `nohup` 脱离终端，Windows 用 `CreateProcess` 重定向日志），关掉 TUI 核心继续跑
- 停止 / 重启 / 热重载；启动失败时直接弹出日志片段
- 一键开启/关闭系统代理（Linux GNOME `gsettings`、Windows 注册表 + WinINet 刷新；关闭前二次确认）
- 开机自启：设置里一键安装/卸载「随登录启动 mihomo」的服务（Linux 为 systemd 用户服务，Windows 为注册表 Run 项），状态实时显示
- 日志三档密度、按级别着色、跟随/滚动/清空，滚动条画在边框列上

**控制器**

- 状态卡：进程、端口、控制器连通性、模式、当前节点（自动解析嵌套分组，显示最终叶子节点）、面板地址、连接数与流量
- 一键切换 `rule / global / direct`、打开 metacubexd 面板、复制 `export *_proxy` 环境变量
- 代理组 / 节点两栏：两侧都用 `>` 标出光标（组列表的 `>` 同时表示右侧正在展示、对应当前节点的组），`*` 表示正在使用的节点
- 回车或鼠标点击节点即切换；`t` 测单节点延迟，`T` 测整组（并发、进度显示在标题、`Esc` 取消）
- `s` 循环节点排序：默认顺序 → 延迟低到高 → 延迟高到低（可用节点在前，超时/未测/子组依次靠后）

## 安装

### 下载预编译版本

从 [Releases](../../releases) 下载对应平台：

| 平台 | 文件 |
| --- | --- |
| Linux x86_64 | `mihomo-tui-<版本>-linux-amd64.tar.gz` |
| Linux arm64 | `mihomo-tui-<版本>-linux-arm64.tar.gz` |
| Linux armv7 | `mihomo-tui-<版本>-linux-armv7.tar.gz` |
| Windows x64 | `mihomo-tui-<版本>-windows-amd64.zip` |
| Windows arm64 | `mihomo-tui-<版本>-windows-arm64.zip` |

解压后是单个可执行文件，无运行时依赖。

### 从源码构建

```sh
dart pub get
dart compile exe bin/mihomo_tui.dart -o build/mihomo-tui      # Windows 用 -o build/mihomo-tui.exe
./build/mihomo-tui
```

需要 Dart 3.5+。

## 内核（mihomo）

程序**不内置**内核，需要自己准备 mihomo 二进制。查找顺序：

1. `--bin <路径>`（命令行）
2. 设置页里的「mihomo 可执行文件」
3. 环境变量 `MIHOMO_BIN`
4. 程序所在目录下的 `mihomo` / `mihomo.exe`
5. 程序目录或当前目录的 `mihomo/`、`core/`、`resources/`、`bin/` 子目录里以 `mihomo` 开头的文件（例如 `mihomo/mihomo-linux-amd64-compatible`）
6. `mihomo/` 配置目录、`PATH`、`~/.local/bin`、`/usr/local/bin`、`/usr/bin`

显式指定（1–3 项）但文件不存在时不会退回自动探测，而是直接报错，避免"以为用上了某个内核"。

## 用法

```sh
mihomo-tui            # 进入 TUI
```

首次使用：`2` 进订阅页 → `a` 添加订阅 → `Enter` 启用 → `1` 回概览 → `s` 启动核心。

### 快捷键

| 位置 | 按键 | 作用 |
| --- | --- | --- |
| 全局 | `1`–`5` | 直接跳到概览 / 订阅 / 代理 / 日志 / 设置 |
| 全局 | `?` | 快捷键帮助浮层 |
| 全局 | `h` | 隐藏面板（核心继续后台运行） |
| 全局 | `q` / `Ctrl+C` | 退出程序（核心不停） |
| 侧栏 | `↑↓` `jk` / `Enter` / 点击 | 选择页面 / 进入内容区（悬停只高亮，不切页） |
| 内容区 | `Esc` | 回到侧栏 |
| 内容区 | `Tab` | 切到侧栏（代理页的 `Tab` 用于切换两栏） |
| 概览 | `↑↓` `jk` `g` `G` | 在快捷操作之间移动 |
| 概览 | `s` `R` `r` `m` `o` `p` | 启动停止 / 重启 / 热重载 / 循环模式 / 打开面板 / 切换系统代理 |
| 概览 | `Enter` | 执行选中的操作（含「编辑生效配置」「切换系统代理」） |
| 订阅 | `Enter` / 双击 | 启用选中订阅 |
| 订阅 | `a` `u` `U` `r` `d` `i` | 添加 / 更新 / 全部更新 / 重命名 / 删除 / 详情 |
| 订阅 | `e` / `E` | 编辑订阅信息（名称 / 地址）/ 编辑订阅配置文件 |
| 代理 | `Tab` 或 `←→` | 代理组与节点列切换 |
| 代理 | `Enter` / 点击 / `t` / `T` | 选择节点 / 测单节点 / 测整组（`Esc` 取消） |
| 代理 | `s` | 循环节点排序（默认 / 延迟低到高 / 延迟高到低） |
| 日志 | `s` | 循环视图密度：标准 → 精简 → 极简 |
| 日志 | `f` `r` `c` `g` `G` | 跟随 / 刷新 / 清空 / 跳到首尾 |
| 设置 | `Enter` | 编辑条目 / 循环主题色 / 明暗模式 / 开机自启 / 导出数据 |
| 设置 | `d` `i` | 重新检测核心 / 关于 |

弹窗内：`Tab` 换字段、`Enter` 提交、`Esc` 取消、`Ctrl+A/E/U/W/K` 行编辑。列表都支持鼠标滚轮（光标跟随）。

## 文件与目录

| 路径 | 内容 |
| --- | --- |
| `~/.config/mihomo-tui/`（Windows：`%APPDATA%\mihomo-tui\`） | 数据目录，可用 `--data` 覆盖 |
| `…/profiles/<名称>.yaml` | 每个订阅的原始配置 |
| `…/data.json` | 订阅列表与当前启用项（兼容旧版裸数组格式） |
| `…/settings.json` | 内核路径、配置目录、编辑器、下载代理、主题色、明暗模式 |
| `…/logs/mihomo.log` | 核心 stdout/stderr（超过 5 MB 自动轮转为 `.1`） |
| `…/run/mihomo.pid` | 由本程序启动的核心进程号 |
| `~/.config/mihomo/config.yaml` | 核心实际读取的配置，可用 `--home` 或 `MIHOMO_HOME` 覆盖 |

订阅下载遵守 `http_proxy` / `https_proxy`（回环地址不走代理），也可以在设置里单独指定「下载代理」。UA 默认为 `clash.meta/mihomo-tui`，方便机场按 Clash 配置返回。

### 导出数据

设置页的「导出数据」或在命令行：

```sh
mihomo-tui --export                 # 写到 ~/mihomo-tui-export-<时间戳>.zip
mihomo-tui --export backup.zip      # 指定路径
```

压缩包内容：

```
manifest.json        版本、平台、导出时间、路径、当前订阅、主题
settings.json        全部设置
data.json            订阅索引
profiles/*.yaml      每个订阅的原始配置
mihomo/config.yaml   正在使用的核心配置（如果存在）
README.txt           说明与恢复提示
```

## 命令行

不需要 TTY 的子命令，适合脚本：

```sh
mihomo-tui --status              # 输出状态；退出码 0=运行中 1=未运行
mihomo-tui --status --json       # 机器可读
mihomo-tui --list                # 订阅列表
mihomo-tui --info [名称]         # 订阅详情（缺省为当前启用项）
mihomo-tui --start | --stop | --restart
mihomo-tui --export [路径]       # 打包设置与全部配置
mihomo-tui --selftest            # 内置自检（CI 用）
mihomo-tui --import-legacy ./我的配置   # 导入旧版 clash_tui 的数据
```

全局参数：`--data <目录>`、`--home <目录>`、`--bin <路径>`、`--editor <命令>`。

## 从 clash_tui 迁移

旧版把订阅存在 `我的配置/config/<名称>`，索引在 `我的配置/data.json`：

```sh
mihomo-tui --import-legacy ./我的配置
```

导入后订阅出现在列表里，URL、更新时间保持不变；启用逻辑与旧版一致（写入 mihomo 的 `config.yaml`）。

## 构建与发布

`.github/workflows/build.yml`：

- `test`：`dart format --set-exit-if-changed` + `dart analyze --fatal-infos` + `dart test` + 编译后跑 `--version` / `--selftest` 冒烟
- `build`：矩阵编译 4 个原生目标（Linux amd64 / arm64、Windows amd64 / arm64）
- `build-linux-armv7`：GitHub 没有 32 位 ARM runner，用 `docker run --platform linux/arm/v7` + qemu 跑 Dart 的 linux-arm SDK 编译（标记 `continue-on-error`，失败不影响其他产物）
- `release`：**推送 `v*` 标签时触发**，汇总产物并附上 `SHA256SUMS.txt` 发布 GitHub Release

```sh
git tag v1.0 && git push origin v1.0
```

## 已知限制

- 深浅色自动探测优先 OSC 11，其次 `COLORFGBG`（Windows 用控制台颜色属性）；都拿不到时默认按深色，可在设置里强制
- 系统代理一键开关目前只支持 GNOME 与 Windows，其他桌面环境会提示手动配置
- 若 mihomo 由其他工具（如 mihomo-party）启动，界面会标记为"外部进程"，停止前需要确认
- 日志按行截断显示，暂不支持横向滚动
- 代理组 / 延迟依赖 mihomo 的 `external-controller`；配置里没写就无法使用代理页

## 致谢

原 `clash_tui` 的功能与操作思路来自 [wzk0/clash_tui](https://github.com/wzk0/clash_tui)，内核为 [MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo)。