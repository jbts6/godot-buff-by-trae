class_name OmniCsv
extends RefCounted

class Row:
	var line_no: int
	var cols: PackedStringArray

static func load_rows(path: String) -> Array[Row]:
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

