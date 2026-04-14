class_name OmniMigrate
extends RefCounted

static func migrate(schema_from: int, schema_to: int, obj: Dictionary) -> Dictionary:
	if schema_from == schema_to:
		return obj
	# 示例：留给未来的版本升级实现（在线迁移，不修改源文件）
	return obj

