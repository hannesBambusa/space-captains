class_name RemoteSystemState
extends RefCounted
## What the game knows and has changed about one generated system, as
## plain data (saved under "cluster" by [Sector]; the SystemDef itself is
## regenerated from the seed). Written by SystemHost when the system goes
## from live to data (and before a save while live), stepped by RemoteSim
## while it is data; exploration fills known / seen / revealed later.

## Scouted at least once.
var known := false
## SimClock time of the last survey, -1 = never.
var last_seen := -1.0
## Revealed planets, clusters, bases, derelicts and gates, by name.
var revealed: PackedStringArray = []
## Base state by den name (ScavengerDen.save_state shape; RemoteSim adds
## "pending": ships launched while not live, built on the next visit).
var dens: Dictionary = {}
## Cluster state by cluster name: {"left": loads, "total": loads}.
var clusters: Dictionary = {}
## Names of the derelicts already looted.
var looted: PackedStringArray = []
## Ships in the system while it is not live (ShipCodec dicts: scavengers,
## the player's ships with their "transit" and RemoteSim "trip").
var ships: Array = []
## Scrap fields while not live (ScrapField.save_state dicts).
var scrap: Array = []
## Sim seconds until the next raid out of this system, -1 = none planned.
var raid_timer := -1.0
## Forward station site, {} = none: {planet, orbit_radius, period, angle
## (deg), founded_at (SimClock time), name} (SolarSystem.add_station,
## SystemWorld.has_station).
var station: Dictionary = {}


func to_dict() -> Dictionary:
	# Deep copies: the snapshot must not change with the live state.
	return {"known": known, "seen": last_seen, "revealed": revealed.duplicate(), "dens": dens.duplicate(true), "clusters": clusters.duplicate(true),
			"looted": looted.duplicate(), "ships": ships.duplicate(true), "scrap": scrap.duplicate(true), "raid": raid_timer, "station": station.duplicate(true)}


static func from_dict(d: Dictionary) -> RemoteSystemState:
	var s := RemoteSystemState.new()
	s.known = bool(d.get("known", false))
	s.last_seen = float(d.get("seen", -1.0))
	s.revealed = PackedStringArray(d.get("revealed", PackedStringArray()))
	s.dens = (d.get("dens", {}) as Dictionary).duplicate(true)
	s.clusters = (d.get("clusters", {}) as Dictionary).duplicate(true)
	s.looted = PackedStringArray(d.get("looted", PackedStringArray()))
	s.ships = (d.get("ships", []) as Array).duplicate(true)
	s.scrap = (d.get("scrap", []) as Array).duplicate(true)
	s.raid_timer = float(d.get("raid", -1.0))
	s.station = (d.get("station", {}) as Dictionary).duplicate(true)
	return s
