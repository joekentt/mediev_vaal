@tool
## A cidade, de uma seed só: sítio, muralha, ruas, lotes, prédios, props e interiores.
##
## O pipeline é sete etapas isoladas, na ordem em que uma precisa da anterior:
##
##   a) sítio      — mede a planície e escolhe onde a cidade cabe
##   b) muralha    — polígono irregular e portão voltado para a estrada
##   c) ruas       — via principal do portão à praça, anel interno e becos por subdivisão
##   d) lotes      — quarteirão vira fileira de testadas de larguras variadas
##   e) prédios    — cada lote empilha peças do kit conforme o tipo
##   f) props      — bancas, poço, lanternas, carroças, cercas e varais
##   g) interiores — dois de verdade, cartas escuras nos demais
##
## Cada etapa escreve num `CityLayout` e nenhuma delas cria nó: quem instancia é
## `CityBuilder`, depois que o traçado inteiro está fechado e validado. A separação não é
## purismo — é o que permite `make city` reprovar uma cidade quebrada **antes** de ela
## custar dez mil instâncias, e o que permite testar a subdivisão sem abrir uma janela.
##
## A cidade é terraplenada antes de a estrada ser traçada. A ordem tem de ser essa: se o
## platô descesse depois, ele afundaria o leito já cravado e a estrada chegaria à cidade
## por um degrau. Terraplenando antes, a estrada nivela o próprio perfil sobre chão que já
## está plano, e o encontro sai de graça.
class_name CityGenerator
extends RefCounted

## Sementes derivadas, uma por etapa. Sem isso, mexer no número de lotes mudaria o
## traçado da muralha — e "ajustei a densidade e a cidade inteira virou outra" é o tipo de
## acoplamento que torna impossível iterar.
const SEED_SITE: int = 22447
const SEED_WALL: int = 33613
const SEED_STREETS: int = 48091
const SEED_LOTS: int = 57173
const SEED_BUILDINGS: int = 69431
const SEED_PROPS: int = 78779

## Lados de um retângulo — o passo do laço que testa as quatro bordas de um quarteirão.
const RECT_SIDES: int = 4
## Divisor de meia-medida com nome, para não parecer constante de jogabilidade escondida.
const HALF: float = 0.5
## Piso de comprimento, para não dividir por zero num segmento degenerado.
const MIN_LENGTH: float = 0.001
## Tentativas de sorteio antes de desistir de um ponto livre.
const PLACEMENT_TRIES: int = 12
## Quantos marcadores de casa a fase 10 espera encontrar (`casa_01..15`).
const HOUSE_MARKERS: int = 15
## Área de um hectare, em m². A densidade de props é dada por hectare, como no vale.
const HECTARE: float = 10000.0


# --- Orquestração -------------------------------------------------------------


## Roda o pipeline inteiro e devolve o traçado. **Modifica `field`**: a etapa de sítio
## terraplena o platô, e é por isso que ela tem de rodar antes da estrada.
static func plan(field: HeightField, world_seed: int) -> CityLayout:
	var layout: CityLayout = CityLayout.new()
	choose_site(layout, field, world_seed)
	terrace(layout, field)
	return layout


## Segunda metade do plano, depois que a estrada existe: é ela que decide onde é o portão.
static func plan_streets(layout: CityLayout, road: Curve3D, world_seed: int) -> void:
	trace_wall(layout, road, world_seed)
	trace_streets(layout, world_seed)
	split_lots(layout, world_seed)
	raise_buildings(layout, world_seed)
	place_markers(layout)


# --- a) Sítio -----------------------------------------------------------------


