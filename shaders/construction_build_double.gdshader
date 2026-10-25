// construction_build for double-sided surfaces (culling off).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/construction_build.gdshaderinc"
