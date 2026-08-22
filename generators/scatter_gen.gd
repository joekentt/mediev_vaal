@tool
## Vegetação e rochas: determinístico, em `MultiMeshInstance3D`, com três faixas de LOD.
##
## **Determinístico** quer dizer que a mesma seed põe a mesma árvore no mesmo lugar, e que
## cada tipo tem a sua própria sequência de números. A segunda parte não é detalhe: com
## um gerador só, acrescentar arbustos deslocaria todas as árvores, e um mundo "estável"
## mudaria inteiro a cada ajuste de densidade.
##
## **Por bloco, e não por vale.** As faixas de LOD do Godot (`visibility_range_*`) medem a
## distância até a *origem do nó*, não até cada instância. Um `MultiMesh` cobrindo os
## 512 m teria uma origem só e uma distância só — LOD nenhuma. Daí os blocos de
## `SCATTER_TILE`: cada um tem origem própria, e é ela que entra e sai das faixas.
##
## **O que muda entre as faixas** são duas coisas ao mesmo tempo: a malha, que vira um
## prisma de oito triângulos, e a densidade, que cai. A terceira faixa larga os tipos
## rasteiros de vez — um tufo de grama a 300 m é meio pixel que custa um draw call.
##
## O orçamento fecha assim: por bloco visível, um draw call por tipo presente na faixa em
## que o bloco está. Faixa perto tem cinco tipos e poucos blocos; faixa longe tem dois
## tipos e muitos blocos.
class_name ScatterGenerator
extends RefCounted

const SEED_OFFSET: int = 613
const HECTARE: float = 10000.0  # m² — a densidade é dada por hectare
const PROXY_CATEGORY: StringName = &"prop"
## Vértices de um triângulo — o passo do índice ao varrer uma malha.
const VERTS_PER_TRIANGLE: int = 3
const FOLIAGE_MATERIAL: StringName = &"foliage"
## Material dos proxies de LOD — um só, para todos os tipos. Ver `_build_band`.
const PROXY_MATERIAL: StringName = Params.KIT_MATERIAL

## Prisma unitário por faixa, construído uma vez. São duas malhas de oito triângulos para o
## vale inteiro: reconstruí-las por bloco daria 32 malhas idênticas e nenhum agrupamento.
static var _prisms: Dictionary = {}

## Disco onde nada é plantado, escrito por `scatter` e lido por `_sample_type`.
static var _keep_out_center: Vector2 = Vector2.ZERO
static var _keep_out_radius: float = -1.0


## Espalha tudo sob `parent`. Devolve estatística para o relatório e para o bench.
##
## `keep_out_center`/`keep_out_radius` recortam um disco onde nada é plantado — é como a
## cidade some do espalhamento sem que o espalhamento saiba o que é uma cidade. Raio zero
## ou negativo desliga o recorte, que é o caso do vale sozinho.
static func scatter(
	field: HeightField,
	parent: Node3D,
	world_seed: int,
	keep_out_center: Vector2 = Vector2.ZERO,
	keep_out_radius: float = -1.0
) -> Dictionary:
	_keep_out_center = keep_out_center
	_keep_out_radius = keep_out_radius
	var tiles: int = maxi(int(ceil(field.size() / Params.SCATTER_TILE)), 1)
	var meshes: Dictionary = _load_meshes()
	var placed: int = 0
	var nodes: int = 0

	for tile_z: int in tiles:
		for tile_x: int in tiles:
			var origin: Vector2 = Vector2(
				-field.size() * 0.5 + (float(tile_x) + 0.5) * Params.SCATTER_TILE,
				-field.size() * 0.5 + (float(tile_z) + 0.5) * Params.SCATTER_TILE
			)
			var result: Dictionary = _build_tile(
				field, parent, meshes, origin, world_seed, tile_x, tile_z
			)
			placed += int(result["instances"])
			nodes += int(result["nodes"])

	return {"instances": placed, "nodes": nodes, "tiles": tiles * tiles}


