class_name FactionDef
extends Resource
## A hostile faction (data/factions/*.tres): who its ships are, how they
## fight, what their hideouts are like and what they are worth. Every
## DenDef names one ([member DenDef.faction]); ScavengerDen, ScavengerShip
## and ScavengerBrain read it, so one set of scripts runs every faction.
## All factions share the hostile combat side (Combat.Faction.SCAVENGER):
## they never fight each other.
##
## Models: [member ship_model_path] and [member den_model_path] follow the
## scavenger node-name contract (scavenger.glb: engine_glow, muzzle_l/r;
## scavenger_den.glb: den_rock, den_salvage, den_hangar_glow, den_lights,
## spawn_point). While a file is missing (not imported yet) the scavenger
## model is used instead, tinted [member color] and scaled by the fallback
## scale; the real model takes over as soon as it exists.

enum RaidStyle {
	## Shield bubble, turrets, generator, then ships near home; loot when nothing is left.
	SHIELD_FIRST,
	## Shield bubble, turrets, generator, then besiege the outposts (heavy
	## looting); ships near home only when they shoot back.
	STRUCTURES,
}

const SCAVENGER_SHIP_MODEL := "res://assets/models/ships/scavenger.glb"
const SCAVENGER_DEN_MODEL := "res://assets/models/buildings/scavenger_den.glb"

@export var id: StringName = &"scavenger"
## Plural, for lists and headers: "Scavengers".
@export var display_name: String = "Scavengers"
## One ship: "Scavenger" ("Scavenger Rustjaw-3").
@export var unit_name: String = "Scavenger"
## One base, lower case: "scavenger hideout".
@export var den_kind: String = "scavenger hideout"
## Marker, overview, minimap and event log colour.
@export var color: Color = Color(1.0, 0.32, 0.24)
## Marker colour of its raiders (sent at the colony).
@export var raider_color: Color = Color(1.0, 0.55, 0.2)
## Hangar light of its bases.
@export var light_color: Color = Color(1.0, 0.4, 0.2)

@export_group("Models")
@export_file("*.glb") var ship_model_path: String = SCAVENGER_SHIP_MODEL
@export_file("*.glb") var den_model_path: String = SCAVENGER_DEN_MODEL
## Fallback (scavenger) models only: scale and how far the tint goes (0..1).
@export var ship_fallback_scale: float = 1.0
@export var den_fallback_scale: float = 1.0
@export_range(0.0, 1.0, 0.01) var fallback_tint: float = 0.55

@export_group("Ship")
## Hull, shields, speed and weapon. Null = the "Scavenger" role default.
@export var loadout: ShipLoadout
## Hit and pick radius, metres.
@export var hit_radius: float = 9.0
## Gunnery of its pilots: 0..1 chance a shot hits a target that does not dodge.
@export_range(0.0, 1.0, 0.01) var ship_accuracy: float = 0.5
## 0..1 chance its ships dodge an incoming hit (light, fast raiders).
@export_range(0.0, 0.9, 0.01) var ship_dodge: float = 0.0

@export_group("Behaviour")
## Prey: miners, salvagers, escape pods, armed player ships (mercenaries).
@export var hunts_miners: bool = true
@export var hunts_salvagers: bool = true
@export var hunts_pods: bool = true
@export var hunts_armed: bool = false
## 0..1. How little escorts put it off and how far it chases whoever shot
## it (0.5 = scavenger: escorts weigh 2500 m each, retaliation 1000 m).
@export_range(0.0, 1.0, 0.01) var aggression: float = 0.5
## Runs home below this hull share.
@export_range(0.0, 1.0, 0.01) var flee_hull: float = 0.35
## Share of a miner's load taken before running home. 0 = never steals,
## shoots to kill.
@export_range(0.0, 1.0, 0.01) var steal_share: float = 0.5
## Ships launched together that hunt as one (2 = pairs).
@export_range(1, 4) var pack_size: int = 1
@export var raid_style: RaidStyle = RaidStyle.SHIELD_FIRST
## Relative chance a raid comes from this faction's bases. 0 = never raids.
@export var raid_weight: float = 1.0
## Raid size range. x = 0: the RaidDirector's growing wave.
@export var raid_size: Vector2i = Vector2i.ZERO
## Sim seconds before this faction raids the colony at all.
@export var raid_after: float = 0.0
## Credits looted per tick and per raider (RaidStyle.STRUCTURES besieges harder).
@export var raid_loot_mult: float = 1.0

