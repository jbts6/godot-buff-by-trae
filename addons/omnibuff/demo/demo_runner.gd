extends Node

func _ready() -> void:
	print("[OmniBuffDemo] boot")
	var result := OmniManifestLoader.load_dataset("res://data/base_demo/manifest.json", true)
	for issue in result.issues:
		push_error("%s %s %s %s: %s" % [issue.level, issue.file, issue.loc, issue.id, issue.message])
	print("[OmniBuffDemo] manifest loaded, enums keys=", result.enums.keys())
	var enums_rt := OmniEnumsRuntime.from_enums_json(result.enums)
	var sources := {
		"stat_defs": OmniJson.load_dict("res://data/base_demo/stat_defs.json"),
		"buff_defs": OmniJson.load_dict("res://data/base_demo/buff_defs.json")
	}
	var ds := OmniDatasetCompiler.compile(result.manifest, enums_rt, sources)
	print("[OmniBuffDemo] stat_id(ATK)=", ds.stat_id("ATK"), " buff_id(buff_atk_up_3t)=", ds.buff_id("buff_atk_up_3t"))
