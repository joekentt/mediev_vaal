@tool
## Põe a cidade de pé: transforma o traçado de `CityLayout` em nós, malhas e colisão.
##
## Nada aqui decide nada. O que é onde já foi decidido em `CityGenerator`; este arquivo só
## empilha peças do kit e cuida para que empilhar dez mil delas não custe dez mil draw
## calls. Três regras fazem esse trabalho, e as três são de geração, não de otimização
## posterior:
##
## 1. **Peça igual vira instância, não nó.** Toda cópia de `wall` na cidade inteira mora
##    num `MultiMesh` só. A cor de cada prédio viaja na instância, então tom não custa
##    material — e material novo é agrupamento perdido.
## 2. **Colisão é sempre caixa.** Um prédio é uma caixa; um prédio com interior de verdade
##    são quatro, uma por parede. Malha de colisão a partir das peças daria ao motor de
##    física a silhueta de cada telha para nada: ninguém encosta num beiral.
## 3. **Muralha e fachada grande são occluder.** São as duas coisas da cidade que escondem
##    muita coisa atrás de si, e é o que segura os draw calls na praça.
class_name CityBuilder
extends RefCounted

const CITY_ROOT_NAME: StringName = &"City"
const MARKERS_NAME: StringName = &"Markers"
const CARD_MESH_CATEGORY: StringName = &"city_block"
const HALF: float = 0.5
## Lados de uma caixa em planta — as quatro paredes de um prédio.
const WALL_SIDES: int = 4
## Módulos de parede por passo de profundidade. O passo é 4 m e a peça tem 2 m.
const MODULES_PER_STEP: int = 2
## Tentativas antes de desistir de achar lugar livre para um prop.
const PLACEMENT_TRIES: int = 10
const HECTARE: float = 10000.0
const MIN_LENGTH: float = 0.001

## Peças do kit usadas pela cidade, carregadas uma vez por sessão.
static var _meshes: Dictionary = {}


# --- Entrada ------------------------------------------------------------------


## Constrói a cidade inteira sob `parent` e devolve estatística para o relatório.
static func build(
	layout: CityLayout, field: HeightField, parent: Node3D, world_seed: int
) -> Dictionary:
	var root: Node3D = Node3D.new()
	root.name = CITY_ROOT_NAME
	parent.add_child(root)

	var pool: Dictionary = {}
	var cards: MeshBuilder = MeshBuilder.new()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = world_seed

	var wall_boxes: Array[Dictionary] = _build_wall(layout, field, pool, root)
	var building_boxes: Array[Dictionary] = _build_buildings(layout, field, pool, cards, root, rng)
	var lanterns: Array[Vector3] = _build_props(layout, field, pool, rng)
	_build_markers(layout, root)

	var instances: int = _flush(pool, root)
	_build_cards(cards, root)
	_build_occluders(wall_boxes + building_boxes, root)
	var night: Dictionary = _build_night_lights(lanterns, layout, root)

	return {
		"instances": instances,
		"draw_nodes": _pool_size(pool),
		"occluders": wall_boxes.size() + building_boxes.size(),
		"lanterns": lanterns.size(),
		"lantern_lights": night["lights"],
		"lantern_glow": night["glow"],
	}


# --- A noite ------------------------------------------------------------------


