class_name StationLoss
extends RefCounted
## A station destroyed in a corp war (rival corporation plan, R7 and M1),
## after its hull's scuttle (StructureHull.scuttle_left) ran out:
## - a forward station (any corp's): it blows up into a big scrap field,
##   its hired ships are lost, its contracts cancelled, its site cleared
##   (the slot is free again) and its system goes back to an ordinary one;
## - the player's home: the game is lost ([EndScreen], the save slot is
##   marked lost: SaveManager.mark_lost);
## - a rival's headquarters: that rival is eliminated ([method eliminate]):
##   its forward stations go too, its captains sign on with the corp that
##   destroyed it (the player when that corp has no berth for them). When
##   the last rival is gone the player wins ([EndScreen], Continue playing).

const SCRAP := 900
const SCRAP_LIFE := 900.0


## [param by]: the corp whose attack started the scuttle.
static func lose(hull: StructureHull, by: StringName = Corps.PLAYER) -> void:
	var w := SystemWorld.of(hull)
	if w == null:
		return
	var tree := w.get_tree()
	if w.is_home:
		EventLog.post_public("Your home station was destroyed by %s" % Corps.display_name(by), EventLog.Kind.LOSS, hull)
		EndScreen.show_end(tree, false)
		return
	var corp := w.corp_id
	if w.is_hq and Corps.is_rival(corp):
		eliminate(tree, corp, by)
		return
	destroy_station(w)


## Blows up the station of system [param w] (not home) and clears its site.
static func destroy_station(w: SystemWorld) -> void:
	var tree := w.get_tree()
	var id := w.system_id
	var corp := w.corp_id
	var st := Sector.state(id)
	var name := String(st.station.get("name", "Station")) if st else "Station"
	var pos := w.sys.home_station.global_position if w.sys and w.sys.home_station else Vector3.ZERO
	if w.combat:
		w.combat.fx.explode_chain(pos, 160.0, 8, 4.0)
		w.combat.spawn_scrap(pos, SCRAP, SCRAP_LIFE, 260.0, "%s wreck" % name)
	# Hired ships and shuttles of its buildings are lost with it.
	if w.buildings:
		for b in w.buildings.buildings.duplicate():
			if not is_instance_valid(b):
				continue
			for s in b.ships.duplicate():
				if is_instance_valid(s) and not s.dead:
					s.retire()
			b.captains.clear()
			b.waiting.clear()
	for c in ContractBoard.contracts.duplicate():
		if c.system_id == id and c.corp == corp and not c.is_finished():
			ContractBoard.cancel(c, true)
	var r := Corps.rival(corp)
	if r:
		r.mind.stats["lost_stations"] = int(r.mind.stats.get("lost_stations", 0)) + 1
	var seen := corp == Corps.PLAYER or (r != null and r.mind.tie(Corps.PLAYER).contact)
	if seen:
		EventLog.post_public("%s was destroyed" % name, EventLog.Kind.LOSS if corp == Corps.PLAYER else EventLog.Kind.REWARD)
	elif r:
		r.mind.note("%s was destroyed" % name)
	if st:
		st.station = {}
	var vm := ViewManager.of(tree)
	if vm:
		var viewed := vm.viewed_id() == id
		vm.unpin(id)
		vm.dematerialise(id)
		if viewed:
			vm.view_now(id)


## Rival [param rid] is out of the game, destroyed by [param by]: its
## stations go, its captains look for work.
static func eliminate(tree: SceneTree, rid: StringName, by: StringName = Corps.PLAYER) -> void:
	var r := Corps.rival(rid)
	if r == null or r.mind.eliminated:
		return
	# Free agents: every captain of its stations, before they go.
	var agents: Array[Captain] = []
	for w in SystemWorld.all(tree):
		if w.has_station and w.corp_id == rid and w.buildings:
			for b in w.buildings.buildings:
				if is_instance_valid(b):
					agents.append_array(b.captains)
	var signed: PackedStringArray = []
	for c in agents:
		var berth := WarStrikes._berth_for(tree, by, c.role)
		if berth == null and by != Corps.PLAYER:
			berth = WarStrikes._berth_for(tree, Corps.PLAYER, c.role)
		if berth == null:
			continue
		if is_instance_valid(c.ship) and not c.ship.dead:
			var old := c.ship.home
			c.ship.retire()
			if is_instance_valid(old):
				old.captains.erase(c)
		c.add_history("Signed on at %s after %s folded" % [berth.display_name, r.display_name])
		if berth.adopt(c) and Corps.corp_of_node(berth) == Corps.PLAYER:
			signed.append(c.captain_name)
	r.mind.eliminated = true
	for k: StringName in r.mind.ties:
		(r.mind.ties[k] as RivalMind.Tie).stance = RivalMind.Stance.PEACE
	for w in SystemWorld.all(tree):
		if w.has_station and w.corp_id == rid:
			destroy_station(w)
	var who := "you" if by == Corps.PLAYER else Corps.display_name(by)
	EventLog.post_public("%s is finished: its headquarters was destroyed by %s%s" % [r.display_name, who,
			", %s signed on with you" % ", ".join(signed) if not signed.is_empty() else ""], EventLog.Kind.REWARD)
	var b := Corps.rival(by)
	if b:
		b.mind.note("We destroyed %s" % r.display_name)
	if Corps.living_rivals().is_empty():
		EndScreen.show_end(tree, true)
