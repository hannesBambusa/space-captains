// Under-construction look of one building surface, opaque pass. Everything
// is measured in building space (to_site), so the effect is fixed to the
// structure while the station's frame moves. Below the build line (cut_y,
// broken up a little by a static noise) the surface shows its own baked
// material (copied from the original StandardMaterial3D) with a fading
// fresh-metal tint and a soft welding seam at the line; above it the
// fragment is discarded and the blueprint pass (construction_holo, the
// next_pass) draws instead. The two passes keep complementary halves of the
// same triangles, so they never z-fight.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/construction_build.gdshaderinc"