## O que a cidade acende quando escurece: o vidro dos lampiões e algumas luzes de verdade.
##
## A divisão entre os dois é orçamento, e é a mesma que todo jogo faz sem dizer. Cada
## lampião ganha um quadrado emissivo — todos num `MeshInstance3D` só, um draw call para a
## cidade inteira, e o material já é o das janelas. Só os `DAY_CYCLE_LANTERN_LIGHTS` mais
## próximos da praça ganham `OmniLight3D`, porque luz pontual custa por objeto iluminado e
## a praça é o único lugar em que alguém para para olhar.
##
## Nenhuma delas projeta sombra. Sombra pontual é atlas, e o orçamento tem quatro — todas
## reservadas para os interiores da fase 9.
static func _build_night_lights(
	spots: Array[Vector3], layout: CityLayout, root: Node3D
) -> Dictionary:
	var lights: Array[OmniLight3D] = []
	var glow: MeshInstance3D = null
	if spots.is_empty():
		return {"lights": lights, "glow": glow}

	var builder: MeshBuilder = MeshBuilder.new()
	var head: Vector3 = Vector3.UP * Params.DAY_CYCLE_LANTERN_HEIGHT
	var size: Vector3 = Vector3.ONE * Params.DAY_CYCLE_GLOW_SIZE
	for spot: Vector3 in spots:
		builder.add_box(spot + head, size, Params.color(&"window_light"))

	var mesh: ArrayMesh = builder.commit(CARD_MESH_CATEGORY)
	if mesh != null:
		glow = MeshInstance3D.new()
		glow.name = "LanternGlow"
		glow.mesh = mesh
		glow.material_override = MaterialLibrary.get_material(Params.GLOW_MATERIAL)
		glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		glow.visible = false
		root.add_child(glow)

	var ordered: Array[Vector3] = spots.duplicate()
	var plaza: Vector2 = layout.plaza
	ordered.sort_custom(
		func(a: Vector3, b: Vector3) -> bool:
			return Vector2(a.x, a.z).distance_squared_to(plaza) \
				< Vector2(b.x, b.z).distance_squared_to(plaza)
	)
	var wanted: int = mini(Params.DAY_CYCLE_LANTERN_LIGHTS, ordered.size())
	for index: int in wanted:
		var lamp: OmniLight3D = OmniLight3D.new()
		lamp.name = "Lantern%02d" % index
		lamp.position = ordered[index] + head
		lamp.light_color = Params.color(&"window_light")
		lamp.light_energy = 0.0
		lamp.omni_range = Params.DAY_CYCLE_LANTERN_RANGE
		lamp.shadow_enabled = false
		lamp.visible = false
		root.add_child(lamp)
		lights.append(lamp)
	return {"lights": lights, "glow": glow}


# --- Peças do kit -------------------------------------------------------------


static func mesh_of(part: StringName) -> Mesh:
	if _meshes.has(part):
		return _meshes[part]
	var path: String = "%s/%s.glb" % [Params.KIT_DIR, part]
	var packed: PackedScene = ResourceLoader.load(path) as PackedScene
	if packed == null:
		push_error("Peça do kit ausente: %s. Rode `make assets`." % path)
		_meshes[part] = null
		return null
	var instance: Node3D = packed.instantiate() as Node3D
	var found: Mesh = _find_mesh(instance)
	instance.queue_free()
	_meshes[part] = found
	return found


static func _find_mesh(node: Node) -> Mesh:
	if node is MeshInstance3D:
		return (node as MeshInstance3D).mesh
	for child: Node in node.get_children():
		var found: Mesh = _find_mesh(child)
		if found != null:
			return found
	return null


## Tamanho da peça em metros. Toda peça do kit nasce com a origem no canto mínimo, então a
## caixa envolvente começa em zero e o tamanho é tudo o que se precisa saber.
static func size_of(part: StringName) -> Vector3:
	var mesh: Mesh = mesh_of(part)
	if mesh == null:
		return Vector3.ONE
	return mesh.get_aabb().size


## Enfileira uma peça com o **centro da base** em `spot`, girada `yaw` em torno de Y.
##
## Centro da base, e não a origem da peça: a origem fica no canto mínimo, e posicionar por
## ela obrigaria cada chamador a lembrar da metade da largura da peça que está usando.
static func place(
	pool: Dictionary, part: StringName, spot: Vector3, yaw: float, tint: Color = Color.WHITE
) -> void:
	var size: Vector3 = size_of(part)
	var basis: Basis = Basis(Vector3.UP, yaw)
	var offset: Vector3 = basis * Vector3(-size.x * HALF, 0.0, -size.z * HALF)
	if not pool.has(part):
		pool[part] = []
	pool[part].append({"transform": Transform3D(basis, spot + offset), "tint": tint})


## Fecha os lotes de instâncias em `MultiMeshInstance3D`, um por peça.
static func _flush(pool: Dictionary, root: Node3D) -> int:
	var total: int = 0
	var parts: Array = pool.keys()
	parts.sort()  # ordem estável: a árvore de cena tem de sair igual em duas execuções
	for part: StringName in parts:
		var entries: Array = pool[part]
		if entries.is_empty():
			continue
		var mesh: Mesh = mesh_of(part)
		if mesh == null:
			continue

		var multi: MultiMesh = MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.use_colors = true
		multi.mesh = mesh
		multi.instance_count = entries.size()
		for index: int in entries.size():
			multi.set_instance_transform(index, entries[index]["transform"])
			multi.set_instance_color(index, entries[index]["tint"])

		var node: MultiMeshInstance3D = MultiMeshInstance3D.new()
		node.name = String(part)
		node.multimesh = multi
		root.add_child(node)
		total += entries.size()
	return total


