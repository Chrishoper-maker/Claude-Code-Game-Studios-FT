shader_type canvas_item;
// 一条从左到右扫过的高光带，progress 由 0→1 时扫完；>1 表示不显示。
// 关键：乘以顶点 COLOR，保留按钮文字/StyleBox 的本色（否则文字会变白、白底白字看不见）。
uniform float progress = 2.0;
uniform float band = 0.18;
void fragment() {
	vec4 base = texture(TEXTURE, UV) * COLOR;
	float d = abs(UV.x - progress);
	float hi = smoothstep(band, 0.0, d) * step(progress, 1.0);
	base.rgb += vec3(hi) * 0.5 * base.a;   // 仅在不透明像素上加高光，避免污染透明区
	COLOR = base;
}
