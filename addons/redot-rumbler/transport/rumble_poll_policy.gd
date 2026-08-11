class_name RumblePollPolicy
extends RefCounted

const MIN_INTERVAL_SECONDS: float = 2.0
const DEFAULT_INTERVAL_SECONDS: float = 5.0
const MAX_BACKOFF_SECONDS: float = 60.0


static func interval(value: float) -> float:
	return maxf(MIN_INTERVAL_SECONDS, value)


static func backoff(attempt: int, jitter_unit: float, retry_after_seconds: float = 0.0) -> float:
	var exponent := mini(maxi(attempt - 1, 0), 5)
	var base := minf(MAX_BACKOFF_SECONDS, MIN_INTERVAL_SECONDS * float(1 << exponent))
	var jitter := clampf(jitter_unit, 0.0, 1.0) * minf(1.0, base * 0.25)
	return maxf(retry_after_seconds, minf(MAX_BACKOFF_SECONDS, base + jitter))