static func _pool_size(pool: Dictionary) -> int:
	var used: int = 0
	for part: StringName in pool:
		if not pool[part].is_empty():
			used += 1
	return used


# --- b) Muralha ---------------------------------------------------------------


## Muralha em módulos, torres nos vértices e o portão no lado que a estrada escolheu.
static func _build_wall(
	layout: CityLayout, field: HeightField, pool: Dictionary, root: Node3D
) -> Array[Dictionary]:
	var boxes: Array[Dictionary] = []
	var count: int = layout.wall.size()
	var module: float = Params.CITY_WALL_MODULE
	var wall_size: Vector3 = size_of(&"wall")

	for index: int in count:
		var a: Vector2 = layout.wall[index]
		var b: Vector2 = layout.wall[(index + 1) % count]
		var span: Vector2 = b - a
		var length: float = span.length()
		if length < MIN_LENGTH:
			continue
		var direction: Vector2 = span / length
		# A peça olha para fora: +Z do kit tem de apontar para longe do centro.
		var outward: Vector2 = direction.orthogonal()
		if outward.dot(a - layout.center) < 0.0:
			outward = -outward
		var yaw: float = atan2(outward.x, outward.y)

		var gap: float = Params.CITY_GATE_WIDTH if index == layout.gate_index else 0.0
		var modules: int = maxi(int(floor((length - gap) / module)), 0)
		var used: float = float(modules) * module + gap
		var start: float = (length - used) * HALF
		var travelled: float = start

		for piece: int in modules:
			# O vão do portão fica no meio do lado; as peças param antes e recomeçam depois.
			if gap > 0.0 and absf(travelled + module * HALF - length * HALF) < gap * HALF:
				travelled += gap
			var middle: Vector2 = a + direction * (travelled + module * HALF)
			place(pool, &"wall", _ground(field, middle), yaw)
			travelled += module

		if gap > 0.0:
			var gate_spot: Vector2 = a + direction * (length * HALF)
			place(pool, &"wall_gate", _ground(field, gate_spot), yaw)

		if index % Params.CITY_TOWER_EVERY == 0:
			place(pool, &"tower", _ground(field, a), yaw)

		boxes.append({
			"center": _ground(field, (a + b) * HALF) + Vector3.UP * (wall_size.y * HALF),
			"size": Vector3(length, wall_size.y, wall_size.z),
			"yaw": yaw,
		})

	_collide(root, boxes, &"WallCollision")
	return boxes


static func _ground(field: HeightField, point: Vector2) -> Vector3:
	return Vector3(point.x, field.height_at(point.x, point.y), point.y)


# --- e) Prédios ---------------------------------------------------------------


static func _build_buildings(
	layout: CityLayout,
	field: HeightField,
	pool: Dictionary,
	cards: MeshBuilder,
	root: Node3D,
	rng: RandomNumberGenerator
) -> Array[Dictionary]:
	var boxes: Array[Dictionary] = []
	var solid: Array[Dictionary] = []
	var hollow: Array[Dictionary] = []

	for building: Dictionary in layout.buildings:
		var real_interior: bool = building["type"] in Params.CITY_INTERIOR_TYPES
		_raise_one(field, pool, cards, building, rng, real_interior)

		var height: float = float(building["floors"]) * Params.CITY_FLOOR_HEIGHT
		var facing: Vector2 = building["facing"]
		var yaw: float = atan2(facing.x, facing.y)
		var base: Vector3 = _ground(field, building["center"])
		var box: Dictionary = {
			"center": base + Vector3.UP * (height * HALF),
			"size": Vector3(float(building["width"]), height, float(building["depth"])),
			"yaw": yaw,
		}
		boxes.append(box)
		# Interior de verdade não pode ser tapado por uma caixa maciça: quem entra pela
		# porta bateria numa parede invisível a um passo dela.
		if real_interior:
			hollow.append(box)
		else:
			solid.append(box)

	_collide(root, solid, &"BuildingCollision")
	_collide_hollow(root, hollow, &"InteriorCollision")
	return boxes