## Escolhe onde a cidade nasce: sorteia candidatos na planície e pontua cada um.
##
## Medir, e não cravar o centro da planície, muda o resultado de verdade: a planície da
## fase 4 desliza com a seed e a erosão deixa nela encostas que o olho não vê numa vista
## aérea mas que põem uma fileira de casas em ladeira. O que se pontua é a inclinação
## média sob a futura muralha — o número que decide se as portas ficam no chão.
static func choose_site(layout: CityLayout, field: HeightField, world_seed: int) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = world_seed + SEED_SITE

	var best_score: float = -INF
	var best_center: Vector2 = field.plain_center
	var best_slope: float = 0.0
	var tested: int = 0

	for _candidate: int in Params.CITY_SITE_CANDIDATES:
		var angle: float = rng.randf_range(0.0, TAU)
		# Raiz da fração para o sorteio cobrir o disco por área, e não se amontoar no
		# centro — um sorteio uniforme no raio concentra metade dos candidatos no miolo.
		var reach: float = sqrt(rng.randf()) * Params.CITY_SITE_SEARCH_RADIUS
		var candidate: Vector2 = field.plain_center + Vector2(cos(angle), sin(angle)) * reach
		var measured: Dictionary = _measure_site(field, candidate)
		tested += 1
		if float(measured["slope"]) > Params.CITY_SITE_MAX_SLOPE:
			continue

		# Plano manda; perto da planície desempata. A planície é o destino da estrada, então
		# proximidade a ela é proximidade à estrada antes de a estrada existir.
		var flatness: float = 1.0 - float(measured["slope"]) / Params.CITY_SITE_MAX_SLOPE
		var closeness: float = 1.0 - reach / Params.CITY_SITE_SEARCH_RADIUS
		var score: float = flatness + closeness
		if score > best_score:
			best_score = score
			best_center = candidate
			best_slope = float(measured["slope"])

	layout.center = best_center
	layout.ground_y = _measure_site(field, best_center)["height"]
	# O giro da malha sai da seed: sem ele, toda cidade teria as ruas paralelas ao eixo do
	# mundo e a primeira vista aérea entregaria a grade.
	layout.angle = deg_to_rad(
		rng.randf_range(-Params.CITY_GRID_JITTER_DEG, Params.CITY_GRID_JITTER_DEG)
	) + rng.randf_range(0.0, TAU)
	layout.plaza = best_center
	layout.report["site_candidates"] = tested
	layout.report["site_slope"] = best_slope
	layout.report["site_drift_m"] = best_center.distance_to(field.plain_center)


## Inclinação média e altura média sob a futura muralha.
static func _measure_site(field: HeightField, candidate: Vector2) -> Dictionary:
	var slope_total: float = 0.0
	var height_total: float = 0.0
	var samples: int = maxi(Params.CITY_SITE_PROBES, 1)
	for index: int in samples:
		# Espiral de Fermat: cobre o disco sem grade e sem sorteio, então dois candidatos
		# vizinhos são medidos nos mesmos pontos relativos e a comparação é justa.
		var fraction: float = (float(index) + HALF) / float(samples)
		var reach: float = sqrt(fraction) * Params.CITY_RADIUS
		var angle: float = fraction * TAU * float(samples) * GOLDEN_ANGLE_TURNS
		var point: Vector2 = candidate + Vector2(cos(angle), sin(angle)) * reach
		slope_total += field.slope_at(point.x, point.y)
		height_total += field.height_at(point.x, point.y)
	return {
		"slope": slope_total / float(samples),
		"height": height_total / float(samples),
	}


## Voltas por amostra da espiral de Fermat — o ângulo áureo em frações de volta.
const GOLDEN_ANGLE_TURNS: float = 0.381966


## Achata o sítio. O platô recebe a altura média medida, e o relevo original volta ao
## longo de `CITY_TERRACE_FALLOFF`.
##
## Sem isto o kit não fecha: as peças de parede são prismas retos de 3 m e não têm remate
## para encostar em ladeira. Uma cidade em declive precisaria de fundação escalonada, que é
## peça da fase 7.
static func terrace(layout: CityLayout, field: HeightField) -> void:
	var flat: float = Params.CITY_RADIUS + Params.CITY_WALL_MODULE
	var outer: float = flat + Params.CITY_TERRACE_FALLOFF
	var cells: int = field.cells()
	var half: float = field.size() * HALF
	var moved: float = 0.0

	for iz: int in cells + 1:
		for ix: int in cells + 1:
			var x: float = -half + float(ix) * field.cell_size()
			var z: float = -half + float(iz) * field.cell_size()
			var distance: float = Vector2(x, z).distance_to(layout.center)
			if distance >= outer:
				continue
			var pull: float = 1.0 - smoothstep(flat, outer, distance)
			pull *= Params.CITY_TERRACE_FLATNESS
			var before: float = field.at_index(ix, iz)
			var after: float = lerpf(before, layout.ground_y, pull)
			moved = maxf(moved, absf(after - before))
			field.set_at_index(ix, iz, after)

	field.refresh_bounds()
	layout.report["terrace_cut_m"] = moved


# --- b) Muralha ---------------------------------------------------------------


