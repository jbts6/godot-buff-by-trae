@tool
extends EditorPlugin

## EditorPlugin：负责在“启用/禁用插件”时安装/卸载 OmniBuff 的工程级集成项
##
## 目标（按用户需求）：
## - 启用插件：即可引入所有 OmniBuff 相关的“全局入口”（Autoload：OmniBuff）
## - 禁用插件：不应残留 OmniBuff 相关全局入口
##
## 实现方式：
## - 使用 EditorPlugin 的 autoload 管理 API 写入/移除 project.godot 的 [autoload] 配置。

const AUTOLOAD_NAME := "OmniBuff"
const AUTOLOAD_PATH := "res://addons/omnibuff/runtime/omnibuff_singleton.gd"

func _enter_tree() -> void:
	print("[OmniBuff] plugin enabled")
	_install_autoload()

func _exit_tree() -> void:
	print("[OmniBuff] plugin disabled")
	_remove_autoload()

func _install_autoload() -> void:
	# 启用插件时：添加 Autoload（若已存在则跳过）
	# 注意：该操作会修改宿主项目的 project.godot。
	if ProjectSettings.has_setting("autoload/" + AUTOLOAD_NAME):
		return
	add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)
	ProjectSettings.save()

func _remove_autoload() -> void:
	# 禁用插件时：移除 Autoload（若不存在则跳过）
	if not ProjectSettings.has_setting("autoload/" + AUTOLOAD_NAME):
		return
	remove_autoload_singleton(AUTOLOAD_NAME)
	ProjectSettings.save()