## Empilha um prédio: piso, andares de parede, telhado e — quando é o caso — interior.
static func _raise_one(
	field: HeightField,
	pool: Dictionary,
	cards: MeshBuilder,
	building: Dictionary,
	rng: RandomNumberGenerator,
	real_interior: bool
) -> void:
	var facing: Vector2 = building["facing"]
	var yaw: float = atan2(facing.x, facing.y)
	var basis: Basis = Basis(Vector3.UP, yaw)
	var base: Vector3 = _ground(field, building["center"])
	var tint: Color = building["tint"]

	var modules: int = building["modules"]
	var steps: int = building["depth_steps"]
	var width: float = building["width"]
	var depth: float = building["depth"]
	var module: float = Params.CITY_BUILDING_MODULE
	var floors: int = building["floors"]

	# Piso só onde ele é visto. Um `floor_tile` custa 48 triângulos — mais que as duas
	# paredes que o cercam — e num prédio de interior falso ele fica debaixo do telhado,
	# atrás de portas fechadas, para sempre. Ladrilhar todos os prédios gastava um terço do
	# orçamento de triângulos da cidade em chão que ninguém pisa.
	if real_interior:
		for row: int in steps * MODULES_PER_STEP:
			for column: int in modules:
				var local: Vector3 = Vector3(
					-width * HALF + (float(column) + HALF) * module,
					0.0,
					-depth * HALF + (float(row) + HALF) * module
				)
				place(pool, &"floor_tile", base + basis * local, yaw, tint)

	# A porta fica no módulo do meio da fachada. A divisão inteira é o que se quer: numa
	# fachada de largura par, "meio" é o módulo à direita do centro, e é indiferente qual.
	@warning_ignore("integer_division")
	var door_module: int = modules / 2
	for level: int in floors:
		var y: float = float(level) * Params.CITY_FLOOR_HEIGHT
		_wall_run(
			pool, cards, base, basis, yaw, tint,
			Vector3(0.0, y, depth * HALF), Vector3.RIGHT, modules,
			(door_module if level == 0 else -1), rng, real_interior
		)
		_wall_run(
			pool, cards, base, basis, yaw + PI, tint,
			Vector3(0.0, y, -depth * HALF), Vector3.RIGHT, modules,
			-1, rng, real_interior
		)
		_wall_run(
			pool, cards, base, basis, yaw + PI * HALF, tint,
			Vector3(width * HALF, y, 0.0), Vector3.BACK, steps * MODULES_PER_STEP,
			-1, rng, real_interior
		)
		_wall_run(
			pool, cards, base, basis, yaw - PI * HALF, tint,
			Vector3(-width * HALF, y, 0.0), Vector3.BACK, steps * MODULES_PER_STEP,
			-1, rng, real_interior
		)

	_roof(pool, base, basis, yaw, tint, modules, steps, width, depth, floors, rng)
	if real_interior:
		_furnish(pool, base, basis, tint, width, depth, building["type"], rng)


## Uma fileira de módulos de parede. `door_at` marca o módulo que vira porta; -1 é sem
## porta. A carta de interior falso nasce aqui, atrás de cada janela.
static func _wall_run(
	pool: Dictionary,
	cards: MeshBuilder,
	base: Vector3,
	basis: Basis,
	yaw: float,
	tint: Color,
	origin: Vector3,
	along: Vector3,
	modules: int,
	door_at: int,
	rng: RandomNumberGenerator,
	real_interior: bool
) -> void:
	var module: float = Params.CITY_BUILDING_MODULE
	var run: float = float(modules) * module
	for index: int in modules:
		var offset: float = -run * HALF + (float(index) + HALF) * module
		var local: Vector3 = origin + along * offset
		var part: StringName = &"wall"
		if index == door_at:
			part = &"wall_door"
		elif rng.randf() < Params.CITY_WINDOW_CHANCE:
			part = &"wall_window"
		place(pool, part, base + basis * local, yaw, tint)

		if part == &"wall_window" and not real_interior:
			_interior_card(cards, base + basis * local, yaw, tint)


