class_name ScienceLab
extends Node
## Service node of the Science Lab station addon (BuildingDef.service_script).
## The research state lives in the Research autoload (it outlasts the lab:
## what is done stays done); the lab only drives the work while it stands
## and is finished, and is what the player selects to hire researchers and
## fund projects (ScienceLabPanel).

const GROUP := "science_labs"

var building: Building


static func find(tree: SceneTree) -> ScienceLab:
	return Building.first_active_service(tree, GROUP) as ScienceLab


func setup(owner_building: Building) -> void:
	building = owner_building


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(SimStepper.GROUP)


func _process(delta: float) -> void:
	if not SimClock.paused:
		sim_step(delta * SimClock.speed)


func sim_step(dt: float) -> void:
	if dt <= 0.0 or building == null or not building.is_active() or ScienceLab.find(get_tree()) != self:
		return
	Research.sim_step(dt)


## "2 researchers, 1 project in progress" / "No researchers hired".
func status_text() -> String:
	if building and not building.is_active():
		return building.get_status_text()
	var n := Research.researchers.size()
	var working := 0
	for r in Research.researchers:
		if not r.is_idle():
			working += 1
	if n == 0:
		return "No researchers hired"
	if Research.any_unpaid():
		return "Unpaid: the station cannot pay the researchers, research is paused"
	return "%d researcher%s, %d at work, %d project%s funded" % [n, "" if n == 1 else "s", working, Research.projects.size(), "" if Research.projects.size() == 1 else "s"]
