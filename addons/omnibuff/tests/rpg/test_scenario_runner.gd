extends GutTest

const ScenarioRunner = preload("res://addons/omnibuff/demo/scenario_runner.gd")


func test_load_scenarios_from_dir() -> void:
	var runner = ScenarioRunner.new()
	var scenarios = runner.load_scenarios_from_dir("res://data/rpg_tests/scenarios")
	assert_gt(scenarios.size(), 0, "should find at least one scenario file")


func test_run_atk_buff_scenario() -> void:
	var runner = ScenarioRunner.new()
	var scenarios = runner.load_scenarios_from_dir("res://data/rpg_tests/scenarios")
	var found = false
	for s in scenarios:
		if String(s.get("id", "")) == "atk_buff_increases_damage":
			found = true
			var log_lines: Array[String] = []
			var result = runner.run_scenario(s, func(msg: String) -> void: log_lines.append(msg))
			assert_true(result, "scenario should pass: " + str(log_lines))
			break
	assert_true(found, "should find atk_buff_increases_damage scenario")


func test_run_scenario_with_invalid_assertion_fails() -> void:
	var runner = ScenarioRunner.new()
	var scenario = {
		"dataset": "rpg_tests",
		"setup": [
			{"entity_id": 101, "base_stats": {"HP": 100, "ATK": 10, "DEF": 5}}
		],
		"steps": [],
		"assertions": [
			{"path": "entity.101.stat.HP", "op": "eq", "value": 999}
		]
	}
	var log_lines: Array[String] = []
	var result = runner.run_scenario(scenario, func(msg: String) -> void: log_lines.append(msg))
	assert_false(result, "scenario with wrong assertion should fail")


func test_run_scenario_resolve_stat() -> void:
	var runner = ScenarioRunner.new()
	var scenario = {
		"dataset": "rpg_tests",
		"setup": [
			{"entity_id": 101, "base_stats": {"HP": 100, "ATK": 10, "DEF": 5}}
		],
		"steps": [],
		"assertions": [
			{"path": "entity.101.stat.HP", "op": "eq", "value": 100}
		]
	}
	var result = runner.run_scenario(scenario, func(_msg: String) -> void: pass)
	assert_true(result, "HP should be 100 as configured")


func test_run_scenario_apply_buff_step() -> void:
	var runner = ScenarioRunner.new()
	var scenario = {
		"dataset": "rpg_tests",
		"setup": [
			{"entity_id": 101, "base_stats": {"HP": 100, "ATK": 10, "DEF": 5}}
		],
		"steps": [
			{"action": "apply_buff", "entity_id": 101, "buff_id": "buff_atk_flat_20", "source_entity_id": 101}
		],
		"assertions": [
			{"path": "entity.101.stat.ATK", "op": "gt", "value": 10}
		]
	}
	var result = runner.run_scenario(scenario, func(_msg: String) -> void: pass)
	assert_true(result, "ATK should increase after buff")
