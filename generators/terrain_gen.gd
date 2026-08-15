@tool
## O vale, de uma seed só: ruído em camadas, erosão, planície da cidade e malha colorida.
##
## Três camadas somam o relevo, e cada uma existe por um motivo:
##
## 1. **Base fractal** — as montanhas. Sozinha, dá aquele terreno ondulado uniforme que
##    todo mundo reconhece como "ruído": bonito em qualquer lugar e memorável em nenhum.
## 2. **Potência de vale** — eleva a altura normalizada a um expoente maior que 1. Isso
##    afunda os fundos e rarefaz os picos, que é a diferença entre um vale e um mar de
##    colinas. É um número só e muda o caráter do mundo inteiro.
## 3. **Erosão térmica** — material acima do ângulo de talude escorrega para o vizinho
##    mais baixo. Não é hidráulica, não move sedimento e não cava rios; corta as encostas
##    impossíveis do ruído cru e dá aos fundos o piso plano onde estrada e cidade cabem.
##
## Sobre isso vem a **planície da cidade**: um disco puxado para a mesma cota, com
## transição suave. A fase 8 vai construir ali, e uma cidade sobre relevo fractal seria
## um exercício de terraplenagem em vez de urbanismo.
##
## A malha sai em pedaços de `TERRAIN_CHUNK_CELLS`, cada um com a sua colisão trimesh.
## Um pedaço só cobriria o vale com um draw call e nenhuma oclusão; um por célula daria
## 16 mil. O tamanho do pedaço é o botão que troca draw calls por granularidade de culling.
##
## `@tool` para poder rodar no editor: o terreno é a única coisa do projeto que alguém vai
## querer ver mudando enquanto mexe num parâmetro.
class_name TerrainGenerator
extends RefCounted

const TERRAIN_MATERIAL: StringName = &"terrain"
const CHUNK_CATEGORY: StringName = &"terrain_chunk"
const CHUNK_PREFIX: String = "TerrainChunk"
## Quatro vizinhos por célula na erosão. Oito seria mais suave e duas vezes mais lento,
## e o ganho some no shading flat.
const NEIGHBOURS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
]
## Primos usados para derivar sementes independentes de uma só. Sem isso, base e detalhe
## andariam em fase e o detalhe reforçaria a base em vez de quebrá-la.
const SEED_DETAIL_OFFSET: int = 7919
const SEED_TINT_OFFSET: int = 104729
const SEED_PLAIN_OFFSET: int = 15485863
## Vértices de um triângulo — o divisor do centroide.
const TRIANGLE_VERTS: float = 3.0
## Piso de divisão, para uma inclinação-limite zerada em params.py não estourar.
const MIN_DIVISOR: float = 0.001
## Máscara de 16 bits usada para transformar o hash de posição em fração.
const HASH_MASK: int = 0xFFFF


## Constrói o campo de altura inteiro. Só dados: nenhum nó, nenhuma malha.
static func build_field(world_seed: int) -> HeightField:
	var cells: int = int(round(Params.TERRAIN_SIZE / Params.TERRAIN_CELL))
	var field: HeightField = HeightField.new(cells, Params.TERRAIN_CELL)

	field.plain_center = plain_center(world_seed)
	_apply_noise(field, world_seed)
	_apply_plain(field)
	_erode(field)
	field.refresh_bounds()
	return field


## Onde a planície da cidade fica, para esta seed.
##
## Deslizar a praça com a seed faz duas coisas de uma vez: tira a simetria que entrega o
## mundo como procedural, e desiguala a parte do mapa que antes era idêntica entre
## seeds — a planície e a transição em volta dela somam quase metade do lado do vale.
static func plain_center(world_seed: int) -> Vector2:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = world_seed + SEED_PLAIN_OFFSET
	var angle: float = rng.randf_range(0.0, TAU)
	var reach: float = rng.randf_range(0.0, Params.TERRAIN_PLAIN_WANDER)
	return Params.TERRAIN_PLAIN_CENTER + Vector2(cos(angle), sin(angle)) * reach


