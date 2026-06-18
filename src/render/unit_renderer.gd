# 单位渲染管理（Node3D，ADR-0007）。管理 UnitView 子节点 + instance_id↔view 字典；零物理体。
# 骨架 stub：实现留 ADR-0007 story（垂直切片已验证白盒方案）。
class_name UnitRenderer
extends Node3D

# TODO(ADR-0007 story)：spawn_view(def, id, pos) / get_view(id)；订阅 unit_moved/unit_downed；
#   数据→视觉单向，离散 Tween 移动，白盒图元 + art-bible 配色 + 阵营冷暖 rim。