## Traça a muralha e abre o portão do lado por onde a estrada chega.
##
## O portão não é sorteado: é a aresta da muralha cujo meio está mais perto do **eixo da
## estrada**, medido na própria curva. Sortear daria uma cidade com a entrada virada para o
## mato e a estrada morrendo contra a pedra.
##
## Medir na curva, e não no campo de distância que a fase 4 grava, porque a estrada deixou
## de cravar o terreno dentro da muralha: ali o campo devolve o "sem estrada" de um milhão
## de metros, e todas as arestas empatam. O primeiro portão gerado assim ficou nas costas da
## cidade, e o relatório entregou o defeito com um "portão a 1000000,0 m da estrada".
static func trace_wall(layout: CityLayout, road: Curve3D, world_seed: int) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = world_seed + SEED_WALL

	var sides: int = maxi(Params.CITY_WALL_SIDES, RECT_SIDES)
	var step: float = TAU / float(sides)
	var ring: PackedVector2Array = PackedVector2Array()
	for index: int in sides:
		var jitter: float = rng.randf_range(
			-Params.CITY_WALL_ANGLE_JITTER, Params.CITY_WALL_ANGLE_JITTER
		)
		var angle: float = (float(index) + jitter) * step + layout.angle
		var reach: float = Params.CITY_RADIUS * (
			1.0 + rng.randf_range(-Params.CITY_RADIUS_JITTER, Params.CITY_RADIUS_JITTER)
		)
		ring.append(layout.center + Vector2(cos(angle), sin(angle)) * reach)
	layout.wall = ring
	layout.buildable = CityLayout.shrink(ring, layout.center, Params.CITY_WALL_MARGIN)

	var best: int = 0
	var best_distance: float = INF
	for index: int in sides:
		var middle: Vector2 = (ring[index] + ring[(index + 1) % sides]) * HALF
		var gap: float = _distance_to_curve(road, middle)
		if gap < best_distance:
			best_distance = gap
			best = index

	layout.gate_index = best
	layout.gate_point = (ring[best] + ring[(best + 1) % sides]) * HALF
	layout.gate_normal = (layout.gate_point - layout.center).normalized()
	layout.report["gate_road_distance_m"] = best_distance


## Menor distância em planta de um ponto à curva da estrada.
static func _distance_to_curve(road: Curve3D, point: Vector2) -> float:
	if road == null:
		return INF
	var length: float = maxf(road.get_baked_length(), MIN_LENGTH)
	var steps: int = maxi(Params.ROAD_SAMPLES, 2)
	var best: float = INF
	for index: int in steps:
		var spot: Vector3 = road.sample_baked(length * float(index) / float(steps - 1))
		best = minf(best, point.distance_to(Vector2(spot.x, spot.z)))
	return best


# --- c) Ruas ------------------------------------------------------------------


## Rede de ruas: via principal, anel interno e becos por subdivisão recursiva.
static func trace_streets(layout: CityLayout, world_seed: int) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = world_seed + SEED_STREETS
	layout.streets.clear()

	_trace_main_street(layout, rng)
	_trace_ring(layout)
	_subdivide(layout, rng)
	layout.report["streets"] = layout.streets.size()


## Do portão à praça, com curva. Uma reta chegaria mais rápido e leria como avenida de
## capital planejada; os desvios laterais são o que faz a fachada seguinte aparecer aos
## poucos em vez de a rua inteira se entregar do portão.
static func _trace_main_street(layout: CityLayout, rng: RandomNumberGenerator) -> void:
	var span: Vector2 = layout.plaza - layout.gate_point
	var side: Vector2 = span.orthogonal().normalized()
	var bends: int = maxi(Params.CITY_MAIN_STREET_BENDS, 1)

	var previous: Vector2 = layout.gate_point
	for index: int in range(1, bends + 1):
		var travel: float = float(index) / float(bends)
		var straight: Vector2 = layout.gate_point + span * travel
		# O desvio morre nas duas pontas: a via tem de encostar no portão e na praça
		# exatamente onde eles estão.
		var sway: float = sin(travel * PI) * Params.CITY_MAIN_STREET_JITTER
		var point: Vector2 = straight + side * rng.randf_range(-sway, sway)
		if index == bends:
			point = layout.plaza
		_add_street(layout, previous, point, Params.CITY_MAIN_STREET_WIDTH, CityLayout.RANK_MAIN)
		previous = point


## Anel logo dentro da muralha. É o que impede um quarteirão de encostar na pedra e o que
## dá à guarda um caminho contínuo — a fase 10 vai andar nele.
static func _trace_ring(layout: CityLayout) -> void:
	var count: int = layout.buildable.size()
	for index: int in count:
		_add_street(
			layout,
			layout.buildable[index],
			layout.buildable[(index + 1) % count],
			Params.CITY_STREET_WIDTH,
			CityLayout.RANK_RING
		)


