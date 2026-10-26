class_name DiscoveryBounty
extends RefCounted
## Corporate discovery bounties (P4): when an explorer brings a survey home
## (ContractBoard.deliver_survey, or the finds of a survey broken off),
## the corporation pays the station for every new find in it
## (Sector.discoveries that are delivered and not paid yet), and the
## explorer gets a finder's cut on top, into their wallet. Each find is
## paid once ("paid" is saved with the discoveries), so a save and load
## before or after the delivery never pays twice.
##
## Value per find: [constant BASE] by kind (clusters by their ore,
## [constant CLUSTER_ORE]), times the system's danger
## (1 + [constant DANGER_STEP] per level above 1), rounded to 5 cr.

## Credits per find kind at danger 1.
const BASE := {"cluster": 80, "den": 120, "derelict": 60, "gate": 100}
## Clusters by ore word (Survey.ORE_WORDS).
const CLUSTER_ORE := {"rock": 60, "iron": 80, "titanium": 110, "crystal": 150}
const DANGER_STEP := 0.25
## The explorer's cut, on top of what the station gets.
const FINDER_CUT := 0.2
## Economy income source.
const SOURCE := "Discovery"


## The bounty for find [param x] (a Sector.discoveries entry).
static func value_of(x: Dictionary) -> int:
	var kind := String(x.get("kind", ""))
	var base := int(BASE.get(kind, 0))
	if kind == "cluster":
		base = int(CLUSTER_ORE.get(String(x.get("detail", "")), base))
	var e := Sector.network.entry(StringName(x.get("system", ""))) if Sector.network else null
	var danger := e.danger if e else 1
	return roundi(float(base) * (1.0 + DANGER_STEP * float(maxi(danger - 1, 0))) / 5.0) * 5


## Pays the delivered, unpaid finds of captain [param captain_id] in
## system [param id]: the station gets the bounty, [param captain] the
## cut. Returns {finds, credits, cut} (zeros when there was nothing).
static func pay(id: StringName, captain_id: int, captain: Captain) -> Dictionary:
	var finds := 0
	var total := 0
	for x in Sector.discoveries:
		if x["system"] != id or int(x.get("captain", 0)) != captain_id:
			continue
		if not bool(x.get("delivered", false)) or bool(x.get("paid", false)):
			continue
		var v := value_of(x)
		x["paid"] = true
		x["bounty"] = v
		finds += 1
		total += v
	var out := {"finds": finds, "credits": total, "cut": 0}
	if total <= 0:
		return out
	Economy.add_income(total, SOURCE, "Finds in %s" % (Sector.system_def(id).system_name if Sector.system_def(id) else String(id)))
	var cut := roundi(float(total) * FINDER_CUT)
	out["cut"] = cut
	if captain and cut > 0:
		captain.wallet += cut
		captain.credits_earned += cut
	var def := Sector.system_def(id)
	var where := def.system_name if def else String(id)
	var who := " (%s +%s)" % [captain.captain_name, Fmt.amount(cut)] if captain and cut > 0 else ""
	EventLog.post("Corporate bounty: %d find%s in %s, +%s cr%s" % [finds, "" if finds == 1 else "s", where, Fmt.amount(total), who], EventLog.Kind.REWARD)
	if captain:
		captain.flight_log.note(CaptainLog.Kind.CONTRACT, CaptainLog.Outcome.DID, "Finder's cut: %s cr" % Fmt.amount(cut),
				"Corporate bounty for %d find%s in %s (%s cr to the station)" % [finds, "" if finds == 1 else "s", where, Fmt.amount(total)])
	return out


## "+460 cr bounty (4 finds)" for toasts, "" when nothing was paid.
static func short_text(r: Dictionary) -> String:
	if int(r.get("credits", 0)) <= 0:
		return ""
	var n := int(r["finds"])
	return "+%s cr bounty (%d find%s)" % [Fmt.amount(int(r["credits"])), n, "" if n == 1 else "s"]
