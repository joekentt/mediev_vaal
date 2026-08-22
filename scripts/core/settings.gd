## As opções do jogador: ler, escrever e **aplicar**.
##
## `GameState` guarda os valores; este arquivo é o único que sabe o que cada um faz no
## motor. A separação não é cerimônia: aplicar qualidade mexe em MSAA, sombra, cascatas e
## LOD ao mesmo tempo, e ter isso espalhado por três menus é como um projeto perde o
## controle de quanto custa a própria imagem.
##
## **Nenhuma opção muda o que a cena é.** Baixar a qualidade não apaga um prédio, não tira
## um habitante da praça e não encurta a cidade: mexe em quantas amostras o anti-aliasing
## tira, em quão longe a sombra alcança e em quanto do espalhamento aparece. O jogo é o
## mesmo em qualquer preset — o que muda é quanto ele custa para desenhar.
##
## A densidade de habitantes é a única exceção, e por isso ela só vale na **geração**: criar
## ou apagar gente na frente do jogador seria pior que qualquer ganho de quadro.
class_name Settings
extends RefCounted

const VIEWPORT_MSAA: String = "rendering/anti_aliasing/quality/msaa_3d"
const VIEWPORT_DEBANDING: String = "rendering/anti_aliasing/quality/use_debanding"
const KEY_QUALITY: StringName = &"quality"
const KEY_RENDER_DISTANCE: StringName = &"render_distance"
const KEY_NPC_DENSITY: StringName = &"npc_density"
const KEY_VSYNC: StringName = &"vsync"
const KEY_VOLUMES: StringName = &"volumes"
const KEY_SENSITIVITY: StringName = &"mouse_sensitivity"
const KEY_INVERT_Y: StringName = &"invert_camera_y"
const KEY_VOICE: StringName = &"voice"


## Preset de qualidade pelo nome, com aviso alto se alguém inventar um.
static func preset(level: StringName) -> Dictionary:
	if Params.QUALITY_PRESETS.has(level):
		return Params.QUALITY_PRESETS[level]
	push_warning("Preset de qualidade inexistente: %s. Usando %s." % [level, Params.QUALITY_DEFAULT])
	return Params.QUALITY_PRESETS[Params.QUALITY_DEFAULT]


# --- Aplicar ------------------------------------------------------------------


## Aplica tudo o que não depende do mundo estar montado: janela, viewport e áudio.
static func apply_global(state: Node) -> void:
	var chosen: Dictionary = preset(state.quality)
	var window: Viewport = Engine.get_main_loop().root

	window.msaa_3d = int(chosen["msaa"]) as Viewport.MSAA
	window.use_debanding = bool(chosen["debanding"])
	window.use_occlusion_culling = bool(chosen["occlusion"])

	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if state.vsync_enabled else DisplayServer.VSYNC_DISABLED
	)

	var audio: Node = Engine.get_main_loop().root.get_node_or_null(^"/root/AudioManager")
	if audio != null:
		for bus_name: Variant in state.volumes:
			audio.set_bus_volume(StringName(bus_name), float(state.volumes[bus_name]))


## Aplica o que só existe depois de o mundo nascer: a luz direcional e o alcance do LOD.
##
## Recebe o estágio em vez de procurá-lo: nas provas há cena sem sol e cena sem cidade, e
## um aplicador que dependesse de achar os dois ficaria mudo em metade delas.
static func apply_world(state: Node, stage: Node3D) -> void:
	if stage == null:
		return
	var chosen: Dictionary = preset(state.quality)
	var reach: float = clampf(
		state.render_distance, Params.RENDER_DISTANCE_MIN, Params.RENDER_DISTANCE_MAX
	)

	var sun: DirectionalLight3D = stage.find_child("Sun", true, false) as DirectionalLight3D
	if sun != null:
		sun.directional_shadow_mode = WorldGenerator.splits_from_name(String(chosen["splits"]))
		sun.directional_shadow_max_distance = float(chosen["shadow_distance"]) * reach

	# A sombra direcional é o botão mais caro do projeto: cada cascata redesenha todo caster
	# dentro do alcance. Tamanho do atlas e filtro vão junto porque é o mesmo assunto.
	RenderingServer.directional_shadow_atlas_set_size(int(chosen["shadow_size"]), true)
	RenderingServer.directional_soft_shadow_filter_set_quality(
		int(chosen["shadow_filter"]) as RenderingServer.ShadowQuality
	)

	_scale_lod(stage, reach * float(chosen["lod_scale"]))
	# **Só o ramo da vegetação.** `visible_instance_count` corta instâncias de qualquer
	# `MultiMesh`, e a cidade inteira é feita deles: aplicado ao estágio todo, baixar a
	# qualidade apagaria metade das paredes. Qualidade mexe em quanto custa desenhar, nunca
	# no que a cena é.
	_thin_scatter(stage.get_node_or_null(NodePath(WorldGenerator.SCATTER_ROOT_NAME)),
		float(chosen["scatter"]))
	_scale_particles(stage, float(chosen["particles"]))


