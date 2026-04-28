extends GutTest

const DamagePipeline = preload("res://addons/omnibuff/runtime/core/damage_pipeline.gd")


func test_roll01_range() -> void:
	for turn in range(5):
		for roll_key in range(10):
			var v := OmniDamagePipeline._roll01(turn, roll_key, 101, 202, 0xA1B2C3D4)
			assert_gt(v, -0.001, "roll01 should be >= 0")
			assert_lt(v, 1.001, "roll01 should be < 1")


func test_roll01_deterministic() -> void:
	var v1 := OmniDamagePipeline._roll01(1, 0, 101, 202, 0xA1B2C3D4)
	var v2 := OmniDamagePipeline._roll01(1, 0, 101, 202, 0xA1B2C3D4)
	assert_eq(v1, v2, "same input should produce same output")


func test_roll01_different_salt_different_result() -> void:
	var v1 := OmniDamagePipeline._roll01(1, 0, 101, 202, 0xA1B2C3D4)
	var v2 := OmniDamagePipeline._roll01(1, 0, 101, 202, 0xC3D4E5F6)
	assert_ne(v1, v2, "different salt should produce different result")


func test_roll01_precision_4_decimal() -> void:
	for turn in range(3):
		for roll_key in range(5):
			var v := OmniDamagePipeline._roll01(turn, roll_key, 101, 202, 0xA1B2C3D4)
			var scaled := v * 10000.0
			var rounded := roundf(scaled)
			assert_lt(absf(scaled - rounded), 0.001, "roll01 should have at most 4 decimal places")


func test_roll01_not_always_zero() -> void:
	var has_nonzero := false
	for turn in range(10):
		for roll_key in range(10):
			var v := OmniDamagePipeline._roll01(turn, roll_key, 101, 202, 0xA1B2C3D4)
			if v > 0.01:
				has_nonzero = true
				break
		if has_nonzero:
			break
	assert_true(has_nonzero, "roll01 should not always return 0")
