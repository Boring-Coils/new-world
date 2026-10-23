extends World

@onready
var debug_UI: DebugUI = $DebugUI

@onready
var placer: PlacementController = $PlacementController


func _ready() -> void:
	super._ready()
	debug_UI.kind_selected.connect(placer.select_kind)
	placer.notice.connect(debug_UI.set_hint)
