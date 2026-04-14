class_name OmniMigrate
extends RefCounted

## Schema 迁移框架（在线迁移，不修改源文件）
##
## 目的：当 schema_version 升级时，允许旧数据集在加载时“按新协议解释”。
## - 在线迁移：在内存中转换 JSON 对象，不写回源文件
## - 离线迁移工具：后续可在 tools/ 目录提供，输出迁移报告与新文件

static func migrate(schema_from: int, schema_to: int, obj: Dictionary) -> Dictionary:
	if schema_from == schema_to:
		return obj
	# 示例：留给未来的版本升级实现（在线迁移，不修改源文件）
	return obj
