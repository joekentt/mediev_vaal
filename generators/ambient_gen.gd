@tool
## Vida ambiente da cidade: fumaça, pássaros, vento no varal, folhas, cachorro e martelo.
##
## Nada disto tem IA, e é essa a ideia. Uma cidade com vinte habitantes tem vinte coisas se
## mexendo; uma cidade viva tem centenas, e as outras centenas não podem custar uma decisão
## cada. Tudo aqui é função do relógio, de uma rota fixa ou de um sistema de partículas —
## coisas que o motor já sabe animar sozinho.
##
## O orçamento manda no formato de cada item:
##
## - **Fumaça e folhas** são `GPUParticles3D`: o motor anima no shader e o custo é um draw
##   call por sistema, não um por partícula.
## - **Pássaros** são um `MultiMesh` por bando, com as transformações reescritas por
##   quadro. Dez nós de pássaro seriam dez draw calls para dez triângulos cada.
## - **O vento do varal é um shader de vértice**, e não geometria animada. Mexer nos
##   vértices na CPU obrigaria cada pano a virar malha própria, e são todos instâncias do
##   mesmo `MultiMesh` desde a fase 8.
## - **O cachorro** é malha gerada aqui — o kit de 34 peças não tem um, e acrescentar uma
##   peça de kit por causa de um cachorro custaria uma rodada inteira de fábrica.
class_name AmbientGenerator
extends RefCounted

const AMBIENT_ROOT_NAME: StringName = &"Ambient"
const HALF: float = 0.5
const MIN_LENGTH: float = 0.001
## Vértices de um triângulo — o passo de leitura de uma malha.
const VERTS_PER_TRIANGLE: int = 3


## Monta a vida ambiente sob `parent`. Devolve o nó de runtime e a estatística.
static func build(layout: CityLayout, field: HeightField, parent: Node3D, world_seed: int) -> Dictionary:
	if layout == null:
		return {"node": null, "smoke": 0, "birds": 0, "leaves": 0}

	var root: AmbientLife = AmbientLife.new()
	root.name = String(AMBIENT_ROOT_NAME)
	parent.add_child(root)

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = world_seed + SEED_OFFSET

	var chimneys: int = _build_smoke(layout, root, rng)
	var birds: int = _build_birds(layout, root, rng)
	_build_leaves(layout, root)
	_build_dog(layout, field, root, rng)
	_build_hammer(layout, root)
	_apply_wind(parent)

	return {
		"node": root,
		"smoke": chimneys,
		"birds": birds,
		"leaves": Params.AMBIENT_LEAF_COUNT,
	}


const SEED_OFFSET: int = 40993


# --- Fumaça de chaminé --------------------------------------------------------


## Uma coluna de fumaça por telhado sorteado, entre os prédios mais altos.
##
## Mais altos porque é onde a chaminé fica visível de longe, e porque uma coluna saindo de
## um celeiro de um andar no meio de casas de dois se perde atrás delas.
static func _build_smoke(layout: CityLayout, root: Node3D, rng: RandomNumberGenerator) -> int:
	var tall: Array[Dictionary] = []
	for building: Dictionary in layout.buildings:
		if int(building["floors"]) >= 2:
			tall.append(building)
	if tall.is_empty():
		tall = layout.buildings.duplicate()
	if tall.is_empty():
		return 0

	var mesh: Mesh = _puff_mesh()
	var material: StandardMaterial3D = MaterialLibrary.get_material(&"plaster")
	var wanted: int = mini(Params.AMBIENT_SMOKE_CHIMNEYS, tall.size())

	for index: int in wanted:
		# Espalhados pela lista, e não os primeiros: os primeiros prédios são todos vizinhos
		# do centro, e seis colunas de fumaça saindo lado a lado leem como um incêndio.
		@warning_ignore("integer_division")
		var picked: int = (index * tall.size()) / maxi(wanted, 1)
		var building: Dictionary = tall[picked % tall.size()]
		var top: float = float(building["floors"]) * Params.CITY_FLOOR_HEIGHT
		var spot: Vector2 = building["center"]

		var particles: GPUParticles3D = GPUParticles3D.new()
		particles.name = "Smoke_%d" % index
		particles.amount = Params.AMBIENT_SMOKE_PARTICLES
		particles.lifetime = Params.AMBIENT_SMOKE_LIFETIME
		particles.draw_pass_1 = mesh
		particles.material_override = material
		particles.process_material = _smoke_material(rng)
		# Fumaça não projeta sombra. Cada caster é redesenhado uma vez por cascata, e uma
		# coluna de fumaça custaria três draw calls para escurecer um telhado que já está
		# na sombra do próprio beiral.
		particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		particles.position = layout.ground(spot, top + Params.CITY_ROOF_DROP)
		root.add_child(particles)
	return wanted


