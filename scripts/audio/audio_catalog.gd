extends RefCounted
## BGM の場面名と効果音の出来事名から音声リソースのパスを解決する純粋な対応表。
## 音声ファイルの出典とライセンスは assets/CREDITS.md を正とする。

## BGM のバス名 (default_bus_layout.tres と一致させる)
const BUS_BGM: String = "BGM"
## 効果音のバス名 (default_bus_layout.tres と一致させる)
const BUS_SFX: String = "SFX"

## BGM の場面名: 題名の画面
const BGM_TITLE: String = "title"
## BGM の場面名: 屋敷の中
const BGM_MANSION: String = "mansion"

## 効果音の出来事名: 毛を抜いた時 (大げさな効果音)
const SFX_PLUCK_HAIR: String = "pluck_hair"
## 効果音の出来事名: お金が入った時
const SFX_EARN_MONEY: String = "earn_money"
## 効果音の出来事名: 道具を買った時
const SFX_BUY_TOOL: String = "buy_tool"
## 効果音の出来事名: ボタン操作
const SFX_BUTTON: String = "button"

## BGM の場面名から音声リソースパスへの対応表
const BGM_PATHS: Dictionary = {
	BGM_TITLE: "res://assets/audio/bgm_title.ogg",
	BGM_MANSION: "res://assets/audio/bgm_mansion.ogg",
}

## 効果音の出来事名から音声リソースパスへの対応表
const SFX_PATHS: Dictionary = {
	SFX_PLUCK_HAIR: "res://assets/audio/sfx_pluck_hair.ogg",
	SFX_EARN_MONEY: "res://assets/audio/sfx_earn_money.ogg",
	SFX_BUY_TOOL: "res://assets/audio/sfx_buy_tool.ogg",
	SFX_BUTTON: "res://assets/audio/sfx_button.ogg",
}


## 場面名に対応する BGM のリソースパスを返す。未登録の場面名は空文字を返す
static func resolve_bgm_path(scene_name: String) -> String:
	return String(BGM_PATHS.get(scene_name, ""))


## 出来事名に対応する効果音のリソースパスを返す。未登録の出来事名は空文字を返す
static func resolve_sfx_path(event_name: String) -> String:
	return String(SFX_PATHS.get(event_name, ""))


## 登録済みの BGM 場面名一覧を返す
static func all_bgm_names() -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray()
	for key: String in BGM_PATHS.keys():
		names.append(key)
	return names


## 登録済みの効果音出来事名一覧を返す
static func all_sfx_names() -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray()
	for key: String in SFX_PATHS.keys():
		names.append(key)
	return names
