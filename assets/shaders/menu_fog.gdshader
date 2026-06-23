shader_type canvas_item;
// 缓慢横向滚动的低频噪声雾，冷白半透明叠加。
uniform float speed = 0.012;
uniform vec4 fog_color : source_color = vec4(0.75, 0.82, 0.88, 1.0);

float hash(vec2 p) { return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	float a = hash(i), b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0)), d = hash(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}
void fragment() {
	vec2 uv = UV * vec2(3.0, 2.0);
	uv.x += TIME * speed * 6.0;
	float n = noise(uv) * 0.6 + noise(uv * 2.0) * 0.4;
	float a = smoothstep(0.35, 0.95, n) * 0.30;       // 雾浓度
	COLOR = vec4(fog_color.rgb, a);
}