## Camada 1 e 2: fractal base, detalhe e a potência que faz o vale ser um vale.
static func _apply_noise(field: HeightField, world_seed: int) -> void:
	var base: FastNoiseLite = FastNoiseLite.new()
	base.seed = world_seed
	base.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	base.frequency = Params.TERRAIN_BASE_FREQUENCY
	base.fractal_type = FastNoiseLite.FRACTAL_FBM
	base.fractal_octaves = Params.TERRAIN_BASE_OCTAVES
	base.fractal_lacunarity = Params.TERRAIN_BASE_LACUNARITY
	base.fractal_gain = Params.TERRAIN_BASE_GAIN

	var detail: FastNoiseLite = FastNoiseLite.new()
	detail.seed = world_seed + SEED_DETAIL_OFFSET
	detail.noise_type = FastNoiseLite.TYPE_SIMPLEX
	detail.frequency = Params.TERRAIN_DETAIL_FREQUENCY
	detail.fractal_type = FastNoiseLite.FRACTAL_FBM
	detail.fractal_octaves = Params.TERRAIN_DETAIL_OCTAVES

	var cells: int = field.cells()
	var half: float = field.size() * 0.5
	for iz: int in cells + 1:
		for ix: int in cells + 1:
			var x: float = -half + float(ix) * field.cell_size()
			var z: float = -half + float(iz) * field.cell_size()

			# FastNoiseLite devolve -1..1; o relevo quer 0..1.
			var shaped: float = (base.get_noise_2d(x, z) + 1.0) * 0.5
			shaped = pow(shaped, Params.TERRAIN_VALLEY_POWER)
			var grain: float = (detail.get_noise_2d(x, z) + 1.0) * 0.5
			shaped = lerpf(shaped, grain, Params.TERRAIN_DETAIL_WEIGHT)
			shaped += _rim(x, z, half)
			field.set_at_index(ix, iz, shaped * Params.TERRAIN_HEIGHT)


## Subida das bordas. Fecha o vale sem cortar o mundo num penhasco reto, e o que se vê do
## fundo é montanha em volta em vez do vazio depois do último polígono.
static func _rim(x: float, z: float, half: float) -> float:
	var reach: float = maxf(absf(x), absf(z)) / half
	if reach <= Params.TERRAIN_RIM_START:
		return 0.0
	var climb: float = (reach - Params.TERRAIN_RIM_START) / (1.0 - Params.TERRAIN_RIM_START)
	return smoothstep(0.0, 1.0, climb) * Params.TERRAIN_RIM_HEIGHT


## A planície onde a cidade nasce. Puxa o disco para a altura média dele próprio, para a
## cidade herdar a cota do vale em vez de aparecer numa mesa arbitrária.
static func _apply_plain(field: HeightField) -> void:
	var center: Vector2 = field.plain_center
	var target: float = _average_height(field, center, Params.TERRAIN_PLAIN_RADIUS)
	var outer: float = Params.TERRAIN_PLAIN_RADIUS + Params.TERRAIN_PLAIN_FALLOFF

	var cells: int = field.cells()
	var half: float = field.size() * 0.5
	for iz: int in cells + 1:
		for ix: int in cells + 1:
			var x: float = -half + float(ix) * field.cell_size()
			var z: float = -half + float(iz) * field.cell_size()
			var distance: float = Vector2(x, z).distance_to(center)
			if distance >= outer:
				continue
			var pull: float = 1.0 - smoothstep(Params.TERRAIN_PLAIN_RADIUS, outer, distance)
			pull *= Params.TERRAIN_PLAIN_FLATNESS
			field.set_at_index(ix, iz, lerpf(field.at_index(ix, iz), target, pull))


