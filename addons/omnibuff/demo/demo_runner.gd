extends Node

func _ready() -> void:
	print("[OmniBuffDemo] boot")
	var result := OmniManifestLoader.load_dataset("res://data/base_demo/manifest.json", true)
	for issue in result.issues:
		push_error("%s %s %s %s: %s" % [issue.level, issue.file, issue.loc, issue.id, issue.message])
	print("[OmniBuffDemo] manifest loaded, enums keys=", result.enums.keys())
