class_name SystemView
extends SubViewportContainer
## Shows the viewed system's SubViewport full screen (scenes/game.tscn).
##
## Sharpness: the window stretches canvas items, so a stretched container
## would render 3D at the base size (1920x1080) and scale it. Instead each
## SubViewport renders at the window's pixel size with its 2D size set to
## the base size, and this container is scaled back by the content scale:
## the image maps 1:1 to screen pixels, as when the system was the main
## scene, and screen coordinates (input, unproject_position) stay in base
## units for the HUD. The SubViewports copy the root's quality settings
## (MSAA, screen-space AA, scaling).
##
## Input: the container does not forward anything by itself. Events nobody
## at the top level took (HUD, selection, placement) go to the viewed
## system in [method _unhandled_input]; this node is the first child of
## game.tscn, so it hears them last, the order the RTS camera had when it
## sat in the same scene as the HUD.


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process_input(false)
	stretch = false
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	for c in get_children():
		var vp := c as SubViewport
		if vp:
			_match_quality(vp)
			vp.audio_listener_enable_3d = true
	get_viewport().size_changed.connect(_fit)
	_fit()


## Pixel size render, base size 2D, container scaled to cover the screen.
func _fit() -> void:
	var root := get_viewport()
	var px := Vector2i(maxi(root.size.x, 1), maxi(root.size.y, 1))
	var base := root.get_visible_rect().size
	for c in get_children():
		var vp := c as SubViewport
		if vp:
			vp.size = px
			vp.size_2d_override = Vector2i(base.round())
			vp.size_2d_override_stretch = true
	position = Vector2.ZERO
	size = Vector2(px)
	scale = base / Vector2(px)


func _match_quality(vp: SubViewport) -> void:
	var root := get_viewport()
	vp.msaa_2d = root.msaa_2d
	vp.msaa_3d = root.msaa_3d
	vp.screen_space_aa = root.screen_space_aa
	vp.use_taa = root.use_taa
	vp.use_debanding = root.use_debanding
	vp.use_occlusion_culling = root.use_occlusion_culling
	vp.mesh_lod_threshold = root.mesh_lod_threshold
	vp.scaling_3d_mode = root.scaling_3d_mode
	vp.scaling_3d_scale = root.scaling_3d_scale
	vp.fsr_sharpness = root.fsr_sharpness
	vp.texture_mipmap_bias = root.texture_mipmap_bias
	vp.anisotropic_filtering_level = root.anisotropic_filtering_level
	vp.positional_shadow_atlas_size = root.positional_shadow_atlas_size
	vp.positional_shadow_atlas_16_bits = root.positional_shadow_atlas_16_bits
	for q in 4:
		vp.set_positional_shadow_atlas_quadrant_subdiv(q, root.get_positional_shadow_atlas_quadrant_subdiv(q))
	vp.use_hdr_2d = root.use_hdr_2d


## The viewed system's SubViewport, or null.
func viewed_viewport() -> SubViewport:
	var vm := ViewManager.of(get_tree())
	if vm == null or not is_instance_valid(vm.viewed):
		return null
	return vm.viewed.get_viewport() as SubViewport


func _unhandled_input(event: InputEvent) -> void:
	var vp := viewed_viewport()
	if vp == null:
		return
	var ev := event
	if event is InputEventMouse or event is InputEventGesture:
		ev = event.xformed_by(get_global_transform_with_canvas().affine_inverse())
	vp.push_input(ev)
	if vp.is_input_handled():
		get_viewport().set_input_as_handled()
