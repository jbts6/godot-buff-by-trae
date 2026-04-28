extends GutTest

const CsvReader = preload("res://addons/omnibuff/config/parsers/csv_reader.gd")


func test_parse_simple_line() -> void:
	var cols := OmniCsv._parse_csv_line("a,b,c")
	assert_eq(cols.size(), 3)
	assert_eq(cols[0], "a")
	assert_eq(cols[1], "b")
	assert_eq(cols[2], "c")


func test_parse_quoted_field_with_comma() -> void:
	var cols := OmniCsv._parse_csv_line('a,"b,c",d')
	assert_eq(cols.size(), 3)
	assert_eq(cols[0], "a")
	assert_eq(cols[1], "b,c")
	assert_eq(cols[2], "d")


func test_parse_escaped_quotes() -> void:
	var cols := OmniCsv._parse_csv_line('a,"b""c",d')
	assert_eq(cols.size(), 3)
	assert_eq(cols[0], "a")
	assert_eq(cols[1], 'b"c')
	assert_eq(cols[2], "d")


func test_parse_empty_fields() -> void:
	var cols := OmniCsv._parse_csv_line("a,,c")
	assert_eq(cols.size(), 3, "should have 3 columns for a,,c")
	assert_eq(cols[0], "a")
	assert_eq(cols[1], "")
	assert_eq(cols[2], "c")


func test_parse_trailing_comma() -> void:
	var cols := OmniCsv._parse_csv_line("a,b,")
	assert_eq(cols.size(), 3)
	assert_eq(cols[0], "a")
	assert_eq(cols[1], "b")
	assert_eq(cols[2], "")


func test_parse_single_field() -> void:
	var cols := OmniCsv._parse_csv_line("hello")
	assert_eq(cols.size(), 1)
	assert_eq(cols[0], "hello")


func test_parse_quoted_field_at_end() -> void:
	var cols := OmniCsv._parse_csv_line('a,"b,c"')
	assert_eq(cols.size(), 2)
	assert_eq(cols[0], "a")
	assert_eq(cols[1], "b,c")


func test_load_existing_equipment_csv() -> void:
	var rows: Array = OmniCsv.load_rows("res://data/base_demo/equipment.csv")
	assert_gt(rows.size(), 0, "equipment.csv should have rows")
	var first_row: PackedStringArray = rows[0].cols
	assert_true(first_row.size() >= 4, "header should have at least 4 columns, got %d" % first_row.size())
	assert_eq(first_row[0], "id")
