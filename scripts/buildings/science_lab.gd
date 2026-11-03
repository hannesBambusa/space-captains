class_name ScienceLab
extends Node
## Service node of the Science Lab station addon (BuildingDef.service_script).
## The research state lives in the Research autoload (it outlasts the lab:
## what is done stays done); the lab only drives the work while it stands
## and is finished, and is what the player selects to hire researchers and
## fund projects (ScienceLabPanel).

const GROUP := "science_labs"

var building: Building


static func find(ctx: Node) -> ScienceLab:
	return Building.first_active_service(ctx, GROUP) as ScienceLab


func setup(owner_building: Building) -> void:
	building = owner_building


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(SimStepper.GROUP)


func _process(delta: float) -> void:
	if not SimClock.paused:
		sim_step(delta * SimClock.speed)


func sim_step(dt: float) -> void:
	if dt <= 0.0 or building == null or not building.is_active() or ScienceLab.find(self) != self:
		return
	# Its corp acts (feed lines without a target are the rival's own when it is its lab).
	var res := Corps.research(self)
	Corps.act_as(Corps.corp_of_node(self), func() -> void: res.sim_step(dt))


## "2 researchers, 1 project in progress" / "No researchers hired".
func status_text() -> String:
	if building and not building.is_active():
		return building.get_status_text()
	var n := Corps.research(self).researchers.size()
	var working := 0
	for r in Corps.research(self).researchers:
		if not r.is_idle():
			working += 1
	if n == 0:
		return "No researchers hired"
	if Corps.research(self).any_unpaid():
		return "Unpaid: the station cannot pay the researchers, research is paused"
	return "%d researcher%s, %d at work, %d project%s funded" % [n, "" if n == 1 else "s", working, Corps.research(self).projects.size(), "" if Corps.research(self).projects.size() == 1 else "s"]
