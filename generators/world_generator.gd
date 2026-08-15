## Monta o mundo por código, em runtime.
##
## `scenes/world/main.tscn` contém um `Node3D` e nada mais. Céu, sol, chão, colisão e
## câmera são criados aqui, a partir de `Params`. Nenhum nó deste mundo existe porque
## alguém arrastou algo no editor — é o que torna o mundo inteiro regenerável.
##
## Fase 1 monta só o estágio vazio: chão cinza, céu e uma câmera fixa para conferir
## paleta e desempenho. Terreno, cidade e vegetação entram nas fases 3 e 4, como funções
## novas neste mesmo arquivo e nos seus vizinhos de `generators/`.
class_name WorldGenerator
extends RefCounted

const STAGE_ROOT_NAME: StringName = &"Stage"
const GROUND_MATERIAL: StringName = &"ground"
const GROUND_MESH_CATEGORY: StringName = &"stage_ground"
const PLAYER_NODE_NAME: StringName = &"Player"

const TONEMAP_LINEAR: String = "linear"
const TONEMAP_REINHARDT: String = "reinhardt"
const TONEMAP_FILMIC: String = "filmic"
const TONEMAP_ACES: String = "aces"


## Constrói o estágio inteiro sob `root`, substituindo o que já estiver lá.
## Devolve o nó raiz do estágio.
##
## `with_player` desligado dá o estágio sem ninguém dentro — é o que as provas visuais
## querem: `anim_preview` põe o próprio corpo e `playtest` a própria arena, e um jogador
## extra apareceria no meio do quadro de ambos.
static func build_stage(root: Node3D, with_player: bool = true) -> Node3D:
	var previous: Node = root.get_node_or_null(NodePath(STAGE_ROOT_NAME))
	if previous != null:
		root.remove_child(previous)
		previous.queue_free()

	var stage: Node3D = Node3D.new()
	stage.name = STAGE_ROOT_NAME
	root.add_child(stage)

	stage.add_child(build_environment())
	stage.add_child(build_sun())
	stage.add_child(build_ground())
	if with_player:
		var player: Node3D = build_player()
		if player != null:
			stage.add_child(player)
			return stage
	# Sem jogador — ou sem a cena dele gerada — vale a câmera fixa da fase 1, para o
	# estágio não abrir preto e o motivo ficar visível no console.
	stage.add_child(build_camera())
	return stage


## Céu procedural e névoa, sem HDRI nem textura.
static func build_environment() -> WorldEnvironment:
	var sky_material: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Params.color(&"sky_zenith")
	sky_material.sky_horizon_color = Params.color(&"sky_horizon")
	sky_material.sky_curve = Params.SKY_CURVE
	sky_material.ground_bottom_color = Params.color(&"earth_dark")
	sky_material.ground_horizon_color = Params.color(&"sky_horizon")
	sky_material.sun_angle_max = Params.SUN_ANGLE_MAX
	sky_material.sun_curve = Params.SUN_CURVE

	var sky: Sky = Sky.new()
	sky.sky_material = sky_material

	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_sky_contribution = Params.AMBIENT_SKY_CONTRIBUTION
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = _tonemap_from_name(Params.TONEMAP_MODE)
	environment.tonemap_white = Params.TONEMAP_WHITE
	environment.fog_enabled = true
	environment.fog_light_color = Params.color(&"fog")
	environment.fog_density = Params.FOG_DENSITY
	environment.fog_sky_affect = Params.FOG_SKY_AFFECT

	var node: WorldEnvironment = WorldEnvironment.new()
	node.name = "WorldEnvironment"
	node.environment = environment
	return node