static func _smoke_material(rng: RandomNumberGenerator) -> ParticleProcessMaterial:
	var process: ParticleProcessMaterial = ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = SMOKE_SPREAD_DEG
	process.initial_velocity_min = Params.AMBIENT_SMOKE_RISE * HALF
	process.initial_velocity_max = Params.AMBIENT_SMOKE_RISE
	process.gravity = Vector3.ZERO
	process.scale_min = Params.AMBIENT_SMOKE_SCALE * HALF
	process.scale_max = Params.AMBIENT_SMOKE_SCALE
	# A fumaça engorda enquanto sobe e some: é o que a distingue de uma fila de cubos.
	var curve: Curve = Curve.new()
	curve.add_point(Vector2(0.0, SMOKE_START_SCALE))
	curve.add_point(Vector2(1.0, SMOKE_END_SCALE))
	var ramp: CurveTexture = CurveTexture.new()
	ramp.curve = curve
	process.scale_curve = ramp
	# Deriva lateral por seed: duas chaminés vizinhas com a mesma coluna reta entregam o
	# sistema de partículas.
	process.turbulence_enabled = true
	process.turbulence_noise_strength = rng.randf_range(SMOKE_DRIFT_MIN, SMOKE_DRIFT_MAX)
	return process


const SMOKE_SPREAD_DEG: float = 12.0
const SMOKE_START_SCALE: float = 0.4
const SMOKE_END_SCALE: float = 1.6
const SMOKE_DRIFT_MIN: float = 0.2
const SMOKE_DRIFT_MAX: float = 0.7


## Um cubo de seis faces, que é toda a geometria que uma partícula de fumaça low poly pede.
static func _puff_mesh() -> Mesh:
	var builder: MeshBuilder = MeshBuilder.new()
	builder.add_box(Vector3.ZERO, Vector3.ONE, Params.color(&"plaster"))
	return builder.commit(&"prop")


# --- Pássaros -----------------------------------------------------------------


static func _build_birds(layout: CityLayout, root: AmbientLife, rng: RandomNumberGenerator) -> int:
	var mesh: Mesh = _bird_mesh()
	var material: StandardMaterial3D = MaterialLibrary.get_material(Params.KIT_MATERIAL)
	var total: int = 0

	for flock_index: int in Params.AMBIENT_BIRD_FLOCKS:
		var multi: MultiMesh = MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = mesh
		multi.instance_count = Params.AMBIENT_BIRDS_PER_FLOCK

		var node: MultiMeshInstance3D = MultiMeshInstance3D.new()
		node.name = "Flock_%d" % flock_index
		node.multimesh = multi
		node.material_override = material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(node)

		var offsets: PackedVector3Array = PackedVector3Array()
		for _bird: int in Params.AMBIENT_BIRDS_PER_FLOCK:
			offsets.append(Vector3(
				rng.randf_range(-1.0, 1.0),
				rng.randf_range(-HALF, HALF),
				rng.randf_range(-1.0, 1.0)
			) * Params.AMBIENT_BIRD_SPREAD)

		var radius: float = Params.AMBIENT_BIRD_RADIUS * rng.randf_range(BIRD_RADIUS_MIN, 1.0)
		root.add_flock(
			node,
			layout.ground(layout.plaza, Params.AMBIENT_BIRD_HEIGHT),
			radius,
			offsets
		)
		total += Params.AMBIENT_BIRDS_PER_FLOCK
	return total


