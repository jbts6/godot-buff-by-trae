class_name OmniCsv
extends RefCounted

class Row:
	## CSV行号（用于错误定位：file + line_no）
	var line_no: int
	## 按逗号切分后的列（最小实现：不处理引号/转义；后续可增强）
	var cols: PackedStringArray

static func load_rows(path: String) -> Array[Row]:
	## 读取 CSV 并返回行数组（跳过空行与#注释行）
	## 注意：当前为最小实现，不支持引号包裹字段（含逗号）。
	var rows: Array[Row] = []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("[OmniCsv] open failed: " + path)
		return rows
	var line_no := 0
	while not f.eof_reached():
		var line := f.get_line()
		line_no += 1
		if line_no == 1 and line.begins_with("\uFEFF"):
			line = line.substr(1)
		var s := line.strip_edges()
		if s == "" or s.begins_with("#"):
			continue
		var cols := line.split(",", false)
		var r := Row.new()
		r.line_no = line_no
		r.cols = cols
		rows.append(r)
	return rows
