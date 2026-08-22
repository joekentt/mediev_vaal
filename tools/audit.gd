## Onde estão os draw calls: a composição da cena em cada estação do bench.
##
##     godot --headless --script res://tools/audit.gd
##
## O bench diz **quanto** custa; este diz **de quê**. Sem essa tabela, otimizar é escolher
## por intuição — e a intuição deste projeto já errou duas vezes com convicção: uma
## procurando geometria quando o custo era cascata de sombra, outra procurando o traçado da
## cidade quando o custo era um `Label3D` sem alcance.
##
## Roda **sem renderizador**, e isso é possível porque a pergunta é geométrica: quantos nós
## de desenho o renderizador receberia deste ponto de vista. O tronco de visão da câmera e
## a caixa envolvente de cada nó bastam — o número não é o do contador do driver, é o de
## quantos objetos entram na conta, que é o que se otimiza.
##
## Cada nó é creditado ao ramo do estágio a que pertence (cidade, terreno, vegetação,
## habitantes, ambiente), porque é assim que se decide o que mexer: o ramo é o gerador.
extends SceneTree

const RESULT_PREFIX: String = "MEDIEV_AUDIT "
const BAKE_TIMEOUT_FRAMES: int = 2400
const MIN_LOOK_DISTANCE: float = 0.01
## Altura de amostragem do corpo de um habitante, para o teste de tronco de visão.
const BODY_RISE: float = 1.0

var _stage: Node3D = null
var _camera: Camera3D = null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var holder: Node3D = Node3D.new()
	root.add_child(holder)
	_stage = WorldGenerator.build_stage(holder, false)
	WorldGenerator.pin_sky(_stage, Params.SHOT_HOUR)

	_camera = Camera3D.new()
	_camera.fov = Params.STAGE_CAMERA_FOV
	_camera.far = Params.STAGE_CAMERA_FAR
	root.add_child(_camera)
	_camera.make_current()

	await _wait_for_bake(_find_region(_stage))

	var layout: CityLayout = WorldGenerator.last_city
	var stations: Array[Dictionary] = []
	for station: Array in Params.BENCH_STATIONS:
		if bool(station[BenchStations.CROWD]):
			_crowd(layout)
		_aim(station, layout)
		await process_frame
		stations.append(_compose(String(station[BenchStations.NAME])))

	print(RESULT_PREFIX + JSON.stringify({
		"stations": stations,
		"materials": _material_census(),
	}))
	quit(0)


## Índices dos campos de `BENCH_STATIONS`. Espelham `tools/bench.gd`; ficam num bloco com
## nome para as duas leituras da mesma tabela não divergirem em silêncio.
class BenchStations:
	const NAME: int = 0
	const MARKER: int = 1
	const DISTANCE: int = 2
	const HEIGHT: int = 3
	const PITCH: int = 4
	const TURN: int = 5
	const CROWD: int = 6


# --- Composição ---------------------------------------------------------------


## Quantos nós de desenho cada ramo do estágio põe neste enquadramento.
func _compose(name: String) -> Dictionary:
	var branches: Dictionary = {}
	var instances: int = 0
	var triangles: int = 0
	for child: Node in _stage.get_children():
		var count: Dictionary = _count_branch(child, child.name)
		if int(count["nodes"]) == 0:
			continue
		branches[String(child.name)] = count
		instances += int(count["instances"])
		triangles += int(count["triangles"])

	var total: int = 0
	for key: String in branches:
		total += int(branches[key]["nodes"])
	return {
		"name": name,
		"nodes": total,
		"instances": instances,
		"triangles": triangles,
		"branches": branches,
	}


func _count_branch(node: Node, _branch: String) -> Dictionary:
	var nodes: int = 0
	var instances: int = 0
	var triangles: int = 0
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		for child: Node in current.get_children():
			stack.append(child)
		var geometry: GeometryInstance3D = current as GeometryInstance3D
		if geometry == null or not geometry.is_visible_in_tree():
			continue
		if not _in_view(geometry):
			continue
		nodes += 1
		var multi: MultiMeshInstance3D = geometry as MultiMeshInstance3D
		if multi != null and multi.multimesh != null:
			var shown: int = _shown_instances(multi.multimesh)
			instances += shown
			triangles += _mesh_triangles(multi.multimesh.mesh) * shown
			continue
		var mesh_node: MeshInstance3D = geometry as MeshInstance3D
		if mesh_node != null:
			instances += 1
			triangles += _mesh_triangles(mesh_node.mesh)
	return {"nodes": nodes, "instances": instances, "triangles": triangles}