const BIRD_RADIUS_MIN: float = 0.6


## Um pássaro: dois triângulos em V, que a 17 m de altura é tudo o que se distingue.
static func _bird_mesh() -> Mesh:
	var builder: MeshBuilder = MeshBuilder.new()
	var color: Color = Params.color(&"slate")
	var span: float = BIRD_SPAN
	var tip: float = BIRD_TIP
	builder.add_triangle(
		Vector3.ZERO, Vector3(-span, tip, -tip), Vector3(-span, tip, tip), color
	)
	builder.add_triangle(
		Vector3.ZERO, Vector3(span, tip, tip), Vector3(span, tip, -tip), color
	)
	return builder.commit(&"prop")


const BIRD_SPAN: float = 0.38
const BIRD_TIP: float = 0.12


# --- Folhas -------------------------------------------------------------------


## Folhas caindo sobre a cidade inteira, num sistema só.
static func _build_leaves(layout: CityLayout, root: Node3D) -> void:
	var particles: GPUParticles3D = GPUParticles3D.new()
	particles.name = "Leaves"
	particles.amount = Params.AMBIENT_LEAF_COUNT
	particles.lifetime = Params.AMBIENT_LEAF_LIFETIME
	particles.draw_pass_1 = _leaf_mesh()
	particles.material_override = MaterialLibrary.get_material(&"foliage")
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var process: ParticleProcessMaterial = ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(
		Params.CITY_RADIUS, LEAF_BOX_HEIGHT, Params.CITY_RADIUS
	)
	process.direction = Vector3.DOWN
	process.spread = LEAF_SPREAD_DEG
	process.initial_velocity_min = Params.AMBIENT_LEAF_FALL * HALF
	process.initial_velocity_max = Params.AMBIENT_LEAF_FALL
	process.gravity = Vector3.ZERO
	process.scale_min = Params.AMBIENT_LEAF_SCALE * HALF
	process.scale_max = Params.AMBIENT_LEAF_SCALE
	# O rodopio é o que separa uma folha de uma pedra caindo.
	process.angular_velocity_min = -LEAF_SPIN_DEG
	process.angular_velocity_max = LEAF_SPIN_DEG
	particles.process_material = process

	particles.position = layout.ground(layout.plaza, LEAF_BOX_HEIGHT)
	root.add_child(particles)


const LEAF_BOX_HEIGHT: float = 9.0
const LEAF_SPREAD_DEG: float = 35.0
const LEAF_SPIN_DEG: float = 180.0


static func _leaf_mesh() -> Mesh:
	var builder: MeshBuilder = MeshBuilder.new()
	builder.add_plane_xz(Vector3.ZERO, Vector2.ONE, Params.color(&"moss"))
	return builder.commit(&"prop")


# --- Vento no varal -----------------------------------------------------------


## Shader de vértice nos panos: balanço no topo, pé preso.
##
## Vertex color continua sendo a cor — o shader só desloca. É o único `ShaderMaterial` do
## projeto, e existe porque a alternativa seria transformar cada pano numa malha própria
## para mexer nos vértices pela CPU, desfazendo o `MultiMesh` que a fase 8 montou.
static func _apply_wind(stage: Node3D) -> void:
	var banners: Node = _find_named(stage, &"banner")
	if banners == null or not banners is MultiMeshInstance3D:
		return
	var shader: Shader = Shader.new()
	shader.code = _wind_shader_code()
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter(&"wind_speed", Params.AMBIENT_WIND_SPEED)
	material.set_shader_parameter(&"sway", deg_to_rad(Params.AMBIENT_WIND_SWAY_DEG))
	(banners as MultiMeshInstance3D).material_override = material