@export_group("Base")
## Toughness defaults for a DenDef that leaves its own at -1.
@export var den_hull: float = 4000.0
@export var den_shields: float = 800.0
@export var den_shield_regen: float = 10.0
@export var den_hit_radius: float = 42.0
## Point defence: guns, damage per shot, shots per second per gun, range.
@export_range(0, 6) var den_guns: int = 1
@export var den_gun_damage: float = 6.0
@export var den_gun_rate: float = 2.0
@export var den_gun_range: float = 650.0

@export_group("Planet claims")
## Orbital garrison over a claimed planet (ClaimGarrison, PlanetClaims):
## hull, shields, regeneration.
@export var garrison_hull: float = 3600.0
@export var garrison_shields: float = 900.0
@export var garrison_shield_regen: float = 10.0
## Its four flak turrets, each on its own target: damage per shot, shots
## per second per turret, range in metres.
@export var garrison_turret_damage: float = 4.0
@export var garrison_turret_rate: float = 1.5
@export var garrison_turret_range: float = 800.0
## Patrol ships out at once, and sim seconds between launches below that.
@export var garrison_patrols: int = 3
@export var garrison_respawn: float = 60.0
## Patrols guard this far past the garrison's own distance from the planet, metres.
@export var garrison_guard_reach: float = 1800.0
## Sim seconds after a claim is broken before the faction comes back
## (random in the range), and the escorts of its claim group.
@export var reclaim_delay: Vector2 = Vector2(540.0, 840.0)
@export var claim_escorts: int = 3
## The claim group's constructor (the garrison core): hull and shields.
@export var constructor_hull: float = 900.0
@export var constructor_shields: float = 300.0

@export_group("Rewards")
## Multiplies the suggested bounty (TargetPanel) and the ruins' scrap.
@export var bounty_mult: float = 1.0
@export var loot_mult: float = 1.0
## Danger rating of a bounty on one of its bases / ships (1..5).
@export_range(1, 5) var den_bounty_danger: int = 4
@export_range(1, 5) var ship_bounty_danger: int = 2

@export_group("Names")
## Callsign words ("Shrike" -> "Shrike-4"). Empty = the den's gang name.
@export var name_pool: PackedStringArray = []
## Target panel blurbs. %s in den_info = the cluster or region it preys on, %d = the spawn cap.
@export_multiline var den_info: String = "Raider base dug into an asteroid, preying on %s. Launches scavengers up to %d at a time. Destroy it to stop them and lower the danger of clusters nearby."
## Event log line when the faction's first base arrives (once per game).
@export_multiline var intro: String = ""
## %s = the ship's base.
@export_multiline var ship_info: String = "Junk raider from %s. Hunts loaded miners and steals cargo."


## Garrison turrets times damage per second (MercFleet's need estimate).
func garrison_gun_dps() -> float:
	return 4.0 * garrison_turret_damage * garrison_turret_rate


## Guns times damage per second (MercFleet's need estimate).
func den_gun_dps() -> float:
	return float(den_guns) * den_gun_damage * den_gun_rate


## Size of its bases against the scavenger den (den_hit_radius 42).
func den_scale() -> float:
	return den_hit_radius / 42.0


## "Raiders" for the scavengers, else "Corsair raiders" and the like.
func raiders_label() -> String:
	return "Raiders" if id == Factions.DEFAULT_ID else "%s raiders" % unit_name


## The hologram look in its colours (Building.CONSTRUCTION_SHADER) for a
## base that is still arriving or being deployed.
func holo_material(grid_size: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = Building.CONSTRUCTION_SHADER
	mat.set_shader_parameter("grid_size", grid_size)
	mat.set_shader_parameter("holo_color", color.lerp(Color.WHITE, 0.2))
	mat.set_shader_parameter("seam_color", light_color)
	return mat


## The model to load: the faction's when it exists, else the scavenger one.
static func pick_model(path: String, fallback: String) -> String:
	if not path.is_empty() and ResourceLoader.exists(path):
		return path
	return fallback
