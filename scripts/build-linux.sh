#!/usr/bin/env bash
# JTerm Linux 构建脚本 —— 无 root / conda-forge 工具链（已在 Ubuntu 24.04 验证打通）。
#
# 首次使用（一次性准备）：
#   1) 安装 Flutter SDK 到用户目录（见 README）
#   2) 创建工具链环境（必须纯 conda-forge，不要混入 defaults 频道，否则 glib 布局会损坏）：
#      conda create -n jterm-build -c conda-forge --override-channels -y \
#          clangxx=17 ninja pkg-config gtk3
#   3) conda-forge 的 libglib 拆包不含 glibconfig.h，需从 Ubuntu 官方 deb 提取一次：
#      cd /tmp && apt download libglib2.0-dev && dpkg-deb -x libglib2.0-dev_*.deb glibdev
#      cp glibdev/usr/lib/x86_64-linux-gnu/glib-2.0/include/glibconfig.h \
#         ~/miniconda3/envs/jterm-build/lib/glib-2.0/include/
#
# 用法：
#   scripts/build-linux.sh              # debug 构建
#   scripts/build-linux.sh --release    # release 构建
set -euo pipefail

FLUTTER_BIN="${FLUTTER_BIN:-$HOME/.local/opt/flutter/bin}"
CONDA_ENV="${CONDA_ENV:-$HOME/miniconda3/envs/jterm-build}"

export PATH="$FLUTTER_BIN:$CONDA_ENV/bin:$PATH"

# 接管 pkg-config 搜索路径，只允许 conda 环境（避免命中系统半套 GTK 头文件）。
export PKG_CONFIG_LIBDIR="$CONDA_ENV/lib/pkgconfig:$CONDA_ENV/lib/x86_64-conda-linux-gnu/pkgconfig:$CONDA_ENV/share/pkgconfig"

# conda 的 x86_64-conda-linux-gnu-ld 默认不搜索系统库目录；libflutter_linux_gtk.so
# 的间接依赖（libepoxy.so.0 / libfontconfig.so.1）只有系统运行时。让间接依赖优先
# 解析到 conda 同源库（pcre2/gtk 符号版本一致），系统目录兜底。
# 注意：-Wl 的多个 -rpath-link 目录必须用冒号分隔（逗号会被拆成独立参数导致
# ld 把目录当输入文件读取，报 "read in flex scanner failed"）。
export LDFLAGS="-Wl,-rpath-link,$CONDA_ENV/lib:/lib/x86_64-linux-gnu"

cd "$(dirname "$0")/.."

# flutter 工具偶发不创建该目录，而 linux/CMakeLists.txt 的 install(DIRECTORY) 需要它存在。
mkdir -p build/native_assets/linux

exec flutter build linux "$@"