## Malha de cada tipo, tirada do `.glb` do kit uma vez só.
static func _load_meshes() -> Dictionary:
	var meshes: Dictionary = {}
	for spec: Dictionary in Params.SCATTER_TYPES:
		var part: StringName = spec["part"]
		var path: String = "%s/%s.glb" % [Params.KIT_DIR, part]
		var packed: PackedScene = ResourceLoader.load(path) as PackedScene
		if packed == null:
			push_warning("Peça de vegetação ausente: %s. Rode `make assets`." % path)
			continue
		var instance: Node3D = packed.instantiate() as Node3D
		var mesh: Mesh = _find_mesh(instance)
		if mesh != null:
			meshes[part] = mesh
		instance.queue_free()
	return meshes


static func _find_mesh(node: Node) -> Mesh:
	if node is MeshInstance3D:
		return (node as MeshInstance3D).mesh
	for child: Node in node.get_children():
		var found: Mesh = _find_mesh(child)
		if found != null:
			return found
	return null


## Um bloco: sorteia as posições uma vez e reparte entre as faixas de LOD.
##
## Sortear uma vez e repartir, em vez de sortear por faixa, é o que faz a árvore não
## trocar de lugar quando a câmera se aproxima. Cada faixa fica com um prefixo da mesma
## lista, então a de perto contém todas as de longe.
static func _build_tile(
	field: HeightField,
	parent: Node3D,
	meshes: Dictionary,
	origin: Vector2,
	world_seed: int,
	tile_x: int,
	tile_z: int
) -> Dictionary:
	var placed: int = 0
	var nodes: int = 0
	var anchor: Vector3 = Vector3(origin.x, field.height_at(origin.x, origin.y), origin.y)

	# As faixas de proxy juntam **todos os tipos** num nó só por faixa. Ver `_build_proxy`.
	var proxy_spots: Array[Array] = []
	var proxy_colors: Array[PackedColorArray] = []
	for _band: int in Params.SCATTER_LOD_BANDS.size():
		proxy_spots.append([])
		proxy_colors.append(PackedColorArray())

	for index: int in Params.SCATTER_TYPES.size():
		var spec: Dictionary = Params.SCATTER_TYPES[index]
		var part: StringName = spec["part"]
		if not meshes.has(part):
			continue

		var spots: Array[Transform3D] = _sample_type(
			field, spec, origin, world_seed, index, tile_x, tile_z
		)
		if spots.is_empty():
			continue
		placed += spots.size()

		var source: Mesh = meshes[part]
		var local: Transform3D = _proxy_local(source)
		var tint: Color = _dominant_color(source)
		var last_band: int = Params.SCATTER_LOD_BANDS.size() - 1

		for band: int in Params.SCATTER_LOD_BANDS.size():
			# A faixa mais distante só recebe os tipos altos. Tufo de grama a 300 m é meio
			# pixel que custaria um draw call por bloco.
			if band == last_band and not bool(spec["far"]):
				continue
			var kept: int = int(round(float(spots.size()) * Params.SCATTER_LOD_THINNING[band]))
			if kept <= 0:
				continue

			if Params.SCATTER_PROXY_SIDES[band] <= 0:
				var node: MultiMeshInstance3D = _build_band(
					source, spots, kept, band, part, tile_x, tile_z
				)
				node.position = anchor
				parent.add_child(node)
				nodes += 1
				continue

			for spot: int in kept:
				proxy_spots[band].append(spots[spot] * local)
				proxy_colors[band].append(tint)

	for band: int in Params.SCATTER_LOD_BANDS.size():
		if proxy_spots[band].is_empty():
			continue
		var node: MultiMeshInstance3D = _build_proxy(
			proxy_spots[band], proxy_colors[band], band, tile_x, tile_z
		)
		node.position = anchor
		parent.add_child(node)
		nodes += 1

	return {"instances": placed, "nodes": nodes}


