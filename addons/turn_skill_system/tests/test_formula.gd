extends GutTest

const Formula := preload("res://addons/turn_skill_system/runtime/formula.gd")


func test_formula_floor_and_vars_tracking() -> void:
	var ctx := {
		"a_stats": {"ATK": 101},
		"t_stats": {"DEF": 10}
	}
	var r := Formula.eval_expr("50 + a.ATK * 1.2", ctx, "floor")
	assert_true(bool(r.get("ok", false)))
	assert_eq(float(r.get("value", -1)), 171.0) # floor(50 + 121.2) = 171

	var resolved: Dictionary = r.get("resolved", {})
	var vars: Dictionary = resolved.get("vars", {})
	assert_eq(float(vars.get("a.ATK", -1)), 101.0)

