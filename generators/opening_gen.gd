@tool
## A abertura: um acampamento à beira da estrada, e nenhuma palavra de tutorial.
##
## O jogador acorda deitado ao lado de uma fogueira. A câmera abre do chão para a linha do
## horizonte, e o que ela encontra é a estrada. A estrada leva a um portão iluminado, o
## portão leva à praça. Não há seta, não há texto, não há "aperte W para andar".
##
## A condução é composição, e é feita de três coisas que já existem no projeto:
##
## 1. **A fogueira é o único ponto quente do quadro.** A abertura acontece às 6h24, quando
##    a paleta do amanhecer ainda é fria e a luz do sol está baixa: um `OmniLight3D` laranja
##    a dois metros do rosto é para onde o olho vai, e é onde o jogador está.
## 2. **A estrada é a única linha reta do vale.** Relevo, vegetação e rochas são ruído; uma
##    faixa de terra batida atravessando tudo lê como caminho antes de qualquer legenda.
## 3. **O portão é o único ponto aceso ao longe.** Os lampiões da estrada e as janelas da
##    cidade estão acesos nessa hora — a fase 5 acende as duas coisas abaixo de
##    `DAY_CYCLE_LIGHT_ON`, e às 6h24 ainda estamos abaixo dele.
##
## O acampamento nasce **na estrada**, e não num ponto fixo: a estrada muda com a seed, e
## um acampamento em coordenada absoluta acabaria no meio de uma encosta na segunda seed.
class_name OpeningGenerator
extends RefCounted

const ROOT_NAME: StringName = &"Opening"
const HALF: float = 0.5
## Props que compõem o acampamento, na ordem em que são distribuídos em volta do fogo.
const CAMP_PARTS: Array[StringName] = [&"crate", &"barrel", &"sack", &"log", &"pot"]


## Monta o acampamento e devolve onde o jogador acorda, olhando para onde ele deve olhar.
##
## Devolve um dicionário e não um `Transform3D` porque quem chama precisa de duas coisas
## diferentes: onde pôr o corpo e para onde apontar a câmera — e a câmera não olha para a
## frente do corpo no primeiro instante, ela sobe do chão até ela.
static func build(
	field: HeightField, curve: Curve3D, layout: CityLayout, parent: Node3D, world_seed: int
) -> Dictionary:
	if field == null or curve == null:
		return {}

	var root: Node3D = Node3D.new()
	root.name = ROOT_NAME
	parent.add_child(root)

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = world_seed + SEED_OFFSET

	# O ponto da estrada onde se acorda: longe o bastante da cidade para ela ser um destino,
	# perto o bastante para caber numa caminhada de um minuto.
	var travel: float = curve.get_baked_length() * Params.OPENING_CAMP_ROAD_T
	var on_road: Vector3 = curve.sample_baked(travel)
	var ahead: Vector3 = curve.sample_baked(minf(travel + STEP_AHEAD, curve.get_baked_length()))
	var forward: Vector2 = Vector2(ahead.x - on_road.x, ahead.z - on_road.z)
	if forward.length() < MIN_LENGTH:
		forward = Vector2.RIGHT
	forward = forward.normalized()

	# O acampamento fica **ao lado** da estrada, do lado oposto ao da cidade: acordar em
	# cima do leito seria acordar no meio do caminho, e o caminho tem de ser uma escolha.
	var side: Vector2 = forward.orthogonal()
	var to_city: Vector2 = Vector2.ZERO
	if layout != null:
		to_city = (layout.center - Vector2(on_road.x, on_road.z)).normalized()
	if side.dot(to_city) > 0.0:
		side = -side

	var flat: Vector2 = Vector2(on_road.x, on_road.z) + side * Params.OPENING_CAMP_OFFSET
	var camp: Vector3 = field.ground_point(flat.x, flat.y, 0.0)

	_build_fire(root, camp)
	_build_props(root, field, camp, rng)
	var lanterns: int = _light_the_road(root, field, curve, travel, layout)

	# O jogador acorda encostado no fogo, olhando para a estrada — que é para onde a
	# câmera vai abrir. A cidade fica do outro lado dela, e é o segundo lugar que o olho vai.
	var rest: Vector2 = flat + side * REST_OFFSET
	var stand: Vector3 = field.ground_point(rest.x, rest.y, WAKE_CLEARANCE)
	return {
		"node": root,
		"position": stand,
		"facing": atan2(-side.x, -side.y),
		"look_at": Vector3(on_road.x, camp.y, on_road.z),
		"lanterns": lanterns,
		"camp": camp,
	}


const SEED_OFFSET: int = 17431
## Quanto adiante na estrada se olha para achar a direção dela.
const STEP_AHEAD: float = 6.0
const MIN_LENGTH: float = 0.001
## Onde o corpo acorda em relação ao fogo, em metros para fora dele.
const REST_OFFSET: float = 1.6
const WAKE_CLEARANCE: float = 0.4