## O deslocamento cresce com a altura do vértice **dentro da peça**, então o pano balança
## e a barra de cima fica quieta. A fase usa a posição de mundo da instância: dois varais
## lado a lado balançam fora de compasso, como dois varais de verdade.
##
## O código é montado por formatação, e não escrito literal, porque `make verify` cobra
## número mágico dentro de .gd — e uma constante enterrada numa string de shader é
## exatamente o tipo de número que ninguém encontra depois.
static func _wind_shader_code() -> String:
	return WIND_SHADER_TEMPLATE % [
		MODEL_ORIGIN_ROW, MODEL_ORIGIN_ROW, WIND_PLACE_SPREAD, WIND_CROSS_RATE
	]


## Linha da matriz de modelo que guarda a origem da instância.
const MODEL_ORIGIN_ROW: int = 3
## Quanto a posição de mundo desloca a fase. Sem isto todos os panos da cidade balançam
## juntos, e um vento perfeitamente sincronizado lê como máquina.
const WIND_PLACE_SPREAD: float = 0.7
## Razão entre o balanço transversal e o principal. Menor que 1: o pano vai e volta mais
## no eixo do vento do que atravessado a ele.
const WIND_CROSS_RATE: float = 0.7

const WIND_SHADER_TEMPLATE: String = """
shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;

uniform float wind_speed = 1.0;
uniform float sway = 0.0;

void vertex() {
	float height = max(VERTEX.y, 0.0);
	float place = MODEL_MATRIX[%d][0] + MODEL_MATRIX[%d][2];
	float phase = TIME * wind_speed + place * %f;
	VERTEX.x += sin(phase) * sway * height;
	VERTEX.z += cos(phase * %f) * sway * height * 0.5;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 1.0;
}
"""


static func _find_named(node: Node, wanted: StringName) -> Node:
	if node.name == wanted:
		return node
	for child: Node in node.get_children():
		var found: Node = _find_named(child, wanted)
		if found != null:
			return found
	return null


# --- Cachorro -----------------------------------------------------------------


## Um cachorro de seis caixas em ronda pela praça.
##
## Não é peça de kit: acrescentar a 35ª peça obrigaria a rodar a fábrica em Blender, mexer
## no manifesto e revalidar o catálogo inteiro por causa de um bicho de 60 triângulos que
## só aparece a 10 m. Gerado aqui, ele nasce e morre com a cidade.
static func _build_dog(
	layout: CityLayout, field: HeightField, root: AmbientLife, rng: RandomNumberGenerator
) -> void:
	var body: MeshInstance3D = MeshInstance3D.new()
	body.name = "Dog"
	body.mesh = _dog_mesh()
	body.material_override = MaterialLibrary.get_material(Params.KIT_MATERIAL)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(body)

	var route: PackedVector3Array = PackedVector3Array()
	for index: int in Params.AMBIENT_DOG_STOPS:
		var angle: float = TAU * float(index) / float(Params.AMBIENT_DOG_STOPS) + layout.angle
		var reach: float = Params.CITY_PLAZA_RADIUS * rng.randf_range(DOG_RING_MIN, DOG_RING_MAX)
		var spot: Vector2 = layout.plaza + Vector2(cos(angle), sin(angle)) * reach
		route.append(Vector3(spot.x, field.height_at(spot.x, spot.y), spot.y))
	root.set_dog(body, route)


const DOG_RING_MIN: float = 0.7
const DOG_RING_MAX: float = 1.5


