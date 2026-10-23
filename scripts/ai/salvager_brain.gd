class_name SalvagerBrain
extends CaptainBrain
## A salvager captain's decisions: the miner's trip (undock, travel, work,
## return, deliver, rest; flee when threatened) on salvage contracts, scored
## by SalvageEvaluator. Only the status lines differ.


func get_status_text() -> String:
	match state:
		State.MINING:
			return "Salvaging %d%%" % roundi((trip.progress if trip else 0.0) * 100.0)
		State.RETURNING:
			if trip and trip.loaded:
				return "Returning with %d scrap" % roundi(float(trip.meta.get("scrap", 0)) * trip.cargo)
			return "Returning"
	return super.get_status_text()