## Um `MultiMeshInstance3D` para a faixa de perto: a peça de verdade, um nó por tipo.
static func _build_band(
	source: Mesh,
	spots: Array[Transform3D],
	kept: int,
	band: int,
	part: StringName,
	tile_x: int,
	tile_z: int
) -> MultiMeshInstance3D:
	var multi: MultiMesh = MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = false
	multi.mesh = source
	multi.instance_count = kept

	# As instâncias vão em espaço local do bloco: o nó é que carrega a posição, e é a
	# posição dele que as faixas de LOD medem.
	for index: int in kept:
		multi.set_instance_transform(index, spots[index])

	var node: MultiMeshInstance3D = MultiMeshInstance3D.new()
	node.name = "%s_%d_%d_lod%d" % [part, tile_x, tile_z, band]
	node.multimesh = multi
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# Mesmo material do resto do kit: a peça vem do seu próprio `.glb` com uma cópia
	# idêntica dentro, e cópia idêntica é troca de estado paga por nada.
	node.material_override = MaterialLibrary.get_material(PROXY_MATERIAL)
	_apply_range(node, band)
	return node


## Um `MultiMeshInstance3D` para uma faixa de proxy — **um por faixa, não por tipo**.
##
## A partir da segunda faixa toda peça vira o mesmo prisma unitário, esticado pela caixa
## envolvente do tipo e tingido pela cor média dele. Como a malha passa a ser uma só, os
## cinco tipos cabem num `MultiMesh` só: a diferença entre uma árvore e uma pedra a 200 m
## é escala e cor, e as duas viajam na instância.
##
## É isto que fecha o orçamento. Um nó por tipo *e* por faixa dava 202 nós de espalhamento
## e 216 draw calls medidos, contra um teto de 140 — e a maior parte deles desenhava oito
## triângulos. Juntando as faixas de proxy, o bloco sai de até 13 nós para até 7.
static func _build_proxy(
	spots: Array, tints: PackedColorArray, band: int, tile_x: int, tile_z: int
) -> MultiMeshInstance3D:
	var multi: MultiMesh = MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.mesh = _unit_prism(band)
	multi.instance_count = spots.size()
	for index: int in spots.size():
		multi.set_instance_transform(index, spots[index])
		multi.set_instance_color(index, tints[index])

	var node: MultiMeshInstance3D = MultiMeshInstance3D.new()
	node.name = "proxy_%d_%d_lod%d" % [tile_x, tile_z, band]
	node.multimesh = multi
	# O prisma sai do `MeshBuilder` sem material, e uma malha sem material herda o branco
	# padrão do Godot — que ignora a cor da instância. A cor média de cada peça
	# simplesmente não aparecia, e além de 92 m o vale inteiro virava um campo de cones
	# claros. Um material só para todos os proxies também é o que impede o LOD de
	# multiplicar materiais visíveis.
	node.material_override = MaterialLibrary.get_material(PROXY_MATERIAL)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_apply_range(node, band)
	return node


## Faixa de visibilidade com fade, medida da origem do nó — ou seja, do centro do bloco.
static func _apply_range(node: MultiMeshInstance3D, band: int) -> void:
	var begin: float = 0.0 if band == 0 else Params.SCATTER_LOD_BANDS[band - 1]
	node.visibility_range_begin = maxf(begin - Params.SCATTER_LOD_FADE, 0.0)
	node.visibility_range_begin_margin = Params.SCATTER_LOD_FADE if band > 0 else 0.0
	node.visibility_range_end = Params.SCATTER_LOD_BANDS[band]
	node.visibility_range_end_margin = Params.SCATTER_LOD_FADE
	node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


