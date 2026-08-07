## Núcleo de geração de malha low poly.
##
## Constrói `ArrayMesh` com **shading flat e vertex color**: cada triângulo tem os seus
## próprios três vértices e uma única normal de face. É isso que dá a silhueta dura da
## estética do projeto — e o que permite pintar a malha sem uma única textura.
##
## Nenhuma malha do jogo é importada de arquivo: toda geometria passa por aqui.
##
## Uso:
##     var builder: MeshBuilder = MeshBuilder.new()
##     builder.add_box(Vector3.ZERO, Vector3.ONE, Params.color(&"stone"))
##     var mesh: ArrayMesh = builder.commit(&"prop")
##
## `commit()` valida a contagem de triângulos contra `Params.TRI_BUDGET` e reprova
## a malha que estourar o teto da categoria.
class_name MeshBuilder
extends RefCounted

const VERTS_PER_TRIANGLE: int = 3

var _vertices: PackedVector3Array = PackedVector3Array()
var _normals: PackedVector3Array = PackedVector3Array()
var _colors: PackedColorArray = PackedColorArray()
var _triangles: int = 0


## Triângulos acumulados até agora.
func triangle_count() -> int:
	return _triangles


## Esvazia o builder para reuso sem realocar o objeto.
func clear() -> void:
	_vertices.clear()
	_normals.clear()
	_colors.clear()
	_triangles = 0


## Triângulo com normal de face calculada. Passe os vértices em ordem **anti-horária**
## vista de fora — é a convenção que faz `(b - a) × (c - a)` apontar para fora.
##
## O Godot, porém, considera frontal o triângulo de winding **horário**. Emitir na ordem
## recebida deixaria toda a geometria virada para dentro: a malha existe, consome draw
## call, e não aparece. Por isso a emissão troca `b` e `c` — a normal continua a mesma.
func add_triangle(a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	var normal: Vector3 = (b - a).cross(c - a).normalized()
	_push(a, normal, color)
	_push(c, normal, color)
	_push(b, normal, color)
	_triangles += 1


## Quadrilátero plano, dividido em dois triângulos. Vértices em ordem de perímetro.
func add_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	add_triangle(a, b, c, color)
	add_triangle(a, c, d, color)


## Plano horizontal centrado em `center`, no plano XZ, virado para +Y.
func add_plane_xz(center: Vector3, size: Vector2, color: Color) -> void:
	var half: Vector2 = size * 0.5
	add_quad(
		center + Vector3(-half.x, 0.0, half.y),
		center + Vector3(half.x, 0.0, half.y),
		center + Vector3(half.x, 0.0, -half.y),
		center + Vector3(-half.x, 0.0, -half.y),
		color
	)


## Caixa fechada de seis faces, centrada em `center`.
func add_box(center: Vector3, size: Vector3, color: Color) -> void:
	var half: Vector3 = size * 0.5
	var min_corner: Vector3 = center - half
	var max_corner: Vector3 = center + half

	# Cantos: n = mínimo, x = máximo, na ordem (x, y, z).
	var nnn: Vector3 = Vector3(min_corner.x, min_corner.y, min_corner.z)
	var xnn: Vector3 = Vector3(max_corner.x, min_corner.y, min_corner.z)
	var xnx: Vector3 = Vector3(max_corner.x, min_corner.y, max_corner.z)
	var nnx: Vector3 = Vector3(min_corner.x, min_corner.y, max_corner.z)
	var nxn: Vector3 = Vector3(min_corner.x, max_corner.y, min_corner.z)
	var xxn: Vector3 = Vector3(max_corner.x, max_corner.y, min_corner.z)
	var xxx: Vector3 = Vector3(max_corner.x, max_corner.y, max_corner.z)
	var nxx: Vector3 = Vector3(min_corner.x, max_corner.y, max_corner.z)

	add_quad(nxx, xxx, xxn, nxn, color) # topo
	add_quad(nnn, xnn, xnx, nnx, color) # base
	add_quad(nnx, xnx, xxx, nxx, color) # frente (+Z)
	add_quad(xnn, nnn, nxn, xxn, color) # fundo (-Z)
	add_quad(xnx, xnn, xxn, xxx, color) # direita (+X)
	add_quad(nnn, nnx, nxx, nxn, color) # esquerda (-X)


## Grade plana em XZ com uma cor por célula — a base de todo terreno vertex-colored.
## `tint` recebe (coluna, linha) e devolve a cor da célula.
func add_color_grid(center: Vector3, size: float, cells: int, tint: Callable) -> void:
	var cell_size: float = size / float(cells)
	var origin: Vector3 = center - Vector3(size, 0.0, size) * 0.5
	for row: int in cells:
		for column: int in cells:
			var cell_center: Vector3 = origin + Vector3(
				(float(column) + 0.5) * cell_size,
				0.0,
				(float(row) + 0.5) * cell_size
			)
			var color: Color = tint.call(column, row)
			add_plane_xz(cell_center, Vector2(cell_size, cell_size), color)


## Fecha a malha e valida contra o orçamento da categoria (ver `Params.TRI_BUDGET`).
## Devolve `null` se o builder estiver vazio.
func commit(category: StringName) -> ArrayMesh:
	if _vertices.is_empty():
		push_warning("MeshBuilder.commit(%s) chamado sem geometria." % category)
		return null

	var triangles: int = triangle_count()
	var ceiling: int = Params.tri_budget(category)
	if ceiling > 0 and triangles > ceiling:
		push_error(
			"Malha '%s' estourou o orçamento: %d triângulos para um teto de %d."
			% [category, triangles, ceiling]
		)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertices
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_COLOR] = _colors

	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.resource_name = String(category)
	return mesh


func _push(vertex: Vector3, normal: Vector3, color: Color) -> void:
	_vertices.append(vertex)
	_normals.append(normal)
	_colors.append(color)