## Carta de interior falso: um plano escuro logo atrás da fachada.
##
## Custa dois triângulos e resolve o efeito que a janela vazia estraga — sem ela, o olho
## atravessa o vão e vê o céu do outro lado, e a casa lê como cenário de teatro.
static func _interior_card(cards: MeshBuilder, spot: Vector3, yaw: float, tint: Color) -> void:
	var basis: Basis = Basis(Vector3.UP, yaw)
	var size: Vector3 = size_of(&"wall_window")
	# O recuo conta a partir da **face de trás da peça**, não do centro dela. Contado do
	# centro, a carta ficava a 5 mm da parede — dentro da margem de profundidade do
	# renderizador — e a fachada inteira saía listrada de z-fighting.
	var back: Vector3 = spot + basis * Vector3(
		0.0, 0.0, -size.z * HALF - Params.CITY_INTERIOR_CARD_INSET
	)
	var half_width: Vector3 = basis * Vector3(size.x * HALF, 0.0, 0.0)
	var low: Vector3 = back + Vector3.UP * (size.y * Params.CITY_INTERIOR_CARD_INSET)
	var high: Vector3 = back + Vector3.UP * size.y
	var color: Color = (tint * Params.color(&"wood_dark")).darkened(
		Params.CITY_INTERIOR_CARD_DARKEN
	)
	cards.add_quad(
		low - half_width, low + half_width, high + half_width, high - half_width, color
	)


## Telhado: quatro águas quando a planta permite, duas águas no resto.
##
## As duas peças do kit ladrilham medidas fixas — `roof_hip` cobre 4x4 m e `roof_gable`
## cobre 2x4 m —, e é por isso que a planta do prédio é obrigada a andar nessa malha. Sem
## isso sobraria um pedaço de laje sem telha, e não existe peça de remate.
static func _roof(
	pool: Dictionary,
	base: Vector3,
	basis: Basis,
	yaw: float,
	tint: Color,
	modules: int,
	steps: int,
	width: float,
	depth: float,
	floors: int,
	rng: RandomNumberGenerator
) -> void:
	var top: float = float(floors) * Params.CITY_FLOOR_HEIGHT - Params.CITY_ROOF_DROP
	var module: float = Params.CITY_BUILDING_MODULE
	var step: float = Params.CITY_BUILDING_DEPTH_STEP
	# Duas águas cobrem 2 m de fachada cada, quatro águas cobrem 4 m: só uma fachada com
	# número par de módulos ladrilha com telhado de quatro águas sem deixar sobra.
	var hip: bool = modules % 2 == 0 and rng.randf() < Params.CITY_HIP_ROOF_CHANCE

	for row: int in steps:
		var z: float = -depth * HALF + (float(row) + HALF) * step
		if hip:
			@warning_ignore("integer_division")
			for pair: int in modules / 2:
				var x: float = -width * HALF + (float(pair) + HALF) * step
				place(pool, &"roof_hip", base + basis * Vector3(x, top, z), yaw, tint)
			continue
		for column: int in modules:
			var x_gable: float = -width * HALF + (float(column) + HALF) * module
			place(pool, &"roof_gable", base + basis * Vector3(x_gable, top, z), yaw, tint)


# --- g) Interiores de verdade -------------------------------------------------


## Mobília dos dois interiores reais. Taverna ganha bancos, mesas improvisadas em caixotes
## e potes; ferraria ganha bigorna, barris e sacos.
static func _furnish(
	pool: Dictionary,
	base: Vector3,
	basis: Basis,
	tint: Color,
	width: float,
	depth: float,
	type_name: StringName,
	rng: RandomNumberGenerator
) -> void:
	# Ternário devolve `Array` sem tipo, e atribuí-lo a `Array[StringName]` falha em
	# runtime com "Trying to assign an array of type Array". O `if` explícito preserva o
	# tipo dos dois lados.
	var kit: Array[StringName] = []
	if type_name == &"taverna":
		kit = [&"bench", &"crate", &"pot", &"barrel"]
	else:
		kit = [&"anvil", &"barrel", &"sack", &"crate"]
	var inset: float = Params.CITY_LOT_SETBACK + Params.CITY_BUILDING_MODULE * HALF
	for index: int in Params.CITY_INTERIOR_PROPS:
		var part: StringName = kit[index % kit.size()]
		var local: Vector3 = Vector3(
			rng.randf_range(-width * HALF + inset, width * HALF - inset),
			0.0,
			rng.randf_range(-depth * HALF + inset, depth * HALF - inset)
		)
		place(pool, part, base + basis * local, rng.randf_range(0.0, TAU), tint)