## Subdivisão recursiva do interior em quarteirões, cortando uma rua a cada divisão.
##
## O corte cai perto do meio, mas não no meio: `CITY_SPLIT_JITTER` é o que separa uma
## cidade de um tabuleiro. O eixo é sempre o mais longo, senão a recursão produz tiras.
static func _subdivide(layout: CityLayout, rng: RandomNumberGenerator) -> void:
	var reach: float = Params.CITY_RADIUS - Params.CITY_WALL_MARGIN
	var start: Rect2 = Rect2(-reach, -reach, reach * 2.0, reach * 2.0)
	layout.blocks.clear()
	_split(layout, rng, start, 0)


static func _split(
	layout: CityLayout, rng: RandomNumberGenerator, rect: Rect2, depth: int
) -> void:
	var longest: float = maxf(rect.size.x, rect.size.y)
	if depth >= Params.CITY_SPLIT_MAX_DEPTH or longest < Params.CITY_BLOCK_MIN * 2.0:
		var fitted: Rect2 = _fit_block(layout, rect)
		if fitted.size.x >= Params.CITY_LOT_MIN and fitted.size.y >= Params.CITY_LOT_MIN:
			layout.blocks.append({"rect": fitted, "depth": depth})
		return

	var vertical: bool = rect.size.x >= rect.size.y
	var width: float = (
		Params.CITY_STREET_WIDTH if depth <= 1 else Params.CITY_ALLEY_WIDTH
	)
	var rank: int = CityLayout.RANK_STREET if depth <= 1 else CityLayout.RANK_ALLEY
	var travel: float = HALF + rng.randf_range(-Params.CITY_SPLIT_JITTER, Params.CITY_SPLIT_JITTER)

	if vertical:
		var cut_x: float = rect.position.x + rect.size.x * travel
		_add_clipped_street(
			layout,
			layout.to_world(Vector2(cut_x, rect.position.y)),
			layout.to_world(Vector2(cut_x, rect.end.y)),
			width,
			rank
		)
		var left: float = cut_x - width * HALF - rect.position.x
		var right: float = rect.end.x - (cut_x + width * HALF)
		_split(layout, rng, Rect2(rect.position, Vector2(left, rect.size.y)), depth + 1)
		_split(
			layout, rng,
			Rect2(Vector2(cut_x + width * HALF, rect.position.y), Vector2(right, rect.size.y)),
			depth + 1
		)
		return

	var cut_y: float = rect.position.y + rect.size.y * travel
	_add_clipped_street(
		layout,
		layout.to_world(Vector2(rect.position.x, cut_y)),
		layout.to_world(Vector2(rect.end.x, cut_y)),
		width,
		rank
	)
	var top: float = cut_y - width * HALF - rect.position.y
	var bottom: float = rect.end.y - (cut_y + width * HALF)
	_split(layout, rng, Rect2(rect.position, Vector2(rect.size.x, top)), depth + 1)
	_split(
		layout, rng,
		Rect2(Vector2(rect.position.x, cut_y + width * HALF), Vector2(rect.size.x, bottom)),
		depth + 1
	)


## Encolhe o quarteirão em torno do próprio centro até ele caber dentro da muralha.
##
## Recusar todo quarteirão que não coubesse inteiro foi a primeira versão, e ela produziu
## uma cidade com zero lotes: a subdivisão parte do quadrado que **envolve** a muralha, e
## um quarteirão de 24 m nessa grade quase sempre tem um canto para fora do anel. Encolher
## em vez de recusar é o que dá à cidade a borda irregular que uma muralha real impõe — as
## quadras junto ao muro são menores, exatamente como numa planta medieval.
##
## Busca binária na escala, e não passo fixo: seis iterações levam o erro a menos de 2% do
## lado, e a alternativa seria escolher um passo que ou desperdiça área ou custa iteração.
static func _fit_block(layout: CityLayout, rect: Rect2) -> Rect2:
	var middle: Vector2 = rect.get_center()
	if middle.length() > Params.CITY_RADIUS:
		return Rect2()
	# Um quarteirão com a praça dentro dele não tem como sair dela encolhendo — some.
	if middle.length() < Params.CITY_PLAZA_RADIUS:
		return Rect2()

	var low: float = 0.0
	var high: float = 1.0
	if _block_fits(layout, rect):
		return rect
	for _step: int in FIT_STEPS:
		var scale: float = (low + high) * HALF
		if _block_fits(layout, Rect2(middle - rect.size * scale * HALF, rect.size * scale)):
			low = scale
		else:
			high = scale
	return Rect2(middle - rect.size * low * HALF, rect.size * low)


