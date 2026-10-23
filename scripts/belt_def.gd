class_name BeltDef
extends Resource
## A full asteroid ring around the star.

@export var name: String = "Belt"
@export var ore_type: AsteroidBelt.OreType = AsteroidBelt.OreType.IRON
## Optional second ore. ROCK = none.
@export var secondary_ore: AsteroidBelt.OreType = AsteroidBelt.OreType.ROCK
@export_range(0.0, 1.0, 0.01) var secondary_share: float = 0.25
## Ring centre-line radius in metres.
@export var orbit_radius: float = 6000.0
## Full radial width in metres. Asteroids cluster toward the middle.
@export var width: float = 900.0
## Max distance above/below the play plane.
@export var vertical_spread: float = 30.0
@export var count: int = 12000
@export var min_scale: float = 2.0
@export var max_scale: float = 25.0
## 0..1. Share of ore-bearing asteroids.
@export_range(0.0, 1.0, 0.01) var richness: float = 0.3
## 1..5. Gameplay metadata.
@export_range(1, 5, 1) var danger: int = 1
@export var seed: int = 1
## Seconds per full ring rotation at 1x. 0 = static. Negative = clockwise.
@export var rotation_period: float = 2400.0
## Crystal glow multiplier (near asteroids and far dust band).
@export var glow: float = 1.0
## Colour of the far-view dust band.
@export var dust_color: Color = Color(0.62, 0.55, 0.48, 1.0)
