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
		var cols := _parse_csv_line(line)
		var r := Row.new()
		r.line_no = line_no
		r.cols = cols
		rows.append(r)
	return rows

static func _parse_csv_line(line: String) -> PackedStringArray:
	var result: Array = []
	var i := 0
	var n := line.length()
	while i < n:
		if line[i] == '"':
			var field := ""
			i += 1
			while i < n:
				if line[i] == '"':
					if i + 1 < n and line[i + 1] == '"':
						field += '"'
						i += 2
					else:
						i += 1
						break
				else:
					field += line[i]
					i += 1
			result.append(field)
			if i < n and line[i] == ',':
				i += 1
		else:
			var start := i
			while i < n and line[i] != ',':
				i += 1
			result.append(line.substr(start, i - start))
			if i < n and line[i] == ',':
				i += 1
				if i >= n:
					result.append("")
	var packed := PackedStringArray()
	packed.resize(result.size())
	for idx in range(result.size()):
		packed[idx] = String(result[idx])
	return packed