## O quarteirão cabe: quatro cantos dentro da muralha e nenhuma parte dentro da praça.
##
## Encolher em vez de descartar quando a praça é tocada valeu quase um terço da cidade.
## Descartar custava um quarteirão inteiro por vez, e até quatro deles cercam a praça —
## era o maior sumidouro de área do traçado, medido em 26% de aproveitamento.
static func _block_fits(layout: CityLayout, rect: Rect2) -> bool:
	# A praça fica na origem do espaço local, porque o centro da cidade é o centro dela.
	var nearest: Vector2 = Vector2(
		clampf(0.0, rect.position.x, rect.end.x),
		clampf(0.0, rect.position.y, rect.end.y)
	)
	if nearest.length() < Params.CITY_PLAZA_RADIUS:
		return false
	return _corners_inside(layout, rect)


## Busca binária da escala do quarteirão. Seis passos: 1/64 do lado, menos que um lote.
const FIT_STEPS: int = 6


static func _corners_inside(layout: CityLayout, rect: Rect2) -> bool:
	for corner: int in RECT_SIDES:
		if not CityLayout.inside(layout.buildable, layout.to_world(_rect_corner(rect, corner))):
			return false
	return true


static func _rect_corner(rect: Rect2, index: int) -> Vector2:
	if index == 0:
		return rect.position
	if index == 1:
		return Vector2(rect.end.x, rect.position.y)
	if index == 2:
		return rect.end
	return Vector2(rect.position.x, rect.end.y)


static func _add_street(
	layout: CityLayout, a: Vector2, b: Vector2, width: float, rank: int
) -> void:
	if a.distance_to(b) < MIN_LENGTH:
		return
	layout.streets.append({"a": a, "b": b, "width": width, "rank": rank})


## Recorta um segmento ao anel construível e o registra só se sobrar rua dentro dele.
##
## A subdivisão corta o quadrado que envolve a muralha, então metade de cada corte nasce
## fora da cidade. Guardar o segmento inteiro tinha duas consequências: lanterna plantada
## no campo e, pior, uma ponta de rua solta lá fora que a checagem de beco sem saída
## contava como beco — a cidade reprovava por um defeito que ela não tinha.
static func _add_clipped_street(
	layout: CityLayout, a: Vector2, b: Vector2, width: float, rank: int
) -> void:
	var span: Vector2 = b - a
	var length: float = span.length()
	if length < MIN_LENGTH:
		return

	# Passo de uma célula de navegação: o ponto do corte precisa cair perto o bastante da
	# borda do anel para a checagem de beco sem saída reconhecer o encontro. Amostrando de
	# lote em lote, a ponta parava até 6 m antes da esquina e a rua era contada como beco.
	var steps: int = maxi(int(ceil(length / Params.NAV_CELL_SIZE)), RECT_SIDES)
	var first: float = -1.0
	var last: float = -1.0
	for index: int in steps + 1:
		var travel: float = float(index) / float(steps)
		if not CityLayout.inside(layout.buildable, a + span * travel):
			continue
		if first < 0.0:
			first = travel
		last = travel

	if first < 0.0 or last - first < MIN_LENGTH:
		return
	_add_street(layout, a + span * first, a + span * last, width, rank)


# --- d) Lotes -----------------------------------------------------------------


## Cada quarteirão vira uma ou duas fileiras de lotes, de testada variada.
##
## Duas fileiras quando o quarteirão é fundo: é assim que uma quadra real funciona, com os
## fundos das casas se encostando e cada fachada olhando a sua própria rua. Uma fileira só
## num quarteirão fundo deixaria um miolo morto do tamanho de uma casa.
static func split_lots(layout: CityLayout, world_seed: int) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = world_seed + SEED_LOTS
	layout.lots.clear()

	for block: Dictionary in layout.blocks:
		var rect: Rect2 = block["rect"]
		var along_x: bool = rect.size.x >= rect.size.y
		var front: float = rect.size.x if along_x else rect.size.y
		var depth: float = rect.size.y if along_x else rect.size.x

		if depth > Params.CITY_LOT_DEPTH_MAX:
			var half_depth: float = depth * HALF
			_lot_row(layout, rng, rect, along_x, front, half_depth, false)
			_lot_row(layout, rng, rect, along_x, front, half_depth, true)
			continue
		_lot_row(layout, rng, rect, along_x, front, depth, false)

	layout.report["lots"] = layout.lots.size()