static func _average_height(field: HeightField, center: Vector2, radius: float) -> float:
	var total: float = 0.0
	var count: int = 0
	var cells: int = field.cells()
	var half: float = field.size() * 0.5
	for iz: int in cells + 1:
		for ix: int in cells + 1:
			var x: float = -half + float(ix) * field.cell_size()
			var z: float = -half + float(iz) * field.cell_size()
			if Vector2(x, z).distance_to(center) <= radius:
				total += field.at_index(ix, iz)
				count += 1
	if count == 0:
		return 0.0
	return total / float(count)


## Erosão térmica: o que passa do ângulo de talude escorrega.
##
## O ruído fractal produz encostas que nenhuma montanha real sustenta — e, pior para um
## jogo, que nenhum personagem sobe. Cada passe move uma fração do excesso para o vizinho
## mais baixo, e o efeito acumulado é encosta com pé de talude e fundo de vale plano.
static func _erode(field: HeightField) -> void:
	var cells: int = field.cells()
	for _pass: int in Params.TERRAIN_EROSION_PASSES:
		for iz: int in cells + 1:
			for ix: int in cells + 1:
				var here: float = field.at_index(ix, iz)
				var lowest: float = here
				var target_x: int = ix
				var target_z: int = iz
				for step: Vector2i in NEIGHBOURS:
					var nx: int = ix + step.x
					var nz: int = iz + step.y
					if nx < 0 or nz < 0 or nx > cells or nz > cells:
						continue
					var neighbour: float = field.at_index(nx, nz)
					if neighbour < lowest:
						lowest = neighbour
						target_x = nx
						target_z = nz

				var drop: float = here - lowest
				if drop <= Params.TERRAIN_TALUS:
					continue
				var moved: float = (drop - Params.TERRAIN_TALUS) * Params.TERRAIN_EROSION_RATE
				field.set_at_index(ix, iz, here - moved)
				field.set_at_index(target_x, target_z, lowest + moved)


# --- Malha --------------------------------------------------------------------


## Constrói os pedaços de malha sob `parent` e devolve quantos foram criados.
##
## Cada pedaço é um `StaticBody3D` com malha visível e colisão trimesh. Trimesh, e não
## heightmap: a `HeightMapShape3D` do Godot seria mais barata, mas exigiria um corpo por
## vale inteiro e perderia a granularidade de culling que os pedaços dão à parte visual.
static func build_chunks(field: HeightField, parent: Node3D) -> int:
	var per_side: int = int(ceil(float(field.cells()) / float(Params.TERRAIN_CHUNK_CELLS)))
	var material: StandardMaterial3D = MaterialLibrary.get_material(TERRAIN_MATERIAL)
	var created: int = 0

	for chunk_z: int in per_side:
		for chunk_x: int in per_side:
			var chunk: StaticBody3D = _build_chunk(field, chunk_x, chunk_z, material)
			if chunk == null:
				continue
			parent.add_child(chunk)
			chunk.add_to_group(Params.NAV_GROUP)
			created += 1
	return created


static func _build_chunk(
	field: HeightField, chunk_x: int, chunk_z: int, material: StandardMaterial3D
) -> StaticBody3D:
	var span: int = Params.TERRAIN_CHUNK_CELLS
	var start_x: int = chunk_x * span
	var start_z: int = chunk_z * span
	var end_x: int = mini(start_x + span, field.cells())
	var end_z: int = mini(start_z + span, field.cells())
	if start_x >= end_x or start_z >= end_z:
		return null

	var builder: MeshBuilder = MeshBuilder.new()
	for iz: int in range(start_z, end_z):
		for ix: int in range(start_x, end_x):
			_emit_cell(builder, field, ix, iz)

	var mesh: ArrayMesh = builder.commit(CHUNK_CATEGORY)
	if mesh == null:
		return null

	var body: StaticBody3D = StaticBody3D.new()
	body.name = "%s_%d_%d" % [CHUNK_PREFIX, chunk_x, chunk_z]
	body.collision_layer = Params.LAYER_WORLD
	body.collision_mask = 0

	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.name = "Mesh"
	visual.mesh = mesh
	visual.material_override = material
	body.add_child(visual)

	var shape: ConcavePolygonShape3D = ConcavePolygonShape3D.new()
	shape.set_faces(mesh.get_faces())
	var collider: CollisionShape3D = CollisionShape3D.new()
	collider.name = "Collision"
	collider.shape = shape
	body.add_child(collider)
	return body