## A fogueira: partículas quentes, uma luz pontual e as pedras em volta.
##
## A luz tem sombra ligada, e é a única do jogo que tem além do sol. O orçamento permite
## quatro pontuais com sombra e o projeto usava zero: uma fogueira sem sombra não desenha
## as pedras em volta dela, e são elas que dizem que aquilo é um acampamento e não um
## efeito de partículas no chão.
static func _build_fire(root: Node3D, spot: Vector3) -> void:
	var fire: GPUParticles3D = GPUParticles3D.new()
	fire.name = "Fire"
	fire.amount = Params.OPENING_FIRE_PARTICLES
	fire.lifetime = FIRE_LIFETIME
	fire.position = spot + Vector3.UP * FIRE_RISE
	fire.draw_pass_1 = _ember_mesh()
	fire.process_material = _fire_material()
	fire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(fire)

	var light: OmniLight3D = OmniLight3D.new()
	light.name = "Firelight"
	light.position = spot + Vector3.UP * Params.OPENING_FIRE_HEIGHT
	light.light_color = Params.color(&"window_light")
	light.light_energy = FIRE_ENERGY
	light.omni_range = FIRE_RANGE
	light.shadow_enabled = true
	root.add_child(light)


const FIRE_LIFETIME: float = 1.1
const FIRE_RISE: float = 0.1
const FIRE_ENERGY: float = 2.4
const FIRE_RANGE: float = 7.5


static func _fire_material() -> ParticleProcessMaterial:
	var process: ParticleProcessMaterial = ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = Params.OPENING_FIRE_SCALE
	process.direction = Vector3.UP
	process.spread = FIRE_SPREAD
	process.initial_velocity_min = FIRE_SPEED * HALF
	process.initial_velocity_max = FIRE_SPEED
	process.gravity = Vector3.ZERO
	process.scale_min = HALF
	process.scale_max = 1.0
	process.color = Params.color(&"window_light")
	return process


const FIRE_SPREAD: float = 14.0
const FIRE_SPEED: float = 1.3


static func _ember_mesh() -> Mesh:
	var builder: MeshBuilder = MeshBuilder.new()
	builder.add_box(
		Vector3.ZERO, Vector3.ONE * Params.OPENING_FIRE_SCALE * EMBER_SIZE,
		Params.color(&"window_light")
	)
	return builder.commit(&"prop")


const EMBER_SIZE: float = 0.35


## O que faz aquilo ler como acampamento: caixotes, um barril, um saco e um tronco de
## sentar, em volta do fogo. Peças do kit, como tudo o mais.
static func _build_props(
	root: Node3D, field: HeightField, camp: Vector3, rng: RandomNumberGenerator
) -> void:
	var pool: Dictionary = {}
	for index: int in Params.OPENING_CAMP_PROPS:
		var part: StringName = CAMP_PARTS[index % CAMP_PARTS.size()]
		var angle: float = TAU * float(index) / float(Params.OPENING_CAMP_PROPS) \
			+ rng.randf_range(-PROP_JITTER, PROP_JITTER)
		var radius: float = Params.OPENING_CAMP_RADIUS * rng.randf_range(HALF + HALF * HALF, 1.0)
		var flat: Vector2 = Vector2(camp.x, camp.z) + Vector2(cos(angle), sin(angle)) * radius
		var spot: Vector3 = field.ground_point(flat.x, flat.y, 0.0)
		CityBuilder.place(pool, part, spot, rng.randf_range(0.0, TAU))
	CityBuilder.flush_into(pool, root)


const PROP_JITTER: float = 0.4


## Lanternas ao longo da estrada, do acampamento até o portão.
##
## É a linha pontilhada que o jogador segue sem saber que está seguindo. Só do acampamento
## para a frente: atrás dele a estrada continua escura, e escuro é a forma mais antiga de
## dizer "não é por aí".
static func _light_the_road(
	root: Node3D, field: HeightField, curve: Curve3D, from: float, layout: CityLayout
) -> int:
	if layout == null:
		return 0
	var pool: Dictionary = {}
	var total: float = curve.get_baked_length()
	var placed: int = 0
	var travel: float = from
	while travel < total:
		var point: Vector3 = curve.sample_baked(travel)
		var flat: Vector2 = Vector2(point.x, point.z)
		# Dentro da muralha a cidade já tem os seus lampiões; duplicar seria dobrar o custo
		# de luz justamente onde ele já é maior.
		if flat.distance_to(layout.center) < Params.CITY_RADIUS:
			break
		var side: Vector2 = _road_side(curve, travel, total)
		var spot: Vector3 = field.ground_point(
			flat.x + side.x * ROAD_LANTERN_OFFSET, flat.y + side.y * ROAD_LANTERN_OFFSET, 0.0
		)
		CityBuilder.place(pool, &"lantern_post", spot, 0.0)
		placed += 1
		travel += Params.OPENING_LANTERN_SPACING
	if placed > 0:
		CityBuilder.flush_into(pool, root)
	return placed


const ROAD_LANTERN_OFFSET: float = 3.4


static func _road_side(curve: Curve3D, travel: float, total: float) -> Vector2:
	var here: Vector3 = curve.sample_baked(travel)
	var ahead: Vector3 = curve.sample_baked(minf(travel + STEP_AHEAD, total))
	var forward: Vector2 = Vector2(ahead.x - here.x, ahead.z - here.z)
	if forward.length() < MIN_LENGTH:
		return Vector2.RIGHT
	return forward.normalized().orthogonal()
