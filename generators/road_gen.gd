@tool
## A estrada: a única coisa do vale desenhada por uma curva, e não por ruído.
##
## Ela liga a borda do vale à planície onde a cidade vai nascer, e a ordem das operações é
## o ponto inteiro: **o terreno se ajusta à estrada, não o contrário**. Primeiro a curva
## amostra o relevo para saber por onde passaria; depois esse perfil de altura é suavizado
## e limitado a `ROAD_MAX_SLOPE`; só então o terreno é cortado e aterrado para encontrar a
## estrada. Se fosse ao contrário — traçar por cima do relevo pronto — a estrada herdaria
## cada lombada do ruído e teria trechos que uma carroça não sobe.
##
## O corte não é um degrau: o leito fica plano e o acostamento dissolve o corte no relevo
## original ao longo de `ROAD_SHOULDER`. Sem essa transição, a estrada vira uma trincheira
## de paredes verticais, e a colisão trimesh que sai dela prende o jogador.
##
## O que fica registrado no campo de altura é a **distância até o eixo**. Três consumidores
## a usam com raios diferentes: a cor pinta o leito, o espalhamento se afasta dela, e a
## própria terraplenagem decide onde parar. Guardar distância, e não uma máscara booleana,
## é o que permite os três raios saírem do mesmo dado.
class_name RoadGenerator
extends RefCounted

## Semente derivada, para o traçado não andar em fase com o relevo.
const SEED_OFFSET: int = 31337
## Alcance além do qual a distância à estrada deixa de ser registrada. É o maior raio que
## algum consumidor pede: acostamento mais a folga de vegetação.
const RECORD_MARGIN: float = 1.0
## Lados do vale de onde a estrada pode entrar. Estrutural: um retângulo tem quatro.
const EDGE_COUNT: int = 4
const EDGE_SOUTH: int = 0
const EDGE_NORTH: int = 1
const EDGE_WEST: int = 2
const EDGE_EAST: int = 3
## Piso do comprimento da curva, para não dividir por zero num traçado degenerado.
const MIN_LENGTH: float = 0.001
## Peso da média móvel que suaviza o perfil de altura da estrada.
const SMOOTH_WEIGHT: float = 0.5
## Fração do meio-lado que o ponto de entrada pode deslizar ao longo da borda.
const ENTRY_SPREAD: float = 0.5


## Traça a estrada, corta o terreno e devolve a curva para quem quiser desenhá-la.
##
## `field` sai modificado: as alturas sob o leito passam a ser as da estrada, e a distância
## ao eixo fica registrada em cada vértice próximo.
static func carve(field: HeightField, world_seed: int) -> Curve3D:
	var curve: Curve3D = _trace(field, world_seed)
	var points: PackedVector3Array = _sample(curve, field)
	points = _level(points)
	_stamp(field, points)
	field.refresh_bounds()
	return curve


## Traçado: da borda do vale até a praça, com desvio lateral por seed.
##
## O desvio existe para a estrada não ser um segmento de reta. Uma reta seria o caminho
## honesto entre dois pontos e leria como estrada de mapa, não como estrada de vale —
## ninguém corta uma montanha em linha reta quando dá para contorná-la.
static func _trace(field: HeightField, world_seed: int) -> Curve3D:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = world_seed + SEED_OFFSET

	var half: float = field.size() * 0.5
	var destination: Vector2 = field.plain_center
	# A entrada nasce numa das quatro bordas, sorteada — é o que mais muda a cara do vale
	# entre duas seeds, porque arrasta o traçado inteiro junto.
	var side: int = rng.randi_range(0, EDGE_COUNT - 1)
	var offset: float = rng.randf_range(-half * ENTRY_SPREAD, half * ENTRY_SPREAD)
	var edge: float = half - Params.ROAD_ENTRY_MARGIN
	var entry: Vector2 = Vector2(offset, -edge)
	if side == EDGE_NORTH:
		entry = Vector2(offset, edge)
	elif side == EDGE_WEST:
		entry = Vector2(-edge, offset)
	elif side == EDGE_EAST:
		entry = Vector2(edge, offset)

	var curve: Curve3D = Curve3D.new()
	var steps: int = maxi(Params.ROAD_CONTROL_POINTS, 2)
	for index: int in steps:
		var t: float = float(index) / float(steps - 1)
		var straight: Vector2 = entry.lerp(destination, t)
		# O desvio é máximo no meio e nulo nas pontas: a estrada tem de chegar à praça e
		# sair da borda exatamente onde prometeu.
		var wander: float = sin(t * PI) * Params.ROAD_WANDER
		var side_dir: Vector2 = (destination - entry).normalized().orthogonal()
		var point: Vector2 = straight + side_dir * rng.randf_range(-wander, wander)
		curve.add_point(Vector3(point.x, field.height_at(point.x, point.y), point.y))
	return curve


