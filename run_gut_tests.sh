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
"${GODOT_BIN}" --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://addons/omnibuff/tests -ginclude_subdirs -gexit
