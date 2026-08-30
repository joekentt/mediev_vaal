## O vale como dado: uma grade de alturas e a distância até a estrada.
##
## Tudo no vale é função disto. A malha do terreno lê a altura; a cor lê a altura e a
## inclinação; o espalhamento lê os três e mais a distância até a estrada; a navegação lê
## a malha que saiu daqui. Manter uma estrutura só, e não recalcular ruído em cada
## consumidor, é o que garante que a árvore fique *em cima* do chão e não flutuando 20 cm
## acima dele — o tipo de erro que aparece só depois de meia hora de jogo.
##
## O campo é centrado na origem: `x` e `z` vão de `-TERRAIN_SIZE/2` a `+TERRAIN_SIZE/2`.
## As arestas da grade têm `cells + 1` vértices, e a célula de índice `(i, j)` é o quadrado
## entre os vértices `(i, j)` e `(i+1, j+1)`.
class_name HeightField
extends RefCounted

## Valor guardado quando não há estrada por perto. Qualquer coisa maior que o alcance
## real da estrada serve; este é o "infinito" barato do campo.
const NO_ROAD: float = 1.0e6

var _cells: int = 0
var _stride: int = 0
var _cell_size: float = 0.0
var _size: float = 0.0
var _height: PackedFloat32Array = PackedFloat32Array()
var _road: PackedFloat32Array = PackedFloat32Array()
var _lowest: float = 0.0
var _highest: float = 0.0

## Centro da planície da cidade, em metros. Fica no campo, e não em `Params`, porque
## varia com a seed: estrada, ponto de nascimento e a fase 8 têm de concordar sobre onde
## a praça está, e ler de três lugares diferentes é como eles passariam a discordar.
var plain_center: Vector2 = Vector2.ZERO


func _init(side_cells: int, metres_per_cell: float) -> void:
	_cells = side_cells
	_stride = side_cells + 1
	_cell_size = metres_per_cell
	_size = float(side_cells) * metres_per_cell
	_height.resize(_stride * _stride)
	_road.resize(_stride * _stride)
	_road.fill(NO_ROAD)


## Células por lado. Vértices por lado são `cells() + 1`.
func cells() -> int:
	return _cells


func cell_size() -> float:
	return _cell_size


## Lado do vale em metros.
func size() -> float:
	return _size


func lowest() -> float:
	return _lowest


func highest() -> float:
	return _highest


## Amplitude real do relevo gerado, em metros. Zero num campo ainda vazio.
func span() -> float:
	return maxf(_highest - _lowest, 0.0)


## Coordenada de mundo do vértice `(ix, iz)`.
func vertex(ix: int, iz: int) -> Vector3:
	return Vector3(
		-_size * 0.5 + float(ix) * _cell_size,
		at_index(ix, iz),
		-_size * 0.5 + float(iz) * _cell_size
	)


func at_index(ix: int, iz: int) -> float:
	return _height[_offset(ix, iz)]


func set_at_index(ix: int, iz: int, value: float) -> void:
	_height[_offset(ix, iz)] = value


func road_at_index(ix: int, iz: int) -> float:
	return _road[_offset(ix, iz)]


## Guarda a menor distância vista até agora. Chamado muitas vezes pelo mesmo vértice,
## uma por amostra da curva, e é por isso que o menor vence.
func mark_road(ix: int, iz: int, distance: float) -> void:
	var offset: int = _offset(ix, iz)
	if distance < _road[offset]:
		_road[offset] = distance


## Altura interpolada num ponto qualquer do mundo. Bilinear: dentro de uma célula o valor
## acompanha o quadrilátero, não o vértice mais próximo — sem isso o pé do personagem
## pularia de degrau em degrau a cada 4 m.
func height_at(x: float, z: float) -> float:
	var fx: float = clampf((x + _size * 0.5) / _cell_size, 0.0, float(_cells))
	var fz: float = clampf((z + _size * 0.5) / _cell_size, 0.0, float(_cells))
	var ix: int = mini(int(fx), _cells - 1)
	var iz: int = mini(int(fz), _cells - 1)
	var tx: float = fx - float(ix)
	var tz: float = fz - float(iz)

	var h00: float = at_index(ix, iz)
	var h10: float = at_index(ix + 1, iz)
	var h01: float = at_index(ix, iz + 1)
	var h11: float = at_index(ix + 1, iz + 1)
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


## Distância horizontal até o eixo da estrada, em metros. `NO_ROAD` quando não há estrada
## dentro do alcance registrado.
func road_distance(x: float, z: float) -> float:
	var ix: int = _clamp_index(int(round((x + _size * 0.5) / _cell_size)))
	var iz: int = _clamp_index(int(round((z + _size * 0.5) / _cell_size)))
	return road_at_index(ix, iz)


## Normal do relevo por diferenças centrais. Serve para inclinação e orientação de props.
func normal_at(x: float, z: float) -> Vector3:
	var step: float = _cell_size
	var dx: float = height_at(x + step, z) - height_at(x - step, z)
	var dz: float = height_at(x, z + step) - height_at(x, z - step)
	return Vector3(-dx, 2.0 * step, -dz).normalized()


## Inclinação em 0..1, como seno do ângulo com a horizontal. 0 é plano, 1 é parede.
func slope_at(x: float, z: float) -> float:
	return clampf(1.0 - normal_at(x, z).y, 0.0, 1.0)


## Altitude em 0..1 dentro da amplitude real do vale. É a escala que o espalhamento e a
## cor usam — fração, e não metros, para um vale mais raso continuar tendo topo e fundo.
func altitude_at(x: float, z: float) -> float:
	var range_m: float = span()
	if range_m <= 0.0:
		return 0.0
	return clampf((height_at(x, z) - _lowest) / range_m, 0.0, 1.0)


## Ponto do mundo apoiado no relevo, com folga vertical.
func ground_point(x: float, z: float, clearance: float = 0.0) -> Vector3:
	return Vector3(x, height_at(x, z) + clearance, z)


## Recalcula mínimo e máximo. Chame depois de qualquer passada que mexa nas alturas —
## `altitude_at` mente se a amplitude ficar velha.
func refresh_bounds() -> void:
	if _height.is_empty():
		return
	_lowest = _height[0]
	_highest = _height[0]
	for value: float in _height:
		_lowest = minf(_lowest, value)
		_highest = maxf(_highest, value)


func _offset(ix: int, iz: int) -> int:
	return _clamp_index(iz) * _stride + _clamp_index(ix)


func _clamp_index(index: int) -> int:
	return clampi(index, 0, _cells)
