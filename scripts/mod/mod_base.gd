# Mod 入口基类。Mod 作者 `extends ModBase` 并实现 setup()。
class_name ModBase
extends RefCounted

var ctx: ModContext = null


## 由加载器调用：注册内容、绑定钩子
func setup(_ctx: ModContext) -> void:
	pass


## 卸载时调用（热重载 / 关闭）
func teardown() -> void:
	pass


## Mod 元信息（可选覆盖）
func meta() -> Dictionary:
	return {}