static func _build_cards(cards: MeshBuilder, root: Node3D) -> void:
	if cards.triangle_count() == 0:
		return
	var mesh: ArrayMesh = cards.commit(CARD_MESH_CATEGORY)
	if mesh == null:
		return
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = "InteriorCards"
	node.mesh = mesh
	# Material emissivo, e é ele que faz a noite. De dia a emissão é zero e a carta é o
	# mesmo escuro de sempre atrás da janela; à noite `DayNightCycle` sobe a emissão **do
	# material** e cada janela da cidade acende junto, numa única atribuição. A alternativa
	# — uma luz por janela — seria centenas de luzes para um orçamento de quatro.
	node.material_override = MaterialLibrary.get_material(Params.GLOW_MATERIAL)
	root.add_child(node)


# --- f) Props -----------------------------------------------------------------


static func _build_props(
	layout: CityLayout, field: HeightField, pool: Dictionary, rng: RandomNumberGenerator
) -> Array[Vector3]:
	_plaza_props(layout, field, pool, rng)
	var lanterns: Array[Vector3] = _street_lanterns(layout, field, pool)
	_loose_props(layout, field, pool, rng)
	_yards(layout, field, pool, rng)
	_clotheslines(layout, field, pool, rng)
	return lanterns


## Praça: poço no meio, bancas em anel, bancos entre elas.
static func _plaza_props(
	layout: CityLayout, field: HeightField, pool: Dictionary, rng: RandomNumberGenerator
) -> void:
	place(pool, &"well", _ground(field, layout.plaza), rng.randf_range(0.0, TAU))

	for index: int in Params.CITY_PLAZA_STALLS:
		var angle: float = TAU * float(index) / float(Params.CITY_PLAZA_STALLS) + layout.angle
		var direction: Vector2 = Vector2(cos(angle), sin(angle))
		var spot: Vector2 = layout.plaza + direction * Params.CITY_PLAZA_STALL_RING
		# A banca olha para o centro da praça, que é onde a freguesia está.
		place(pool, &"market_stall", _ground(field, spot), atan2(-direction.x, -direction.y))

		var between: float = angle + PI / float(Params.CITY_PLAZA_STALLS)
		var bench_dir: Vector2 = Vector2(cos(between), sin(between))
		var bench_spot: Vector2 = layout.plaza + bench_dir * (Params.CITY_PLAZA_STALL_RING * HALF)
		place(pool, &"bench", _ground(field, bench_spot), atan2(-bench_dir.x, -bench_dir.y))


## Lanternas ao longo das ruas, do lado de fora da faixa de rolamento.
##
## Devolve onde cada uma ficou: é dessa lista que sai a iluminação da noite, e recalculá-la
## depois obrigaria a repetir a mesma varredura de ruas com as mesmas regras de descarte.
static func _street_lanterns(
	layout: CityLayout, field: HeightField, pool: Dictionary
) -> Array[Vector3]:
	var spots: Array[Vector3] = []
	for street: Dictionary in layout.streets:
		if int(street["rank"]) > CityLayout.RANK_STREET:
			continue
		var a: Vector2 = street["a"]
		var b: Vector2 = street["b"]
		var length: float = a.distance_to(b)
		if length < Params.CITY_LANTERN_SPACING:
			continue
		var direction: Vector2 = (b - a) / length
		var side: Vector2 = direction.orthogonal() * (float(street["width"]) * HALF)
		var count: int = int(floor(length / Params.CITY_LANTERN_SPACING))
		for index: int in count:
			var travel: float = (float(index) + HALF) * Params.CITY_LANTERN_SPACING
			var spot: Vector2 = a + direction * travel + side
			if not CityLayout.inside(layout.buildable, spot):
				continue
			var base: Vector3 = _ground(field, spot)
			place(pool, &"lantern_post", base, 0.0)
			spots.append(base)
	return spots