## O prisma de uma faixa, em tamanho unitário: raio 0,5 e altura 1, apoiado em y = 0.
##
## Unitário para caber qualquer peça: quem dá dimensão é a instância, por `_proxy_local`.
## É grosseiro de propósito — a 200 m o que resta de uma árvore low poly é a silhueta e a
## cor, e as duas cabem em oito triângulos.
static func _unit_prism(band: int) -> Mesh:
	if _prisms.has(band):
		return _prisms[band]

	var sides: int = maxi(Params.SCATTER_PROXY_SIDES[band], VERTS_PER_TRIANGLE)
	var builder: MeshBuilder = MeshBuilder.new()
	var radius: float = 0.5
	var taper: float = radius * Params.SCATTER_PROXY_TAPER
	var center: Vector2 = Vector2.ZERO
	# Branco: a cor de verdade chega por instância, e o branco deixa passar. Ver
	# `_build_proxy`.
	var color: Color = Color.WHITE

	for index: int in sides:
		var a0: float = TAU * float(index) / float(sides)
		var a1: float = TAU * float(index + 1) / float(sides)
		var low_a: Vector3 = _ring_point(center, radius, a0, 0.0)
		var low_b: Vector3 = _ring_point(center, radius, a1, 0.0)
		var high_a: Vector3 = _ring_point(center, taper, a0, 1.0)
		var high_b: Vector3 = _ring_point(center, taper, a1, 1.0)
		# Winding para fora. O `MeshBuilder` tira a normal de `(v1-v0)×(v2-v0)`, e um anel
		# percorrido no sentido do ângulo crescente dá a normal *para dentro* — o prisma
		# nascia virado do avesso. Não aparecia como buraco: as peças do kit vêm do Blender
		# com o material de dupla face, o proxy usa o material do projeto, que corta a face
		# de trás, e o que se via era a parede interna do cone, iluminada só de raspão.
		# O vale ficava salpicado de cones claros e lavados onde deviam estar árvores.
		builder.add_triangle(low_a, high_b, low_b, color)
		builder.add_triangle(low_a, high_a, high_b, color)

	_prisms[band] = builder.commit(PROXY_CATEGORY)
	return _prisms[band]


## Transformação que veste o prisma unitário com a caixa envolvente de uma peça.
##
## Largura vira o maior lado horizontal — um proxy é uma silhueta vista de qualquer ângulo,
## e a maior dimensão é a que o olho usa para julgar o tamanho.
static func _proxy_local(source: Mesh) -> Transform3D:
	var bounds: AABB = source.get_aabb()
	var width: float = maxf(bounds.size.x, bounds.size.z)
	var basis: Basis = Basis.IDENTITY.scaled(Vector3(width, bounds.size.y, width))
	var offset: Vector3 = Vector3(
		bounds.position.x + bounds.size.x * 0.5,
		bounds.position.y,
		bounds.position.z + bounds.size.z * 0.5
	)
	return Transform3D(basis, offset)


static func _ring_point(center: Vector2, radius: float, angle: float, y: float) -> Vector3:
	return Vector3(center.x + cos(angle) * radius, y, center.y + sin(angle) * radius)


## Cor da peça vista de longe: média do vertex color **ponderada pela área do triângulo**.
##
## A ponderação não é preciosismo. Uma conífera do kit tem o tronco em muitos vértices
## pequenos e a copa em poucos vértices grandes; a média simples dava o mesmo peso aos dois
## e a árvore distante saía parda, quando o que se vê a 200 m é a massa da copa. Área é
## exatamente "quanto daquela cor chega ao olho".
static func _dominant_color(source: Mesh) -> Color:
	if source.get_surface_count() == 0:
		return Params.color(&"foliage")
	var arrays: Array = source.surface_get_arrays(0)
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if colors.is_empty() or vertices.size() != colors.size():
		return Params.color(&"foliage")

	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if indices.is_empty():
		indices = PackedInt32Array()
		for index: int in vertices.size():
			indices.append(index)

	var total: Color = Color(0.0, 0.0, 0.0, 1.0)
	var weight: float = 0.0
	# A divisão inteira é o que se quer: uma lista de índices bem-formada é múltipla de três,
	# e um resto seria uma malha quebrada, não um triângulo a mais.
	@warning_ignore("integer_division")
	for triangle: int in indices.size() / VERTS_PER_TRIANGLE:
		var base: int = triangle * VERTS_PER_TRIANGLE
		var a: int = indices[base]
		var b: int = indices[base + 1]
		var c: int = indices[base + 2]
		var area: float = (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a]).length() * 0.5
		if area <= 0.0:
			continue
		var face: Color = (colors[a] + colors[b] + colors[c]) / float(VERTS_PER_TRIANGLE)
		total += face * area
		weight += area

	if weight <= 0.0:
		return Params.color(&"foliage")
	return Color(total.r / weight, total.g / weight, total.b / weight, 1.0)