static func _shown_instances(multi: MultiMesh) -> int:
	return multi.instance_count if multi.visible_instance_count < 0 \
		else multi.visible_instance_count


## Caixa envolvente do nó, em espaço de mundo.
##
## Para `MultiMeshInstance3D` a caixa é calculada aqui, instância a instância, porque
## `get_aabb()` devolve uma caixa **vazia**: o Godot mantém os limites de um `MultiMesh` do
## lado do servidor de renderização e não os publica no recurso. Confiar nela deixava toda
## a cidade reduzida a um ponto na origem — e a auditoria contava um nó de cidade no portão
## onde o renderizador desenhava vinte e cinco.
static func _world_aabb(geometry: GeometryInstance3D) -> AABB:
	var box: AABB = geometry.custom_aabb if geometry.custom_aabb.size != Vector3.ZERO \
		else geometry.get_aabb()
	return geometry.global_transform * box


## O nó entra na conta deste enquadramento?
##
## Dois testes, na ordem em que o renderizador os faria: alcance de LOD e caixa envolvente
## contra o tronco de visão. Não é culling de oclusão — occluder não se simula sem
## renderizador —, então o número é um **teto**: o driver desenha isto ou menos.
##
## O teste é **plano a plano**, e não pelos oito cantos da caixa. Testar cantos parece
## equivalente e não é: a caixa de um `MultiMesh` que cobre a cidade inteira pode ter os
## oito cantos fora do tronco e mesmo assim atravessá-lo inteiro. Com cantos, a auditoria
## contava um nó de cidade no portão onde o renderizador desenhava vinte e cinco.
func _in_view(geometry: GeometryInstance3D) -> bool:
	var world: AABB = _world_aabb(geometry)
	var gap: float = _camera.global_position.distance_to(world.get_center())
	if geometry.visibility_range_end > 0.0 and gap > geometry.visibility_range_end:
		return false

	# As normais do tronco do Godot apontam para **fora**: `distance_to() > 0` é o lado de
	# lá. Então o canto que decide é o mais recuado contra a normal — se nem ele está do
	# lado de dentro, a caixa inteira está fora deste plano.
	for plane: Plane in _camera.get_frustum():
		var inner: Vector3 = Vector3(
			world.position.x + (0.0 if plane.normal.x > 0.0 else world.size.x),
			world.position.y + (0.0 if plane.normal.y > 0.0 else world.size.y),
			world.position.z + (0.0 if plane.normal.z > 0.0 else world.size.z)
		)
		if plane.distance_to(inner) > 0.0:
			return false
	return true