## Barris, caixotes, carroças e sacos encostados nas ruas.
##
## O sorteio recusa qualquer ponto que caia dentro da faixa de rolamento: prop no meio da
## rua não lê como cidade viva, lê como colisão esquecida.
static func _loose_props(
	layout: CityLayout, field: HeightField, pool: Dictionary, rng: RandomNumberGenerator
) -> void:
	var parts: Array[StringName] = [&"barrel", &"crate", &"cart", &"sack", &"pot", &"log"]
	var reach: float = Params.CITY_RADIUS - Params.CITY_WALL_MARGIN
	var area_ha: float = (PI * reach * reach) / HECTARE
	var wanted: int = int(round(Params.CITY_PROP_DENSITY * area_ha))

	for _index: int in wanted:
		for _try: int in PLACEMENT_TRIES:
			var angle: float = rng.randf_range(0.0, TAU)
			var distance: float = sqrt(rng.randf()) * reach
			var spot: Vector2 = layout.center + Vector2(cos(angle), sin(angle)) * distance
			if not CityLayout.inside(layout.buildable, spot):
				continue
			var clearance: float = layout.street_clearance(spot)
			# Encostado na rua, não no meio dela nem dentro do quarteirão.
			if clearance < 0.0 or clearance > Params.CITY_LOT_SETBACK * 2.0:
				continue
			var part: StringName = parts[rng.randi_range(0, parts.size() - 1)]
			place(pool, part, _ground(field, spot), rng.randf_range(0.0, TAU))
			break


## Lotes vazios viram pátio: cerca em volta e alguma coisa dentro.
static func _yards(
	layout: CityLayout, field: HeightField, pool: Dictionary, rng: RandomNumberGenerator
) -> void:
	var occupied: Array[Vector2] = []
	for building: Dictionary in layout.buildings:
		occupied.append(building["center"])

	var parts: Array[StringName] = [&"stump", &"crate", &"pot", &"bush", &"sack"]
	for lot: Dictionary in layout.lots:
		var center: Vector2 = lot["center"]
		var taken: bool = false
		for spot: Vector2 in occupied:
			if spot.distance_to(center) < Params.CITY_LOT_MIN:
				taken = true
				break
		if taken:
			continue

		var facing: Vector2 = lot["facing"]
		var yaw: float = atan2(facing.x, facing.y)
		var width: float = float(lot["width"])
		var modules: int = maxi(int(floor(width / Params.CITY_WALL_MODULE)), 1)
		var fence_line: Vector2 = center + facing * (float(lot["depth"]) * HALF - Params.CITY_LOT_SETBACK)
		var along: Vector2 = facing.orthogonal()
		for index: int in modules:
			var offset: float = -width * HALF + (float(index) + HALF) * Params.CITY_WALL_MODULE
			place(pool, &"fence", _ground(field, fence_line + along * offset), yaw)

		for _index: int in Params.CITY_YARD_PROPS:
			var inside_spot: Vector2 = center + Vector2(
				rng.randf_range(-width * HALF, width * HALF),
				rng.randf_range(-float(lot["depth"]) * HALF, 0.0)
			).rotated(layout.angle)
			var part: StringName = parts[rng.randi_range(0, parts.size() - 1)]
			place(pool, part, _ground(field, inside_spot), rng.randf_range(0.0, TAU))


## Varais atravessando os becos: duas cordas nas pontas e um pano no meio.
##
## É o detalhe que mais barato converte "rua" em "gente mora aqui", e só cabe em beco: num
## vão de rua larga a corda ficaria pendurada no ar sem apoio nenhum.
static func _clotheslines(
	layout: CityLayout, field: HeightField, pool: Dictionary, rng: RandomNumberGenerator
) -> void:
	for street: Dictionary in layout.streets:
		if int(street["rank"]) != CityLayout.RANK_ALLEY:
			continue
		if float(street["width"]) > Params.CITY_CLOTHESLINE_MAX_SPAN:
			continue
		if rng.randf() > Params.CITY_CLOTHESLINE_CHANCE:
			continue

		var a: Vector2 = street["a"]
		var b: Vector2 = street["b"]
		var length: float = a.distance_to(b)
		if length < MIN_LENGTH:
			continue
		var direction: Vector2 = (b - a) / length
		var across: Vector2 = direction.orthogonal() * (float(street["width"]) * HALF)
		var middle: Vector2 = a + direction * (length * HALF)
		if not CityLayout.inside(layout.buildable, middle):
			continue

		var height: float = Params.CITY_CLOTHESLINE_HEIGHT
		var yaw: float = atan2(direction.x, direction.y)
		place(pool, &"rope", _ground(field, middle + across) + Vector3.UP * height, yaw)
		place(pool, &"rope", _ground(field, middle - across) + Vector3.UP * height, yaw)
		place(pool, &"banner", _ground(field, middle) + Vector3.UP * (height - size_of(&"banner").y), yaw)


