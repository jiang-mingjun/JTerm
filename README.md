# JTerm

Linux 上的全功能 SSH 客户端，全面对标 MobaXterm。基于 Flutter 构建，核心协议层（SSH/SFTP/Telnet/加密/持久化）为**纯 Dart 实现**，未来可低成本移植到鸿蒙（HarmonyOS）。

![status](https://img.shields.io/badge/status-beta-orange) ![flutter](https://img.shields.io/badge/Flutter-3.47-02569B) ![dartssh2](https://img.shields.io/badge/SSH-dartssh2-2563EB)

## 功能对标 MobaXterm

| MobaXterm 功能 | JTerm 对应实现 | 状态 |
| --- | --- | --- |
| 多标签 SSH 会话 | xterm.dart 终端 + 多标签页（右键菜单：广播/重连/关闭） | ✅ |
| 会话管理器（分组/书签） | 左侧会话面板，`分组/子分组` 层级、复制/编辑/删除 | ✅ |
| 密码管理 | AES-256-GCM 凭据保险库，主密码 + PBKDF2(150k) 派生 | ✅ |
| SSH 认证 | 密码 / 私钥（OpenSSH PEM、ed25519、RSA…），口令保护 | ✅ |
| 跳板机 (SSH gateway) | 会话级跳板配置，支持多级级联，循环引用会拒绝 | ✅ |
| SSH Agent | 用本机 `SSH_AUTH_SOCK` 登录，并可把 agent 转发到远端 | ✅ |
| 出站代理 | SOCKS5 / HTTP CONNECT，可选代理认证 | ✅ |
| keyboard-interactive | OTP / PAM 等多提示认证对话框 | ✅ |
| SFTP 浏览器（左侧自动弹出） | 左侧 SFTP 面板随 SSH 会话自动打开，浏览/上传/下载/重命名/删除/新建目录/Chmod/编辑，带进度条 | ✅ |
| SFTP 跟随终端目录 | 注入 `PROMPT_COMMAND` 上报 OSC 7，浏览器跟着当前目录走 | ✅ |
| ZMODEM | 远端 `sz` 下载、`rz` 上传 | ✅ |
| 端口转发 -L/-R/-D | 会话内嵌转发规则编辑器 + 转发管理对话框，动态转发为内置 SOCKS5 | ✅ |
| X11 转发 | `x11-req` + 本地 X server 桥接（`$DISPLAY` / `/tmp/.X11-unix`） | ✅ |
| Telnet | RFC 854 协商 + NAWS 窗口自适应 | ✅ |
| 本地终端 | flutter_pty 真伪终端，登录 shell | ✅ |
| 多会话命令广播 | 标签右键「切换命令广播」，输入实时同步到所有广播会话 | ✅ |
| 宏命令 | 宏面板 + 工具栏录制（按回车切分命令） | ✅ |
| 主机密钥校验 | TOFU 策略 + known_hosts 管理 + 指纹变更警告 | ✅ |
| 快速连接 | 顶栏 `user@host:port` 一键连接，可记入保险库 | ✅ |
| 命令片段 | 宏面板中的单条命令，点击即发送 | ✅ |
| 远程文本编辑 | SFTP 右键编辑，写回同一条连接 | ✅ |
| 终端查找 / 配色 / 选中即复制 | Ctrl+F、多套配色、Ctrl+点击打开链接 | ✅ |
| 分屏 | 左右 / 上下分屏，标签右键或工具栏 | ✅ |
| 导入 OpenSSH 配置 | 工具菜单读取 `~/.ssh/config`，保留跳板链 | ✅ |
| 密钥生成 | 调用系统 `ssh-keygen`（ed25519 / RSA） | ✅ |
| 会话导入导出 | JSON 备份会话与宏 | ✅ |
| 会话日志 | 单会话或全局记录终端输出 | ✅ |
| 断线重连 | 指数退避，最多 6 次 | ✅ |
| 网络探测 | TCP 连接与 ping | ✅ |
| 串口 (Serial) | Linux termios 打开 `/dev/ttyUSB*`、`ttyACM*`，可配波特率、校验和停止位 | ✅ |
| 内置 X server | 依赖系统 X11/Wayland（不内置） | ➖ |

## 快速开始

### 环境要求

- Flutter ≥ 3.24（本仓库使用 3.47.5 开发）
- Linux 桌面构建依赖：`clang cmake ninja-build pkg-config libgtk-3-dev libstdc++-dev`

```bash
# Ubuntu/Debian
sudo apt install -y clang cmake ninja-build pkg-config libgtk-3-dev libstdc++-dev unzip

# 运行
flutter pub get
flutter run -d linux

# 发布构建
flutter build linux --release
# 产物: build/linux/x64/release/bundle/jterm
```

### 无 root 环境构建（conda-forge 工具链）

没有 sudo 时，可用纯 conda-forge 工具链完成构建（已在 Ubuntu 24.04 + Flutter 3.47.5 验证）：

```bash
# 1) 创建工具链（务必 --override-channels，混入 defaults 频道会损坏 glib 布局）
conda create -n jterm-build -c conda-forge --override-channels -y \
    clangxx=17 ninja pkg-config gtk3

# 2) conda-forge 的 libglib 拆包不含 glibconfig.h，从 Ubuntu 官方 deb 提取一次
cd /tmp && apt download libglib2.0-dev && dpkg-deb -x libglib2.0-dev_*.deb glibdev
mkdir -p ~/miniconda3/envs/jterm-build/lib/glib-2.0/include
cp glibdev/usr/lib/x86_64-linux-gnu/glib-2.0/include/glibconfig.h \
   ~/miniconda3/envs/jterm-build/lib/glib-2.0/include/

# 3) 一键构建（脚本内封装了 PKG_CONFIG_LIBDIR / LDFLAGS 等全部坑位）
scripts/build-linux.sh --release
# 产物: build/linux/x64/release/bundle/jterm
```

脚本 `scripts/build-linux.sh` 解决的坑位：conda 的 pkg-config/ld 不搜系统路径、
间接依赖符号版本冲突（conda 的 pcre2 必须优先于系统的）、flutter 偶发不建
`build/native_assets/linux` 目录等，详见脚本内注释。

## 架构

```
lib/
├── core/                 ★ 纯 Dart 平台无关层（鸿蒙可移植）
│   ├── models/           会话/转发/宏 数据模型 + JSON 序列化
│   ├── store/            JSON 原子持久化、AES-GCM 凭据库、known_hosts
│   ├── ssh/              dartssh2 连接管理、SFTP 服务、X11 桥接
│   ├── forward/          -L/-R/-D 端口转发引擎
│   ├── telnet/           RFC 854 客户端
│   └── terminal/         会话抽象（SSH/PTY/Telnet 桥接 xterm 核心）
├── state/                Provider 状态层（AppState/TabsState/Settings）
└── ui/                   Flutter 界面（替换平台壳即可移植）
    ├── main_shell.dart   主窗口：工具栏+侧栏+标签+状态栏
    ├── session/          会话面板、会话编辑器、宏面板
    ├── sftp/             SFTP 浏览器
    ├── terminal/         终端页
    └── ...
```

**设计原则**：`core/` 不依赖任何 Flutter UI 与平台插件，连接生命周期、协议、加密、
持久化全部在此层；`ui/` 仅做展示与交互。移植鸿蒙时只需：

1. 用 OpenHarmony 的 Flutter 分支（[flutter_flutter](https://gitee.com/openharmony-sig/flutter_flutter)）重建平台壳；
2. `flutter_pty`（本地终端）替换为鸿蒙平台实现（`core/terminal` 已隔离该依赖）；
3. SSH/SFTP/转发/保险库零改动。

## 数据位置

所有配置存储于 `~/.local/share/dev.jterm/jterm/`：

- `sessions.json` 会话与宏
- `vault.json` 加密凭据库（AES-256-GCM）
- `known_hosts.json` 受信主机指纹

## 安全说明

- 密码/口令永不明文落盘，保险库由主密码派生密钥加密；
- 主机密钥采用 TOFU（首次信任）策略，指纹变更时高亮告警；
- 建议生产环境使用密钥认证 + 保险库。

## 路线图

- [x] 终端分屏
- [x] SSH Agent 登录与转发
- [x] SFTP 跟随目录、远程编辑、终端查找与配色
- [x] 串口会话（Linux termios）
- [x] Zmodem（`sz` / `rz`）
- [ ] 鸿蒙平台适配（ArkUI 壳 + flutter_flutter 分支）
- [ ] 内置 RDP / VNC

## License

MIT
