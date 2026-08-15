## A cidade como dado, antes de existir um só nó.
##
## Todas as etapas de `CityGenerator` escrevem aqui e leem daqui, e nenhuma delas toca na
## árvore de cena. É o que permite provar o traçado sem renderizar nada: `make city` mede
## sobreposição de prédio, alcance de porta e beco sem saída lendo estes arrays, e só
## depois olha a captura para julgar o que número nenhum julga.
##
## Há dois espaços de coordenadas e a distinção importa:
##
## - **local**: XZ centrado no sítio e girado por `angle`. A subdivisão em quarteirões
##   trabalha aqui, porque retângulo alinhado ao eixo é fácil de cortar e de testar.
## - **mundo**: o XZ do vale. Tudo que vira nó passa por `to_world` antes.
##
## O giro é o que salva a malha de parecer papel quadriculado: a subdivisão continua
## retangular, mas nenhuma rua fica paralela ao eixo do mundo, e a via principal cruza tudo
## em diagonal porque nasce no portão, que a estrada escolheu.
class_name CityLayout
extends RefCounted

## Ranques de rua, do mais largo ao mais estreito. O número é hierarquia, não índice.
const RANK_MAIN: int = 0
const RANK_RING: int = 1
const RANK_STREET: int = 2
const RANK_ALLEY: int = 3

## Centro do sítio, em mundo (XZ).
var center: Vector2 = Vector2.ZERO
## Cota do platô, em metros. A cidade inteira é construída nesta altura.
var ground_y: float = 0.0
## Giro da malha da cidade, em radianos.
var angle: float = 0.0
## Vértices da muralha, em mundo, no sentido do ângulo crescente.
var wall: PackedVector2Array = PackedVector2Array()
## Anel construível: a muralha recuada de `CITY_WALL_MARGIN`.
var buildable: PackedVector2Array = PackedVector2Array()
## Índice do vértice da muralha onde o portão se abre.
var gate_index: int = 0
## Centro do vão do portão, em mundo.
var gate_point: Vector2 = Vector2.ZERO
## Normal do portão, apontando para fora da cidade.
var gate_normal: Vector2 = Vector2.RIGHT
## Centro da praça, em mundo.
var plaza: Vector2 = Vector2.ZERO
## Ruas: `{"a": Vector2, "b": Vector2, "width": float, "rank": int}`, em mundo.
var streets: Array[Dictionary] = []
## Quarteirões, em local: `{"rect": Rect2, "depth": int}`.
var blocks: Array[Dictionary] = []
## Lotes, em mundo: `{"center": Vector2, "facing": Vector2, "width": float, "depth": float}`.
var lots: Array[Dictionary] = []
## Prédios, em mundo. Ver `CityGenerator.raise_buildings` para os campos.
var buildings: Array[Dictionary] = []
## Pontos de interesse: nome -> posição de mundo em 3D.
var markers: Dictionary = {}
## Diagnóstico de cada etapa, para o relatório da prova.
var report: Dictionary = {}


func to_world(local: Vector2) -> Vector2:
	return center + local.rotated(angle)


func to_local(world: Vector2) -> Vector2:
	return (world - center).rotated(-angle)


## Direção de mundo de uma direção local. Direção não translada — só gira.
func dir_to_world(local: Vector2) -> Vector2:
	return local.rotated(angle)


## Ponto 3D no platô da cidade.
func ground(point: Vector2, height: float = 0.0) -> Vector3:
	return Vector3(point.x, ground_y + height, point.y)


## O ponto está dentro do polígono? Ray casting clássico, em mundo.
static func inside(polygon: PackedVector2Array, point: Vector2) -> bool:
	var count: int = polygon.size()
	if count < VERTS_PER_POLYGON:
		return false
	var hit: bool = false
	var previous: int = count - 1
	for index: int in count:
		var a: Vector2 = polygon[index]
		var b: Vector2 = polygon[previous]
		if (a.y > point.y) != (b.y > point.y):
			var span: float = b.y - a.y
			if absf(span) > EPSILON and point.x < a.x + (point.y - a.y) / span * (b.x - a.x):
				hit = not hit
		previous = index
	return hit


## Polígono recuado para dentro por `margin`, vértice a vértice ao longo da bissetriz.
##
## Não é um offset de polígono de verdade — não trata auto-interseção. Serve porque o anel
## da muralha é convexo por construção: os vértices saem de um raio positivo em ângulos
## crescentes, e nenhum recuo razoável o dobra sobre si mesmo.
static func shrink(polygon: PackedVector2Array, origin: Vector2, margin: float) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	for vertex: Vector2 in polygon:
		var outward: Vector2 = vertex - origin
		var reach: float = outward.length()
		if reach <= margin:
			out.append(vertex)
			continue
		out.append(origin + outward * ((reach - margin) / reach))
	return out


## Menor distância de um ponto a um segmento. Usada pelo corredor da via principal e pela
## checagem de props que não podem nascer na rua.
static func distance_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var span: Vector2 = b - a
	var length_squared: float = span.length_squared()
	if length_squared <= EPSILON:
		return point.distance_to(a)
	var travel: float = clampf((point - a).dot(span) / length_squared, 0.0, 1.0)
	return point.distance_to(a + span * travel)


## Menor distância do ponto a qualquer rua de ranque até `max_rank`, já descontada a
## meia-largura da via. Negativa quer dizer "dentro da rua".
func street_clearance(point: Vector2, max_rank: int = RANK_ALLEY) -> float:
	var best: float = INF
	for street: Dictionary in streets:
		if int(street["rank"]) > max_rank:
			continue
		var gap: float = distance_to_segment(point, street["a"], street["b"])
		best = minf(best, gap - float(street["width"]) * 0.5)
	return best


const VERTS_PER_POLYGON: int = 3
const EPSILON: float = 0.000001
