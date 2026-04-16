class_name OmniExprContext
extends RefCounted

## Expression 的安全 base_instance：只暴露白名单函数

func min(a: float, b: float) -> float:
	return minf(a, b)

func max(a: float, b: float) -> float:
	return maxf(a, b)

func clamp(x: float, lo: float, hi: float) -> float:
	return clampf(x, lo, hi)

func floor(x: float) -> float:
	return floorf(x)

func ceil(x: float) -> float:
	return ceilf(x)

func round(x: float) -> float:
	return roundf(x)

func abs(x: float) -> float:
	return absf(x)

