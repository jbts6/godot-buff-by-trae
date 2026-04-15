#!/usr/bin/env bash
set -euo pipefail

# OmniBuff: Run GUT tests (headless)
#
# 用法：
#   1) 使用 PATH/alias 里的 godot：
#        ./run_gut_tests.sh
#   2) 指定 Godot 可执行文件（推荐，避免 alias 在非交互 shell 不生效）：
#        GODOT_BIN="/Applications/Godot.app/Contents/MacOS/Godot" ./run_gut_tests.sh
#
# 注意：请在包含 project.godot 的目录（即 godot-buff/）下执行本脚本。

GODOT_BIN="${GODOT_BIN:-godot}"

echo "[GUT] Godot bin: ${GODOT_BIN}"
echo "[GUT] Import project (headless)..."
"${GODOT_BIN}" --headless --import --quit

echo "[GUT] Run tests..."
# GUT 默认只扫描 -gdir 指定目录本身，不递归子目录。
# 为了同时跑：
# - res://addons/omnibuff/tests/base 下的“根目录测试”
# - res://addons/omnibuff/tests/rpg 下的大量用例
# 且避免把 helpers/ 下的脚本当成测试扫描导致 warning，
# 我们显式指定两次 -gdir，不开启 -ginclude_subdirs。
"${GODOT_BIN}" --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://addons/omnibuff/tests/base -gdir=res://addons/omnibuff/tests/rpg -gexit
