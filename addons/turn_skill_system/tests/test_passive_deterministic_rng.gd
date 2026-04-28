extends GutTest

const PassiveManager = preload("res://addons/turn_skill_system/runtime/passive_manager.gd")

func test_passive_rng_deterministic_same_params() -> void:
	var r1 = PassiveManager._roll01_deterministic(1, 0, 100, 0)
	var r2 = PassiveManager._roll01_deterministic(1, 0, 100, 0)
	assert_eq(r1, r2)

func test_passive_rng_different_roll_key_different_result() -> void:
	var r1 = PassiveManager._roll01_deterministic(1, 0, 100, 0)
	var r2 = PassiveManager._roll01_deterministic(1, 1, 100, 0)
	assert_ne(r1, r2)

func test_passive_rng_in_range_0_to_1() -> void:
	for i in range(100):
		var r = PassiveManager._roll01_deterministic(i, i, i + 1, i * 7)
		assert_true(r >= 0.0 and r <= 1.0)

func test_passive_rng_different_owner_different_result() -> void:
	var r1 = PassiveManager._roll01_deterministic(1, 0, 100, 0)
	var r2 = PassiveManager._roll01_deterministic(1, 0, 200, 0)
	assert_ne(r1, r2)

func test_passive_rng_reproducible_across_calls() -> void:
	var results1: Array = []
	var results2: Array = []
	for i in range(20):
		results1.append(PassiveManager._roll01_deterministic(5, i, 42, 0))
	for i in range(20):
		results2.append(PassiveManager._roll01_deterministic(5, i, 42, 0))
	for i in range(20):
		assert_eq(results1[i], results2[i])
