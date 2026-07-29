shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

// Additive sprite-sheet effect.
//
// `blend_add` is the whole trick. The source clips were generated on pure black,
// and black adds nothing, so there is no alpha channel to key, no matte line and
// no cutout threshold to tune. It also means the effect *glows over* whatever is
// behind it rather than punching a hole in it, which is the point of using
// filmed-looking fire on top of pixel actors.
//
// The frame lives in a uniform rather than in a swapped texture, so a whole
// animation is one texture and one material. Twenty effects on screen is twenty
// draw calls, not twenty draw calls plus twenty texture binds per frame.
//
// Draw order is NOT decided here. It comes from render_priority on the material,
// set from RenderPriority, so a friendly effect can never cover a red telegraph.

uniform sampler2D sheet : source_color, filter_linear, repeat_disable;

uniform int cols = 4;
uniform int rows = 6;
uniform int frame = 0;

// Scales the light the effect contributes. Fade-out multiplies the colour rather
// than the alpha: under blend_add a lower alpha would also dim the result, but
// only by accident of the blend equation. Multiplying the colour says what it
// means and survives someone changing the blend mode later.
uniform float energy : hint_range(0.0, 4.0) = 1.0;
uniform float fade : hint_range(0.0, 1.0) = 1.0;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// How the quad is oriented. Must match AdditiveVfxData.Facing.
//
//   0 UPRIGHT - turns about the vertical axis only. Things that stand up in the
//               world: a flame column, a beam. Keeps world-up as up, so it is
//               foreshortened by the camera pitch and picks up the perspective
//               keystone of any tall upright object. That is correct, and for
//               fire it is what makes the flame look like it is in the room.
//   1 VIEW    - aligns to the view plane, so the quad always presents flat-on at
//               full size with no lean. Right for anything that reads as a disc
//               facing the player - a radial burst, a bloom, an impact flash.
//   2 GROUND  - no billboarding at all. The node's own rotation is kept, which is
//               how a top-down effect gets to lie flat in XZ.
uniform int facing = 0;

// GROUND is the do-nothing case, written as an `if` rather than an early return:
// Godot's shader language rejects `return` inside vertex() outright.
void vertex() {
	if (facing != 2) {
		// Rebuild the modelview basis from the camera, keeping the model's own
		// scale on each axis - dropping it is the classic way to make every
		// billboard render at unit size.
		vec3 scale_v = vec3(
			length(MODEL_MATRIX[0].xyz),
			length(MODEL_MATRIX[1].xyz),
			length(MODEL_MATRIX[2].xyz));

		vec3 right = INV_VIEW_MATRIX[0].xyz;
		vec3 up = INV_VIEW_MATRIX[1].xyz;
		if (facing == 0) {
			// Lock up to world-up and flatten the camera's right into the ground
			// plane, so the effect cannot tip over or roll.
			right = normalize(vec3(right.x, 0.0, right.z));
			up = vec3(0.0, 1.0, 0.0);
		}
		vec3 fwd = cross(right, up);

		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			vec4(right * scale_v.x, 0.0),
			vec4(up * scale_v.y, 0.0),
			vec4(fwd * scale_v.z, 0.0),
			MODEL_MATRIX[3]);
	}
}

void fragment() {
	vec2 grid = vec2(float(cols), float(rows));
	int idx = clamp(frame, 0, cols * rows - 1);
	vec2 cell = vec2(float(idx % cols), float(idx / cols));

	// Inset by half a texel. Without this, linear filtering at a cell edge reaches
	// into the neighbouring frame and every effect gets a faint ghost of the next
	// one along its border.
	vec2 texel = 1.0 / (vec2(textureSize(sheet, 0)));
	vec2 uv = clamp(UV, texel * grid * 0.5, 1.0 - texel * grid * 0.5);
	uv = (uv + cell) / grid;

	vec3 c = texture(sheet, uv).rgb * tint.rgb * energy * fade;
	ALBEDO = c;
	ALPHA = 1.0;
}