## Uma célula, dois triângulos. A diagonal alterna em xadrez: fixa, ela desenha um
## grão diagonal visível no vale inteiro assim que a luz bate de raspão.
static func _emit_cell(builder: MeshBuilder, field: HeightField, ix: int, iz: int) -> void:
	var a: Vector3 = field.vertex(ix, iz)
	var b: Vector3 = field.vertex(ix + 1, iz)
	var c: Vector3 = field.vertex(ix + 1, iz + 1)
	var d: Vector3 = field.vertex(ix, iz + 1)

	if (ix + iz) % 2 == 0:
		builder.add_triangle(a, d, c, _face_color(field, a, d, c, ix, iz))
		builder.add_triangle(a, c, b, _face_color(field, a, c, b, ix, iz))
	else:
		builder.add_triangle(a, d, b, _face_color(field, a, d, b, ix, iz))
		builder.add_triangle(b, d, c, _face_color(field, b, d, c, ix, iz))


## Cor de um triângulo: grama, terra ou rocha, por altitude e inclinação — e terra batida
## onde a estrada passa.
##
## O declive manda mais que a altura. Encosta íngreme é rocha em qualquer cota, porque é
## onde a terra não se segura; e um platô alto continua sendo grama, que é o que se vê nas
## montanhas de verdade.
static func _face_color(
	field: HeightField, a: Vector3, b: Vector3, c: Vector3, ix: int, iz: int
) -> Color:
	var center: Vector3 = (a + b + c) / TRIANGLE_VERTS
	var normal: Vector3 = (b - a).cross(c - a).normalized()
	var slope: float = clampf(1.0 - absf(normal.y), 0.0, 1.0)
	var altitude: float = 0.0
	if field.span() > 0.0:
		altitude = clampf((center.y - field.lowest()) / field.span(), 0.0, 1.0)

	var color: Color = Params.color(&"grass")
	var dirt_mix: float = clampf(slope / maxf(Params.TERRAIN_SLOPE_DIRT, MIN_DIVISOR), 0.0, 1.0)
	color = color.lerp(Params.color(&"earth"), dirt_mix)

	var rock_by_slope: float = smoothstep(
		Params.TERRAIN_SLOPE_DIRT, Params.TERRAIN_SLOPE_ROCK, slope
	)
	var rock_by_altitude: float = smoothstep(
		Params.TERRAIN_ALTITUDE_GRASS, Params.TERRAIN_ALTITUDE_ROCK, altitude
	)
	color = color.lerp(Params.color(&"stone"), maxf(rock_by_slope, rock_by_altitude))

	# Terra batida: o leito recebe a cor cheia, o acostamento dissolve nela.
	var distance: float = field.road_distance(center.x, center.z)
	if distance < Params.ROAD_WIDTH * 0.5 + Params.ROAD_SHOULDER:
		var packed: float = 1.0 - smoothstep(
			Params.ROAD_WIDTH * 0.5, Params.ROAD_WIDTH * 0.5 + Params.ROAD_SHOULDER, distance
		)
		color = color.lerp(Params.color(&"earth_dark"), packed)

	return _jitter(color, ix, iz)


## Variação de tom por triângulo, determinística. Sem ela a malha fica chapada em áreas
## grandes de mesma inclinação, e o vale parece pintado com rolo.
static func _jitter(color: Color, ix: int, iz: int) -> Color:
	var hash_value: int = (ix * SEED_TINT_OFFSET) ^ (iz * SEED_DETAIL_OFFSET)
	var normalized: float = float(hash_value & HASH_MASK) / float(HASH_MASK)
	var shift: float = (normalized - 0.5) * 2.0 * Params.TERRAIN_TONE_JITTER
	if shift >= 0.0:
		return color.lightened(shift)
	return color.darkened(-shift)
