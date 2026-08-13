## Acesso à biblioteca de materiais gerada em `assets/generated/materials/`.
##
## Um material por nome, carregado uma vez e compartilhado por todas as malhas. Reuso
## de material é o que segura o orçamento de draw calls: material novo é agrupamento
## perdido. Nenhum sistema deve chamar `StandardMaterial3D.new()` — peça aqui.
##
## Se `assets/generated/` não existir (é derivado e ignorado pelo git), o material cai
## para um magenta de depuração gerado em memória e avisa no console. Rode `make assets`.
class_name MaterialLibrary
extends RefCounted

const MATERIALS_DIR: String = "res://assets/generated/materials"

static var _cache: Dictionary = {}
static var _warned_missing: bool = false


## Material compartilhado pelo nome (ver `Params.MATERIALS`).
static func get_material(key: StringName) -> StandardMaterial3D:
	if _cache.has(key):
		return _cache[key]

	var path: String = "%s/%s.tres" % [MATERIALS_DIR, key]
	var material: StandardMaterial3D = null
	if ResourceLoader.exists(path):
		material = ResourceLoader.load(path) as StandardMaterial3D

	if material == null:
		material = _fallback(key)

	_cache[key] = material
	return material


## Descarta o cache — usado quando `make assets` roda com o jogo aberto.
static func reload() -> void:
	_cache.clear()
	_warned_missing = false


## Quantos materiais distintos já foram pedidos nesta sessão. Alimenta `make bench`.
static func loaded_count() -> int:
	return _cache.size()


static func _fallback(key: StringName) -> StandardMaterial3D:
	if not _warned_missing:
		_warned_missing = true
		push_warning(
			"Biblioteca de materiais ausente em %s. Rode `make assets`." % MATERIALS_DIR
		)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Params.color(&"debug_magenta")
	material.vertex_color_use_as_albedo = true
	material.resource_name = "fallback_%s" % key
	return material