## Uma fileira de lotes ao longo de um lado do quarteirão. `far` escolhe qual dos dois
## lados: a fileira olha sempre para fora do quarteirão, que é onde está a rua.
static func _lot_row(
	layout: CityLayout,
	rng: RandomNumberGenerator,
	rect: Rect2,
	along_x: bool,
	front: float,
	depth: float,
	far: bool
) -> void:
	var travelled: float = 0.0
	while travelled < front - Params.CITY_LOT_MIN:
		var width: float = minf(
			rng.randf_range(Params.CITY_LOT_MIN, Params.CITY_LOT_MAX),
			front - travelled
		)
		if width < Params.CITY_LOT_MIN:
			break
		var middle: float = travelled + width * HALF
		var local: Vector2 = Vector2.ZERO
		var facing: Vector2 = Vector2.ZERO
		if along_x:
			var y: float = rect.end.y - depth * HALF if far else rect.position.y + depth * HALF
			local = Vector2(rect.position.x + middle, y)
			facing = Vector2(0.0, 1.0) if far else Vector2(0.0, -1.0)
		else:
			var x: float = rect.end.x - depth * HALF if far else rect.position.x + depth * HALF
			local = Vector2(x, rect.position.y + middle)
			facing = Vector2(1.0, 0.0) if far else Vector2(-1.0, 0.0)

		layout.lots.append({
			"center": layout.to_world(local),
			"local": local,
			"facing": layout.dir_to_world(facing),
			"facing_local": facing,
			"width": width - Params.CITY_LOT_GAP,
			"depth": depth,
		})
		travelled += width


# --- e) Prédios (dados) -------------------------------------------------------


## Escolhe o tipo, o tamanho e a altura de cada prédio, e recusa o que não couber.
##
## Ainda não é geometria: é a lista que a validação vai cobrar e que o `CityBuilder` vai
## empilhar. Separar os dois é o que faz "nenhum prédio sobrepondo outro" ser uma checagem
## de retângulos, e não uma inspeção de malha.
static func raise_buildings(layout: CityLayout, world_seed: int) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = world_seed + SEED_BUILDINGS
	layout.buildings.clear()

	# Os tipos únicos são atribuídos primeiro, aos lotes mais perto da praça, e só depois o
	# resto é sorteado. Deixar a taverna ao acaso produziu cidades sem taverna nenhuma nas
	# três seeds de prova: com peso 6 em 92 e vinte lotes, "quase sempre aparece" é falso.
	# E uma cidade tem uma taverna e uma ferraria — não um número sorteado delas.
	var order: Array[int] = _lots_by_distance(layout)
	var reserved: Dictionary = {}
	for required: StringName in Params.CITY_INTERIOR_TYPES:
		for index: int in order:
			if reserved.has(index):
				continue
			reserved[index] = required
			break

	var placed: Array[Rect2] = []
	for index: int in order:
		var lot: Dictionary = layout.lots[index]
		var forced: StringName = reserved.get(index, &"")
		if forced == &"" and rng.randf() < Params.CITY_LOT_EMPTY_CHANCE:
			continue
		var building: Dictionary = _fit_building(layout, rng, lot, forced)
		if building.is_empty():
			continue
		var footprint: Rect2 = building["rect"]
		if _overlaps(placed, footprint):
			continue
		placed.append(footprint)
		layout.buildings.append(building)

	layout.report["buildings"] = layout.buildings.size()


## Índices dos lotes, do mais perto da praça ao mais longe.
static func _lots_by_distance(layout: CityLayout) -> Array[int]:
	var order: Array[int] = []
	for index: int in layout.lots.size():
		order.append(index)
	var plaza: Vector2 = layout.plaza
	var lots: Array[Dictionary] = layout.lots
	order.sort_custom(func(a: int, b: int) -> bool:
		return (
			Vector2(lots[a]["center"]).distance_squared_to(plaza)
			< Vector2(lots[b]["center"]).distance_squared_to(plaza)
		)
	)
	return order