static func _mesh_triangles(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	var total: int = 0
	for surface: int in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface)
		# Divisão inteira de propósito: três vértices por triângulo, e triângulo fracionário
		# não existe.
		@warning_ignore("integer_division")
		var indices: int = (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / VERTS_PER_TRIANGLE
		if indices > 0:
			total += indices
			continue
		@warning_ignore("integer_division")
		var vertices: int = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / VERTS_PER_TRIANGLE
		total += vertices
	return total


const VERTS_PER_TRIANGLE: int = 3


## Quantos nós usam cada material **distinto**, contando o que de fato vai para o
## renderizador: o `material_override` quando existe, e a superfície do mesh quando não.
##
## Contar só o override responderia a pergunta errada. Toda peça do kit chega num `.glb`
## com o próprio material embutido, e um material por peça é um agrupamento perdido por
## peça — o teto de `BUDGET.unique_materials` existe para isso e ninguém o estava medindo:
## `Metrics` conta o cache do `MaterialLibrary`, que não sabe dos materiais que vêm dentro
## das malhas.
##
## A identidade é a do recurso (`get_instance_id`), não o nome: dois materiais idênticos
## com o mesmo nome continuam sendo duas trocas de estado.
func _material_census() -> Dictionary:
	var by_id: Dictionary = {}
	var stack: Array[Node] = [_stage]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		for child: Node in current.get_children():
			stack.append(child)
		var geometry: GeometryInstance3D = current as GeometryInstance3D
		if geometry == null:
			continue
		for material: Material in _materials_of(geometry):
			var key: int = material.get_instance_id() if material != null else 0
			var entry: Dictionary = by_id.get(key, {"name": _material_name(material), "nodes": 0})
			entry["nodes"] = int(entry["nodes"]) + 1
			by_id[key] = entry

	var census: Dictionary = {}
	for key: int in by_id:
		var entry: Dictionary = by_id[key]
		# Nome mais um sufixo quando dois recursos distintos compartilham o nome: é
		# justamente esse caso — o mesmo material repetido — que a auditoria procura.
		var name: String = String(entry["name"])
		var suffix: int = 2
		var unique: String = name
		while census.has(unique):
			unique = "%s#%d" % [name, suffix]
			suffix += 1
		census[unique] = int(entry["nodes"])
	return census


static func _materials_of(geometry: GeometryInstance3D) -> Array[Material]:
	if geometry.material_override != null:
		return [geometry.material_override] as Array[Material]

	var mesh: Mesh = null
	var mesh_node: MeshInstance3D = geometry as MeshInstance3D
	if mesh_node != null:
		mesh = mesh_node.mesh
	var multi: MultiMeshInstance3D = geometry as MultiMeshInstance3D
	if multi != null and multi.multimesh != null:
		mesh = multi.multimesh.mesh
	if mesh == null:
		return [] as Array[Material]

	var out: Array[Material] = []
	for surface: int in mesh.get_surface_count():
		out.append(mesh.surface_get_material(surface))
	return out


static func _material_name(material: Material) -> String:
	if material == null:
		return "(sem material)"
	if not material.resource_name.is_empty():
		return material.resource_name
	if not material.resource_path.is_empty():
		return material.resource_path.get_file().get_basename()
	return "(anônimo)"


# --- Câmera -------------------------------------------------------------------


func _aim(station: Array, layout: CityLayout) -> void:
	var anchor: Vector3 = layout.markers.get(
		station[BenchStations.MARKER], layout.markers[&"praca"]
	)
	var away: Vector2 = Vector2(anchor.x, anchor.z) - layout.center
	if away.length() < MIN_LOOK_DISTANCE:
		away = Vector2(cos(layout.angle), sin(layout.angle))
	away = away.normalized()

	var flat: Vector2 = Vector2(anchor.x, anchor.z) \
		+ away * float(station[BenchStations.DISTANCE])
	var spot: Vector3 = Vector3(
		flat.x, anchor.y + float(station[BenchStations.HEIGHT]), flat.y
	)
	var field: HeightField = WorldGenerator.last_field
	if field != null:
		spot.y = maxf(spot.y, field.height_at(spot.x, spot.z) + Params.BENCH_CAMERA_CLEARANCE)

	_camera.global_position = spot
	_camera.look_at(Vector3(anchor.x, spot.y, anchor.z), Vector3.UP)
	_camera.rotate_object_local(Vector3.UP, deg_to_rad(float(station[BenchStations.TURN])))
	_camera.rotate_object_local(Vector3.RIGHT, deg_to_rad(float(station[BenchStations.PITCH])))


func _crowd(layout: CityLayout) -> void:
	var npcs: Array[Node] = []
	_collect(_stage, npcs)
	if npcs.is_empty() or layout == null:
		return
	var center: Vector3 = layout.markers.get(&"praca", Vector3.ZERO)
	for index: int in npcs.size():
		var angle: float = TAU * float(index) / float(npcs.size())
		var radius: float = Params.BENCH_CROWD_RADIUS * (HALF + HALF * float(index % 2))
		(npcs[index] as Node3D).global_position = center \
			+ Vector3(cos(angle) * radius, BODY_RISE - BODY_RISE, sin(angle) * radius)


const HALF: float = 0.5


func _collect(node: Node, out: Array[Node]) -> void:
	if node is NPCController:
		out.append(node)
	for child: Node in node.get_children():
		_collect(child, out)


func _find_region(node: Node) -> NavigationRegion3D:
	if node is NavigationRegion3D:
		return node as NavigationRegion3D
	for child: Node in node.get_children():
		var found: NavigationRegion3D = _find_region(child)
		if found != null:
			return found
	return null


func _wait_for_bake(region: NavigationRegion3D) -> void:
	if region == null:
		return
	var waited: int = 0
	while region.is_baking() and waited < BAKE_TIMEOUT_FRAMES:
		await physics_frame
		waited += 1
	await physics_frame