## Posições de um tipo dentro de um bloco, já filtradas por relevo e estrada.
##
## A grade com deslocamento aleatório (jitter) substitui um Poisson de verdade: custa uma
## fração e não deixa aglomerado nem fileira visível, que é tudo o que se pede de um campo
## visto de longe.
static func _sample_type(
	field: HeightField,
	spec: Dictionary,
	origin: Vector2,
	world_seed: int,
	type_index: int,
	tile_x: int,
	tile_z: int
) -> Array[Transform3D]:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	# Semente por tipo **e** por bloco: acrescentar um tipo não mexe nos outros, e um
	# bloco gerado sozinho sai igual ao mesmo bloco gerado com o vale inteiro.
	rng.seed = (
		world_seed
		+ SEED_OFFSET * (type_index + 1)
		+ tile_x * Params.TERRAIN_CHUNK_CELLS
		+ tile_z * Params.ROAD_SAMPLES
	)

	var area_ha: float = (Params.SCATTER_TILE * Params.SCATTER_TILE) / HECTARE
	var wanted: int = int(round(float(spec["density"]) * area_ha))
	if wanted <= 0:
		return []

	var per_side: int = maxi(int(ceil(sqrt(float(wanted)))), 1)
	var step: float = Params.SCATTER_TILE / float(per_side)
	var half_tile: float = Params.SCATTER_TILE * 0.5
	var clearance: float = (
		Params.ROAD_WIDTH * 0.5 + Params.ROAD_SHOULDER + Params.SCATTER_ROAD_CLEARANCE
	)
	var altitude: Vector2 = spec["altitude"]
	var scale_range: Vector2 = spec["scale"]
	var spots: Array[Transform3D] = []

	for row: int in per_side:
		for column: int in per_side:
			var jitter: float = step * Params.SCATTER_JITTER
			var x: float = (
				origin.x - half_tile + (float(column) + 0.5) * step
				+ rng.randf_range(-jitter, jitter)
			)
			var z: float = (
				origin.y - half_tile + (float(row) + 0.5) * step
				+ rng.randf_range(-jitter, jitter)
			)
			if absf(x) > field.size() * 0.5 or absf(z) > field.size() * 0.5:
				continue
			if field.road_distance(x, z) < clearance:
				continue
			if (
				_keep_out_radius > 0.0
				and Vector2(x, z).distance_to(_keep_out_center) < _keep_out_radius
			):
				continue
			if field.slope_at(x, z) > float(spec["max_slope"]):
				continue
			var height_fraction: float = field.altitude_at(x, z)
			if height_fraction < altitude.x or height_fraction > altitude.y:
				continue

			var scale: float = rng.randf_range(scale_range.x, scale_range.y)
			var basis: Basis = Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(
				Vector3(scale, scale, scale)
			)
			# Local ao bloco: o nó carrega a origem, e é a origem que a LOD mede.
			var local: Vector3 = Vector3(
				x - origin.x, field.height_at(x, z) - field.height_at(origin.x, origin.y),
				z - origin.y
			)
			spots.append(Transform3D(basis, local))

	# Embaralho com o **mesmo** gerador semeado, e não `Array.shuffle()`: aquele usa o RNG
	# global do Godot, que não é semeado por nós. A ordem decide quais instâncias sobrevivem
	# ao afinamento de LOD, então um embaralho global tornaria as faixas distantes
	# diferentes a cada execução — determinismo perdido no último passo.
	for index: int in range(spots.size() - 1, 0, -1):
		var swap: int = rng.randi_range(0, index)
		var keep: Transform3D = spots[index]
		spots[index] = spots[swap]
		spots[swap] = keep
	return spots