static func _dog_mesh() -> Mesh:
	var builder: MeshBuilder = MeshBuilder.new()
	var fur: Color = Params.color(&"bark_light")
	var dark: Color = Params.color(&"bark")
	# Tronco, cabeça, focinho, cauda e quatro patas — a silhueta inteira de um cão a 10 m.
	builder.add_box(Vector3(0.0, DOG_BODY_Y, 0.0), Vector3(DOG_WIDTH, DOG_HEIGHT, DOG_LENGTH), fur)
	builder.add_box(Vector3(0.0, DOG_HEAD_Y, DOG_LENGTH * HALF), Vector3(DOG_HEAD, DOG_HEAD, DOG_HEAD), fur)
	builder.add_box(
		Vector3(0.0, DOG_HEAD_Y - DOG_HEAD * DOG_SNOUT_DROP, DOG_LENGTH * HALF + DOG_HEAD * DOG_SNOUT_DEPTH),
		Vector3(DOG_HEAD * DOG_SNOUT_SCALE, DOG_HEAD * DOG_SNOUT_SCALE, DOG_HEAD * DOG_SNOUT_DEPTH), dark
	)
	builder.add_box(
		Vector3(0.0, DOG_BODY_Y + DOG_HEIGHT * HALF, -DOG_LENGTH * HALF - DOG_TAIL * HALF),
		Vector3(DOG_TAIL * DOG_TAIL_THICKNESS, DOG_TAIL * DOG_TAIL_THICKNESS, DOG_TAIL), dark
	)
	for side: int in 2:
		for end_index: int in 2:
			var x: float = (DOG_WIDTH * HALF - DOG_LEG * HALF) * (1.0 if side == 0 else -1.0)
			var z: float = (DOG_LENGTH * DOG_LEG_SPACING) * (1.0 if end_index == 0 else -1.0)
			builder.add_box(
				Vector3(x, DOG_LEG_Y, z), Vector3(DOG_LEG, DOG_LEG_HEIGHT, DOG_LEG), dark
			)
	return builder.commit(&"prop")


const DOG_WIDTH: float = 0.26
const DOG_HEIGHT: float = 0.28
const DOG_LENGTH: float = 0.62
const DOG_HEAD: float = 0.22
const DOG_TAIL: float = 0.22
const DOG_LEG: float = 0.09
const DOG_LEG_HEIGHT: float = 0.3
const DOG_LEG_Y: float = 0.15
const DOG_BODY_Y: float = 0.44
const DOG_HEAD_Y: float = 0.54
## Proporções internas do cão, como fração das medidas acima. São de desenho da peça, não
## de jogabilidade: mudar o comprimento do corpo tem de arrastar as patas junto.
const DOG_TAIL_THICKNESS: float = 0.4
const DOG_LEG_SPACING: float = 0.3
const DOG_SNOUT_SCALE: float = 0.5
const DOG_SNOUT_DEPTH: float = 0.6
const DOG_SNOUT_DROP: float = 0.2


# --- Martelo da ferraria ------------------------------------------------------


static func _build_hammer(layout: CityLayout, root: AmbientLife) -> void:
	if not layout.markers.has(&"ferraria"):
		return
	var pivot: Node3D = Node3D.new()
	pivot.name = "Hammer"
	var head: MeshInstance3D = MeshInstance3D.new()
	head.name = "Head"
	head.mesh = _hammer_mesh()
	head.material_override = MaterialLibrary.get_material(&"metal")
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(head)

	# Em frente à porta da ferraria, na altura da bigorna: é ali que o artesão fica.
	var door: Vector3 = layout.markers[&"ferraria"]
	pivot.position = door + Vector3.UP * HAMMER_HEIGHT
	root.add_child(pivot)
	root.set_hammer(pivot, null)


const HAMMER_HEIGHT: float = 0.85


static func _hammer_mesh() -> Mesh:
	var builder: MeshBuilder = MeshBuilder.new()
	builder.add_box(Vector3.ZERO, Vector3(HAMMER_HEAD, HAMMER_HEAD, HAMMER_HEAD * 2.0), Params.color(&"iron"))
	builder.add_box(
		Vector3(0.0, -HAMMER_SHAFT * HALF, 0.0),
		Vector3(HAMMER_HEAD * HAMMER_GRIP, HAMMER_SHAFT, HAMMER_HEAD * HAMMER_GRIP),
		Params.color(&"wood")
	)
	return builder.commit(&"prop")


const HAMMER_HEAD: float = 0.11
const HAMMER_SHAFT: float = 0.34
## Espessura do cabo como fração da cabeça do martelo.
const HAMMER_GRIP: float = 0.4