## Traduz o nome de tonemap de `Params` para a constante da engine. Guardar o índice
## numérico em `params.py` daria um `int` cru numa propriedade de enum — e um aviso.
static func _tonemap_from_name(name: String) -> Environment.ToneMapper:
	if name == TONEMAP_LINEAR:
		return Environment.TONE_MAPPER_LINEAR
	if name == TONEMAP_REINHARDT:
		return Environment.TONE_MAPPER_REINHARDT
	if name == TONEMAP_FILMIC:
		return Environment.TONE_MAPPER_FILMIC
	if name == TONEMAP_ACES:
		return Environment.TONE_MAPPER_ACES
	push_error("Tonemap desconhecido em params.py: %s" % name)
	return Environment.TONE_MAPPER_FILMIC


## Luz direcional única — o orçamento só permite uma sombra direcional.
static func build_sun() -> DirectionalLight3D:
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Params.color(&"sun")
	sun.light_energy = Params.STAGE_SUN_ENERGY
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = Params.SHADOW_MAX_DISTANCE
	sun.position = Vector3(0.0, Params.STAGE_SUN_HEIGHT, 0.0)
	sun.rotation = Vector3(
		deg_to_rad(Params.STAGE_SUN_PITCH_DEG),
		deg_to_rad(Params.STAGE_SUN_YAW_DEG),
		0.0
	)
	return sun


## Chão do estágio: malha vertex-colored gerada célula a célula, mais colisão de mundo.
static func build_ground() -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "Ground"
	body.collision_layer = Params.LAYER_WORLD
	body.collision_mask = 0

	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.name = "GroundMesh"
	mesh_instance.mesh = build_ground_mesh()
	mesh_instance.material_override = MaterialLibrary.get_material(GROUND_MATERIAL)
	body.add_child(mesh_instance)

	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.name = "GroundCollision"
	collision.shape = WorldBoundaryShape3D.new()
	body.add_child(collision)
	return body


## Grade plana com leve variação de tom por célula — demonstra o pipeline de vertex color
## sem custar um material a mais.
static func build_ground_mesh() -> ArrayMesh:
	var builder: MeshBuilder = MeshBuilder.new()
	var base: Color = Params.color(&"ground_default")
	var noise: RandomNumberGenerator = RandomNumberGenerator.new()
	noise.seed = Params.WORLD_SEED

	var tint: Callable = func(_column: int, _row: int) -> Color:
		var jitter: float = noise.randf_range(-Params.STAGE_GROUND_TONE_JITTER, Params.STAGE_GROUND_TONE_JITTER)
		return base.lightened(jitter) if jitter > 0.0 else base.darkened(-jitter)

	builder.add_color_grid(
		Vector3.ZERO,
		Params.STAGE_GROUND_SIZE,
		Params.STAGE_GROUND_CELLS,
		tint
	)
	return builder.commit(GROUND_MESH_CATEGORY)


## Instancia o jogador gerado. Devolve `null` quando a cena ainda não existe.
static func build_player() -> Node3D:
	if not ResourceLoader.exists(Params.PLAYER_SCENE):
		push_warning(
			"Cena do jogador ausente (%s). Rode `make player`." % Params.PLAYER_SCENE
		)
		return null
	var packed: PackedScene = ResourceLoader.load(Params.PLAYER_SCENE) as PackedScene
	if packed == null:
		return null
	var player: Node3D = packed.instantiate() as Node3D
	player.name = PLAYER_NODE_NAME
	player.position = Vector3.ZERO
	return player


## Câmera fixa da fase 1, usada só quando não há jogador na cena.
static func build_camera() -> Camera3D:
	var camera: Camera3D = Camera3D.new()
	camera.name = "Camera3D"
	camera.fov = Params.STAGE_CAMERA_FOV
	camera.far = Params.STAGE_CAMERA_FAR
	camera.position = Vector3(0.0, Params.STAGE_CAMERA_HEIGHT, Params.STAGE_CAMERA_DISTANCE)
	camera.rotation = Vector3(deg_to_rad(Params.STAGE_CAMERA_PITCH_DEG), 0.0, 0.0)
	camera.current = true
	return camera