## Amostra a curva já apoiada no relevo. A altura vem do terreno; o próximo passo é que
## decide qual altura a estrada vai *impor*.
static func _sample(curve: Curve3D, field: HeightField) -> PackedVector3Array:
	var points: PackedVector3Array = PackedVector3Array()
	var count: int = maxi(Params.ROAD_SAMPLES, 2)
	points.resize(count)
	var length: float = maxf(curve.get_baked_length(), MIN_LENGTH)
	for index: int in count:
		var distance: float = length * float(index) / float(count - 1)
		var point: Vector3 = curve.sample_baked(distance)
		points[index] = Vector3(point.x, field.height_at(point.x, point.z), point.z)
	return points


## Suaviza o perfil e força a inclinação máxima.
##
## Duas passagens, e as duas são necessárias. A média móvel tira as lombadas mas não
## garante nada; o passe de limite anda a lista para a frente e para trás cortando
## qualquer degrau que ainda exceda `ROAD_MAX_SLOPE` — nas duas direções, porque limitar
## só numa deixa o sentido oposto livre para descer o quanto quiser.
static func _level(points: PackedVector3Array) -> PackedVector3Array:
	var count: int = points.size()
	if count < 2:
		return points

	for _pass: int in Params.ROAD_SMOOTH_PASSES:
		var smoothed: PackedVector3Array = points.duplicate()
		for index: int in range(1, count - 1):
			var average: float = (points[index - 1].y + points[index + 1].y) * 0.5
			smoothed[index] = Vector3(
				points[index].x, lerpf(points[index].y, average, SMOOTH_WEIGHT), points[index].z
			)
		points = smoothed

	for index: int in range(1, count):
		points[index] = _clamp_step(points[index - 1], points[index])
	for index: int in range(count - 2, -1, -1):
		points[index] = _clamp_step(points[index + 1], points[index])
	return points


## Aproxima `next` de `previous` até caber na inclinação de projeto.
##
## Projeto, e não aceite: o limite vale para o terreno construído, e a grade de 4 m não
## reproduz de graça a rampa que o perfil descreve a cada 1,2 m. `ROAD_GRADE_MARGIN` é a
## folga que absorve essa diferença.
static func _clamp_step(previous: Vector3, next: Vector3) -> Vector3:
	var run: float = Vector2(next.x - previous.x, next.z - previous.z).length()
	var allowed: float = run * design_slope()
	var rise: float = clampf(next.y - previous.y, -allowed, allowed)
	return Vector3(next.x, previous.y + rise, next.z)


## Inclinação com que a estrada é traçada, sempre abaixo da que ela tem de cumprir.
static func design_slope() -> float:
	return maxf(Params.ROAD_MAX_SLOPE - Params.ROAD_GRADE_MARGIN, MIN_LENGTH)


