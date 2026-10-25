class_name Researcher
extends RefCounted
## A scientist hired at the Science Lab (not a ship). Field, skill and
## personality are rolled like a captain's. They pick their own project
## among the funded ones ([ResearchChoice]); skill and a field match set how
## fast they work ([method speed_on]).

enum Personality { AMBITIOUS, CAUTIOUS, CURIOUS, METHODICAL }

const PERSONALITY_NAMES: PackedStringArray = ["Ambitious", "Cautious", "Curious", "Methodical"]
const PERSONALITY_HINTS: PackedStringArray = [
	"Likes big, expensive, high-tier projects.",
	"Likes defensive work: shields, armour, escape gear. Avoids weapons.",
	"Likes Planetary work and anything that unlocks something new to build.",
	"Likes cheap, low-tier projects and finishing what was started.",
]
const FIRST_NAMES: PackedStringArray = [
	"Ada", "Bastian", "Celeste", "Darius", "Elin", "Farid", "Greta", "Hiro", "Ilse", "Joran",
	"Kalia", "Lukas", "Maren", "Nils", "Odile", "Priya", "Quill", "Rasmus", "Saga", "Tobin",
	"Una", "Viktor", "Wilhelmina", "Xander", "Yara", "Zofia",
]
const LAST_NAMES: PackedStringArray = [
	"Arkwright", "Bellamy", "Cho", "Dresner", "Ekdahl", "Fontaine", "Gallo", "Hazeltine",
	"Ishikawa", "Jansen", "Kowalczyk", "Lund", "Mbeki", "Nakamura", "Osei", "Pryce",
	"Quint", "Rautio", "Sandoval", "Thorne", "Ulven", "Vasquez", "Weiss", "Zhou",
]
## Speed on a project outside their field.
const OFF_FIELD_SPEED := 0.6
const MAX_SKILL := 10
## Wage, credits per sim minute: base plus per skill point.
const WAGE_BASE := 2.0
const WAGE_PER_SKILL := 0.5

var id: int = 0
var researcher_name: String = ""
var field: TechDef.Field = TechDef.Field.ENGINEERING
## 1 to 10.
var skill: int = 5
var personality: Personality = Personality.METHODICAL
## Credits to hire (applicants only).
var hire_cost: int = 0
## Tech being worked on, &"" when idle.
var project: StringName = &""
var hired_at: float = 0.0
var completed: int = 0
## Why they picked their current (or last) project.
var reason: String = ""
## Wage earned but not paid yet, credits (paid in whole credits).
var wage_due: float = 0.0
## The station could not pay the wage: no work until it can.
var unpaid: bool = false


static func generate(rng: RandomNumberGenerator, new_id: int) -> Researcher:
	var r := Researcher.new()
	r.id = new_id
	r.researcher_name = "Dr. %s %s" % [FIRST_NAMES[rng.randi() % FIRST_NAMES.size()], LAST_NAMES[rng.randi() % LAST_NAMES.size()]]
	r.field = (rng.randi() % TechDef.FIELD_NAMES.size()) as TechDef.Field
	r.personality = (rng.randi() % PERSONALITY_NAMES.size()) as Personality
	r.skill = clampi(rng.randi_range(2, 7) + (1 if rng.randf() < 0.25 else 0), 1, MAX_SKILL)
	r.hire_cost = hire_cost_for(r.skill)
	return r


## 150 cr plus 40 per skill point.
static func hire_cost_for(level: int) -> int:
	return 150 + 40 * level


func personality_name() -> String:
	return PERSONALITY_NAMES[personality]


func field_name() -> String:
	return TechDef.FIELD_NAMES[field]


## Wage, credits per sim minute: 2 + 0.5 per skill point.
func wage_per_min() -> float:
	return WAGE_BASE + WAGE_PER_SKILL * float(skill)


## Work speed from skill: 0.6 at skill 1, 1.0 at 5, 1.5 at 10.
func skill_speed() -> float:
	return 0.5 + 0.1 * float(skill)


## Sim seconds of project time done per second on [param tech].
func speed_on(tech: TechDef) -> float:
	return skill_speed() * (1.0 if tech == null or tech.field == field else OFF_FIELD_SPEED)


func is_idle() -> bool:
	return project.is_empty()


func save_state() -> Dictionary:
	return {"id": id, "name": researcher_name, "field": int(field), "skill": skill, "personality": int(personality), "hire_cost": hire_cost,
			"project": project, "hired_at": hired_at, "completed": completed, "reason": reason, "wage_due": wage_due, "unpaid": unpaid}


static func from_save(d: Dictionary) -> Researcher:
	var r := Researcher.new()
	r.id = int(d.get("id", 0))
	r.researcher_name = String(d.get("name", "Dr. Unknown"))
	r.field = clampi(int(d.get("field", 0)), 0, TechDef.FIELD_NAMES.size() - 1) as TechDef.Field
	r.skill = clampi(int(d.get("skill", 5)), 1, MAX_SKILL)
	r.personality = clampi(int(d.get("personality", 0)), 0, PERSONALITY_NAMES.size() - 1) as Personality
	r.hire_cost = int(d.get("hire_cost", hire_cost_for(r.skill)))
	r.project = StringName(d.get("project", &""))
	r.hired_at = float(d.get("hired_at", 0.0))
	r.completed = int(d.get("completed", 0))
	r.reason = String(d.get("reason", ""))
	r.wage_due = float(d.get("wage_due", 0.0))
	r.unpaid = bool(d.get("unpaid", false))
	return r