# --- Marcadores, colisão e oclusão --------------------------------------------


static func _build_markers(layout: CityLayout, root: Node3D) -> void:
	var holder: Node3D = Node3D.new()
	holder.name = MARKERS_NAME
	root.add_child(holder)

	var names: Array = layout.markers.keys()
	names.sort()
	for name: StringName in names:
		var marker: Marker3D = Marker3D.new()
		marker.name = String(name)
		marker.position = layout.markers[name]
		holder.add_child(marker)


## Um corpo estático com uma caixa por entrada. Entra no grupo de navegação: é assim que a
## malha de caminho contorna os prédios sem que ninguém desenhe o contorno à mão.
static func _collide(root: Node3D, boxes: Array[Dictionary], node_name: StringName) -> void:
	if boxes.is_empty():
		return
	var body: StaticBody3D = StaticBody3D.new()
	body.name = String(node_name)
	body.collision_layer = Params.LAYER_WORLD
	body.collision_mask = 0
	root.add_child(body)
	body.add_to_group(Params.NAV_GROUP)

	for index: int in boxes.size():
		var box: Dictionary = boxes[index]
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = box["size"]
		var collider: CollisionShape3D = CollisionShape3D.new()
		collider.name = "Box_%d" % index
		collider.shape = shape
		collider.transform = Transform3D(Basis(Vector3.UP, float(box["yaw"])), box["center"])
		body.add_child(collider)


## Prédio com interior de verdade: quatro caixas finas, uma por parede, em vez de um bloco.
static func _collide_hollow(
	root: Node3D, boxes: Array[Dictionary], node_name: StringName
) -> void:
	if boxes.is_empty():
		return
	var body: StaticBody3D = StaticBody3D.new()
	body.name = String(node_name)
	body.collision_layer = Params.LAYER_WORLD
	body.collision_mask = 0
	root.add_child(body)
	body.add_to_group(Params.NAV_GROUP)

	var thickness: float = size_of(&"wall").z
	var index: int = 0
	for box: Dictionary in boxes:
		var size: Vector3 = box["size"]
		var yaw: float = box["yaw"]
		var basis: Basis = Basis(Vector3.UP, yaw)
		for side: int in WALL_SIDES:
			# A parede da frente é a do vão da porta: fica de fora, senão a caixa fecha a
			# entrada que o `wall_door` acabou de abrir.
			if side == 0:
				continue
			var slab: Vector3 = Vector3.ZERO
			var offset: Vector3 = Vector3.ZERO
			if side == 1:
				slab = Vector3(size.x, size.y, thickness)
				offset = Vector3(0.0, 0.0, -size.z * HALF)
			elif side == 2:
				slab = Vector3(thickness, size.y, size.z)
				offset = Vector3(size.x * HALF, 0.0, 0.0)
			else:
				slab = Vector3(thickness, size.y, size.z)
				offset = Vector3(-size.x * HALF, 0.0, 0.0)

			var shape: BoxShape3D = BoxShape3D.new()
			shape.size = slab
			var collider: CollisionShape3D = CollisionShape3D.new()
			collider.name = "Slab_%d" % index
			collider.shape = shape
			collider.transform = Transform3D(basis, Vector3(box["center"]) + basis * offset)
			body.add_child(collider)
			index += 1


## Occluders na muralha e nas fachadas grandes.
##
## Occlusion culling só paga quando o occluder é grande e opaco. Uma casa de 4 m esconde
## pouco e custa um teste; a muralha esconde a cidade inteira de fora, e um celeiro de 10 m
## esconde a rua de trás. O corte por área é o que separa os dois.
static func _build_occluders(boxes: Array[Dictionary], root: Node3D) -> void:
	var threshold: float = Params.CITY_BLOCK_MIN * Params.CITY_FLOOR_HEIGHT
	for index: int in boxes.size():
		var box: Dictionary = boxes[index]
		var size: Vector3 = box["size"]
		if size.x * size.y < threshold:
			continue
		var shape: BoxOccluder3D = BoxOccluder3D.new()
		shape.size = size
		var node: OccluderInstance3D = OccluderInstance3D.new()
		node.name = "Occluder_%d" % index
		node.occluder = shape
		node.transform = Transform3D(Basis(Vector3.UP, float(box["yaw"])), box["center"])
		root.add_child(node)