## Crava a estrada no terreno.
##
## Percorre as amostras e mexe só nos vértices perto de cada uma, em vez de varrer o vale
## inteiro procurando a estrada: o leito ocupa menos de 1% da área, e a varredura completa
## custaria dezesseis mil testes de distância por amostra.
##
## Três regras aqui não são detalhe de implementação, são o que faz a estrada respeitar a
## inclinação **no terreno** e não só na lista de amostras:
##
## 1. **O vértice é projetado no eixo**, e não encostado na amostra mais próxima. A altura
##    cravada sai da interpolação ao longo do segmento, num contínuo. Copiar a altura de
##    uma amostra discreta faz dois vértices vizinhos do mesmo leito herdarem pontos
##    diferentes da curva: o leito sai serrilhado na direção transversal, e a altura
##    bilinear lida sobre o eixo balança junto. Era daí que vinham 110 das 220 amostras
##    acima do limite, com a pior em 0,132 contra 0,11 — em terreno de inclinação 0,007,
##    ou seja, num trecho onde o relevo não tinha culpa nenhuma.
## 2. **Vence a projeção mais próxima**, não a última. A curva pode se aproximar de si
##    mesma — com 78 m de desvio lateral, ela faz isso —, e aí dois trechos de altura
##    muito diferente disputam o mesmo vértice.
## 3. **A mistura parte da altura original**, guardada antes de qualquer escrita. Misturar
##    a partir do valor corrente faz cada segmento compor sobre o anterior, e o acostamento
##    afunda progressivamente a cada passada em vez de dissolver no relevo.
static func _stamp(field: HeightField, points: PackedVector3Array) -> void:
	var reach: float = (
		Params.ROAD_WIDTH * 0.5
		+ Params.ROAD_SHOULDER
		+ Params.SCATTER_ROAD_CLEARANCE
		+ RECORD_MARGIN
	)
	var cell: float = field.cell_size()
	var half: float = field.size() * 0.5
	# O leito achatado é o maior entre a meia-largura e uma célula e meia. A grade tem 4 m
	# e o leito 6: o canto mais distante da célula que contém um ponto do eixo fica a uma
	# diagonal dela, 5,66 m. Com o leito em 6 m os quatro cantos entram cravados, e só assim
	# a leitura bilinear sobre o eixo devolve a rampa que o nivelamento prometeu.
	var bed: float = maxf(Params.ROAD_WIDTH * 0.5, cell * Params.ROAD_BED_CELLS)
	var shoulder_end: float = bed + Params.ROAD_SHOULDER
	var original: Dictionary = {}

	for index: int in range(points.size() - 1):
		var start: Vector3 = points[index]
		var finish: Vector3 = points[index + 1]
		var axis: Vector2 = Vector2(finish.x - start.x, finish.z - start.z)
		var axis_length: float = maxf(axis.length_squared(), MIN_LENGTH)

		var min_x: int = int(floor((minf(start.x, finish.x) + half - reach) / cell))
		var max_x: int = int(ceil((maxf(start.x, finish.x) + half + reach) / cell))
		var min_z: int = int(floor((minf(start.z, finish.z) + half - reach) / cell))
		var max_z: int = int(ceil((maxf(start.z, finish.z) + half + reach) / cell))

		for iz: int in range(maxi(min_z, 0), mini(max_z, field.cells()) + 1):
			for ix: int in range(maxi(min_x, 0), mini(max_x, field.cells()) + 1):
				var world: Vector3 = field.vertex(ix, iz)
				var offset: Vector2 = Vector2(world.x - start.x, world.z - start.z)
				var travel: float = clampf(offset.dot(axis) / axis_length, 0.0, 1.0)
				var distance: float = offset.distance_to(axis * travel)
				if distance > reach:
					continue
				if distance >= field.road_at_index(ix, iz):
					continue  # outro trecho já passou mais perto deste vértice
				field.mark_road(ix, iz, distance)
				if distance > shoulder_end:
					continue

				var key: int = iz * (field.cells() + 1) + ix
				if not original.has(key):
					original[key] = world.y
				# Leito plano; acostamento em transição suave para o relevo original.
				var pull: float = 1.0 - smoothstep(bed, shoulder_end, distance)
				var axis_y: float = lerpf(start.y, finish.y, travel)
				field.set_at_index(ix, iz, lerpf(float(original[key]), axis_y, pull))


## Maior inclinação encontrada ao longo da estrada já cravada, como tangente.
##
## É o critério "respeita a inclinação máxima" medido no resultado, e não prometido pelo
## algoritmo: o corte do terreno acontece depois do nivelamento, e um erro ali reapareceria
## como rampa impossível sem que nada reclamasse.
static func measure_slope(field: HeightField, curve: Curve3D) -> float:
	var length: float = maxf(curve.get_baked_length(), MIN_LENGTH)
	var count: int = maxi(Params.ROAD_SAMPLES, 2)
	var worst: float = 0.0
	var previous: Vector3 = Vector3.ZERO
	for index: int in count:
		var distance: float = length * float(index) / float(count - 1)
		var point: Vector3 = curve.sample_baked(distance)
		var here: Vector3 = field.ground_point(point.x, point.z)
		if index > 0:
			var run: float = Vector2(here.x - previous.x, here.z - previous.z).length()
			if run > 0.0:
				worst = maxf(worst, absf(here.y - previous.y) / run)
		previous = here
	return worst