## Encaixa um prédio no lote: sorteia o tipo, corta o tamanho na malha do kit e encosta a
## fachada na rua.
static func _fit_building(
	layout: CityLayout, rng: RandomNumberGenerator, lot: Dictionary, forced: StringName
) -> Dictionary:
	var spec: Dictionary = (
		_type_named(forced) if forced != &"" else _pick_type(layout, rng, lot["center"])
	)
	var module: float = Params.CITY_BUILDING_MODULE
	var step: float = Params.CITY_BUILDING_DEPTH_STEP

	var width_range: Vector2i = spec["width"]
	var depth_range: Vector2i = spec["depth"]
	var usable_width: float = float(lot["width"])
	var usable_depth: float = float(lot["depth"]) - Params.CITY_LOT_SETBACK - Params.CITY_LOT_GAP

	var modules: int = mini(
		rng.randi_range(width_range.x, width_range.y), int(floor(usable_width / module))
	)
	var depth_steps: int = mini(
		rng.randi_range(depth_range.x, depth_range.y), int(floor(usable_depth / step))
	)
	if modules < 1 or depth_steps < 1:
		return {}

	var width: float = float(modules) * module
	var depth: float = float(depth_steps) * step
	# A fachada encosta na rua; o prédio cresce para dentro do lote.
	var back: float = float(lot["depth"]) * HALF - Params.CITY_LOT_SETBACK - depth * HALF
	var local: Vector2 = Vector2(lot["local"]) + Vector2(lot["facing_local"]) * back
	var facing_local: Vector2 = lot["facing_local"]

	var along: Vector2 = facing_local.orthogonal()
	var size: Vector2 = (along * width + facing_local * depth).abs()
	var rect: Rect2 = Rect2(local - size * HALF, size)

	var floors: Vector2i = spec["floors"]
	return {
		"type": spec["name"],
		"marker": spec["marker"],
		"center": layout.to_world(local),
		"local": local,
		"rect": rect,
		"facing": layout.dir_to_world(facing_local),
		"facing_local": facing_local,
		"width": width,
		"depth": depth,
		"modules": modules,
		"depth_steps": depth_steps,
		"floors": rng.randi_range(floors.x, floors.y),
		# A porta não é o plano da parede: é onde alguém para na frente dela. Um raio de
		# agente à frente da fachada põe o ponto fora da caixa de colisão, que é o que a
		# malha de navegação precisa para tê-lo dentro dela.
		"door": layout.to_world(
			local + facing_local * (depth * HALF + Params.NAV_AGENT_RADIUS * 2.0)
		),
		"tint": _tint(rng),
	}


static func _type_named(name: StringName) -> Dictionary:
	for spec: Dictionary in Params.CITY_BUILDING_TYPES:
		if spec["name"] == name:
			return spec
	push_error("Tipo de prédio desconhecido em params.py: %s" % name)
	return Params.CITY_BUILDING_TYPES[0]


## Sorteia o tipo, com o peso corrigido pela distância à praça.
##
## `plaza_bias` é o que põe a taverna no centro e o celeiro na borda sem uma única linha de
## `if tipo == ...`: o viés multiplica o peso conforme o lote está perto ou longe.
static func _pick_type(
	layout: CityLayout, rng: RandomNumberGenerator, position: Vector2
) -> Dictionary:
	var reach: float = maxf(Params.CITY_RADIUS - Params.CITY_WALL_MARGIN, MIN_LENGTH)
	var closeness: float = clampf(1.0 - position.distance_to(layout.plaza) / reach, 0.0, 1.0)

	var total: float = 0.0
	var weights: Array[float] = []
	for spec: Dictionary in Params.CITY_BUILDING_TYPES:
		var bias: float = float(spec["plaza_bias"])
		# Viés positivo puxa para o centro, negativo para a periferia, zero é indiferente.
		var factor: float = 1.0 + bias * (closeness * 2.0 - 1.0)
		var weight: float = maxf(float(spec["weight"]) * factor, 0.0)
		weights.append(weight)
		total += weight

	var roll: float = rng.randf() * total
	for index: int in weights.size():
		roll -= weights[index]
		if roll <= 0.0:
			return Params.CITY_BUILDING_TYPES[index]
	return Params.CITY_BUILDING_TYPES[0]


## Tom por prédio. A cor multiplica o vertex color na instância, então perto de branco é
## "não mexe": a variação é de tom, não de paleta.
static func _tint(rng: RandomNumberGenerator) -> Color:
	var shift: float = rng.randf_range(-Params.CITY_TINT_JITTER, Params.CITY_TINT_JITTER)
	return Color(1.0 + shift, 1.0 + shift * HALF, 1.0 - shift * HALF, 1.0)


static func _overlaps(placed: Array[Rect2], candidate: Rect2) -> bool:
	var padded: Rect2 = candidate.grow(Params.CITY_LOT_GAP * HALF)
	for other: Rect2 in placed:
		if padded.intersects(other):
			return true
	return false


# --- Marcadores ---------------------------------------------------------------


