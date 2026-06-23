shader_type canvas_item;
// 一条从左到右扫过的高光带，progress 由 0→1 时扫完；>1 表示不显示。
uniform float progress = 0.0;
uniform float band = 0.18;
void fragment() {
	vec4 base = texture(TEXTURE, UV);
	float d = abs(UV.x - progress);
	float hi = smoothstep(band, 0.0, d) * step(progress, 1.0);
	base.rgb += vec3(hi) * 0.5;
	COLOR = base;
}