## Estica ou encolhe toda faixa de LOD já montada, preservando a proporção entre elas.
##
## Multiplicar o que o gerador escreveu, em vez de reescrever as faixas: o espalhamento
## nasce com três faixas calibradas umas contra as outras, e recalculá-las aqui duplicaria
## a regra em dois lugares que iriam divergir na primeira mudança.
static func _scale_lod(node: Node, factor: float) -> void:
	if node is GeometryInstance3D:
		var geometry: GeometryInstance3D = node as GeometryInstance3D
		var base: Variant = geometry.get_meta(LOD_META, null)
		if base == null and geometry.visibility_range_end > 0.0:
			base = geometry.visibility_range_end
			geometry.set_meta(LOD_META, base)
		if base != null:
			geometry.visibility_range_end = float(base) * maxf(factor, MIN_FACTOR)
	for child: Node in node.get_children():
		_scale_lod(child, factor)


const LOD_META: StringName = &"lod_base"
const SCATTER_META: StringName = &"scatter_base"
const MIN_FACTOR: float = 0.1


## Mostra menos instâncias de vegetação sem reconstruir o `MultiMesh`.
##
## `visible_instance_count` corta do fim da lista, e a lista nasce embaralhada pela seed —
## então cortar 45% tira 45% espalhados pelo bloco, e não uma faixa vazia de um lado.
static func _thin_scatter(node: Node, factor: float) -> void:
	if node == null:
		return
	if node is MultiMeshInstance3D:
		var multi: MultiMesh = (node as MultiMeshInstance3D).multimesh
		if multi != null:
			var base: Variant = node.get_meta(SCATTER_META, null)
			if base == null:
				base = multi.instance_count
				node.set_meta(SCATTER_META, base)
			multi.visible_instance_count = int(round(float(base) * clampf(factor, 0.0, 1.0)))
	for child: Node in node.get_children():
		_thin_scatter(child, factor)


static func _scale_particles(node: Node, factor: float) -> void:
	if node is GPUParticles3D:
		(node as GPUParticles3D).amount_ratio = clampf(factor, 0.0, 1.0)
	for child: Node in node.get_children():
		_scale_particles(child, factor)


# --- Disco --------------------------------------------------------------------


## Lê `user://settings.json` para dentro do `GameState`. Sem arquivo, ficam os padrões.
static func load_into(state: Node) -> void:
	if not FileAccess.file_exists(Params.SETTINGS_PATH):
		return
	var file: FileAccess = FileAccess.open(Params.SETTINGS_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		push_warning("Opções ilegíveis em %s. Usando os padrões." % Params.SETTINGS_PATH)
		return

	var data: Dictionary = parsed as Dictionary
	var wanted: StringName = StringName(data.get(KEY_QUALITY, state.quality))
	if Params.QUALITY_LEVELS.has(wanted):
		state.quality = wanted
	state.render_distance = clampf(
		float(data.get(KEY_RENDER_DISTANCE, state.render_distance)),
		Params.RENDER_DISTANCE_MIN, Params.RENDER_DISTANCE_MAX
	)
	state.npc_density = clampf(
		float(data.get(KEY_NPC_DENSITY, state.npc_density)),
		Params.NPC_DENSITY_MIN, Params.NPC_DENSITY_MAX
	)
	state.vsync_enabled = bool(data.get(KEY_VSYNC, state.vsync_enabled))
	state.set_mouse_sensitivity(float(data.get(KEY_SENSITIVITY, state.mouse_sensitivity)))
	state.invert_camera_y = bool(data.get(KEY_INVERT_Y, state.invert_camera_y))
	state.voice_enabled = bool(data.get(KEY_VOICE, state.voice_enabled))

	var stored: Dictionary = data.get(KEY_VOLUMES, {})
	for bus_name: Variant in stored:
		if state.volumes.has(bus_name):
			state.volumes[bus_name] = clampf(float(stored[bus_name]), 0.0, 1.0)


static func save_from(state: Node) -> void:
	var file: FileAccess = FileAccess.open(Params.SETTINGS_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Não consegui escrever %s" % Params.SETTINGS_PATH)
		return
	file.store_string(JSON.stringify({
		KEY_QUALITY: String(state.quality),
		KEY_RENDER_DISTANCE: state.render_distance,
		KEY_NPC_DENSITY: state.npc_density,
		KEY_VSYNC: state.vsync_enabled,
		KEY_SENSITIVITY: state.mouse_sensitivity,
		KEY_INVERT_Y: state.invert_camera_y,
		KEY_VOICE: state.voice_enabled,
		KEY_VOLUMES: state.volumes,
	}, "  ") + "\n")
	file.close()
