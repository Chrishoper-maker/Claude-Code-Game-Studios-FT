# 套装效果中文描述表（②b-2a，纸娃娃用）。仅四基础套；未知套/档返回 ""。
class_name SetEffectCatalog
extends RefCounted

const _DESC := {
	"set_ironwall": {3: "首击减半", 6: "+3自愈", 9: "钢铁壁垒·全轮减半"},
	"set_berserker": {3: "攻击+1", 6: "狂热·攻击+2", 9: "持续狂热·每击+2"},
	"set_healer": {3: "自愈+3", 6: "相邻友军+3", 9: "治疗翻倍+6"},
	"set_navigator": {3: "邻友攻击+1", 6: "邻友首击减半", 9: "增益半径+1"},
	"set_bloodthirst": {3: "吸血¼", 6: "吸血½", 9: "吸血½·外溢"},
	"set_thorns": {3: "反伤1", 6: "反伤2", 9: "反伤3"},
	"set_executioner": {3: "斩杀残血≤3", 6: "斩杀残血≤5", 9: "斩杀残血≤7"},
}

# 某套某档效果描述；未知套或非 {3,6,9} 档返回 ""。
static func describe(set_id: String, tier: int) -> String:
	var by_tier: Variant = _DESC.get(set_id, null)
	if by_tier is Dictionary:
		return str((by_tier as Dictionary).get(tier, ""))
	return ""