## Nomeia os pontos de interesse que a fase 10 vai consumir.
##
## Os nomes são contrato: `praca`, `taverna`, `ferraria`, `portao`, `poco`,
## `mercado_01..05` e `casa_01..15`. Uma rotina de NPC que procure `taverna` tem de achar
## `taverna` em qualquer seed — por isso a validação reprova a cidade que não os produza.
static func place_markers(layout: CityLayout) -> void:
	layout.markers.clear()
	layout.markers[&"praca"] = layout.ground(layout.plaza)
	layout.markers[&"portao"] = layout.ground(layout.gate_point)
	layout.markers[&"poco"] = layout.ground(layout.plaza)

	for index: int in Params.CITY_PLAZA_STALLS:
		var angle: float = TAU * float(index) / float(Params.CITY_PLAZA_STALLS) + layout.angle
		var spot: Vector2 = layout.plaza + Vector2(cos(angle), sin(angle)) * Params.CITY_PLAZA_STALL_RING
		layout.markers[StringName("mercado_%02d" % (index + 1))] = layout.ground(spot)

	var houses: int = 0
	for building: Dictionary in layout.buildings:
		var marker: StringName = building["marker"]
		if marker == &"":
			continue
		if marker == &"casa":
			if houses >= HOUSE_MARKERS:
				continue
			houses += 1
			layout.markers[StringName("casa_%02d" % houses)] = layout.ground(building["door"])
			continue
		if not layout.markers.has(marker):
			layout.markers[marker] = layout.ground(building["door"])

	layout.report["markers"] = layout.markers.size()
	layout.report["house_markers"] = houses


# --- Validação ----------------------------------------------------------------


## Cobra o traçado e devolve a lista de problemas. Vazia é aprovação.
##
## O que se checa aqui é o que dá para checar sem a árvore de cena: sobreposição de prédio,
## marcadores obrigatórios, quantidade mínima e beco sem saída. Porta alcançável pela
## navegação depende do assado e fica em `tools/city.gd`, depois que a cena existe.
static func validate(layout: CityLayout) -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()

	for index: int in layout.buildings.size():
		var here: Rect2 = layout.buildings[index]["rect"]
		for other: int in range(index + 1, layout.buildings.size()):
			var there: Rect2 = layout.buildings[other]["rect"]
			if here.intersects(there):
				problems.append(
					"prédios %d (%s) e %d (%s) se sobrepõem em %s"
					% [
						index, layout.buildings[index]["type"],
						other, layout.buildings[other]["type"],
						str(here.intersection(there).size)
					]
				)

	if layout.buildings.size() < Params.CITY_MIN_BUILDINGS:
		problems.append(
			"a cidade tem %d prédios, abaixo do mínimo de %d — isso é acampamento, não cidade"
			% [layout.buildings.size(), Params.CITY_MIN_BUILDINGS]
		)

	for required: StringName in _required_markers():
		if not layout.markers.has(required):
			problems.append("marcador obrigatório ausente: %s" % required)

	var dead_ends: int = count_dead_ends(layout)
	if dead_ends > Params.CITY_MAX_DEAD_ENDS:
		problems.append(
			"%d rua(s) sem saída não intencionais, acima do limite de %d"
			% [dead_ends, Params.CITY_MAX_DEAD_ENDS]
		)
	layout.report["dead_ends"] = dead_ends
	return problems


static func _required_markers() -> Array[StringName]:
	var names: Array[StringName] = [&"praca", &"portao", &"poco", &"taverna", &"ferraria"]
	for index: int in Params.CITY_PLAZA_STALLS:
		names.append(StringName("mercado_%02d" % (index + 1)))
	for index: int in HOUSE_MARKERS:
		names.append(StringName("casa_%02d" % (index + 1)))
	return names


## Pontas de rua que não encostam em nenhuma outra rua.
##
## Uma ponta solta é um beco sem saída, e o único intencional é o portão — que morre na
## muralha de propósito. O teste é topológico e não geométrico: duas ruas se encontram se
## as pontas estão a menos de meia largura de via uma da outra, que é a folga com que um
## cruzamento de verdade se fecha.
static func count_dead_ends(layout: CityLayout) -> int:
	var tolerance: float = Params.CITY_MAIN_STREET_WIDTH
	var loose: int = 0
	for index: int in layout.streets.size():
		var street: Dictionary = layout.streets[index]
		for end_index: int in 2:
			var tip: Vector2 = street["a"] if end_index == 0 else street["b"]
			if tip.distance_to(layout.gate_point) < tolerance:
				continue  # o portão é o fim intencional da via principal
			var connected: bool = false
			for other_index: int in layout.streets.size():
				if other_index == index:
					continue
				var other: Dictionary = layout.streets[other_index]
				if CityLayout.distance_to_segment(tip, other["a"], other["b"]) < tolerance:
					connected = true
					break
			if not connected:
				loose += 1
	return loose
