## Leitura das métricas que o orçamento de performance cobra.
##
## É a fonte dos números que `make preview` e `make bench` reportam: draw calls,
## triângulos visíveis e frame time, comparados com `Params.BUDGET`. Sem isto,
## "otimizar" seria adivinhação.
class_name Metrics
extends RefCounted

const MS_PER_SEC: float = 1000.0
const BYTES_PER_MB: float = 1048576.0


## Amostra instantânea do viewport. Chame depois de `RenderingServer.frame_post_draw`.
static func sample(viewport: Viewport) -> Dictionary:
	var rid: RID = viewport.get_viewport_rid()
	var visible: int = RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE
	return {
		"draw_calls": RenderingServer.viewport_get_render_info(
			rid, visible, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME
		),
		"objects": RenderingServer.viewport_get_render_info(
			rid, visible, RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME
		),
		"triangles": RenderingServer.viewport_get_render_info(
			rid, visible, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME
		),
		"fps": Performance.get_monitor(Performance.TIME_FPS),
		"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * MS_PER_SEC,
		"physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * MS_PER_SEC,
		"memory_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / BYTES_PER_MB,
		"materials_loaded": MaterialLibrary.loaded_count(),
	}


## Reduz uma série de amostras a picos e médias. Picos, não médias, é o que reprova
## uma cena: o pior frame é o que o jogador sente.
static func summarize(samples: Array[Dictionary]) -> Dictionary:
	if samples.is_empty():
		return {}

	var frame_ms: Array[float] = []
	for entry: Dictionary in samples:
		var fps: float = entry["fps"]
		if fps > 0.0:
			frame_ms.append(MS_PER_SEC / fps)

	var last: Dictionary = samples[samples.size() - 1]
	var average_ms: float = _average(frame_ms)
	return {
		"samples": samples.size(),
		"draw_calls": _peak(samples, "draw_calls"),
		"objects": _peak(samples, "objects"),
		"triangles": _peak(samples, "triangles"),
		"materials_loaded": int(last["materials_loaded"]),
		"frame_ms_avg": average_ms,
		"frame_ms_max": _maximum(frame_ms),
		"fps_avg": MS_PER_SEC / average_ms if average_ms > 0.0 else 0.0,
		"memory_mb": float(last["memory_mb"]),
	}


## Compara um resumo com os tetos de `Params.BUDGET`. Lista vazia = dentro do orçamento.
static func check_budget(summary: Dictionary, draw_call_key: StringName) -> Array[String]:
	var violations: Array[String] = []
	if summary.is_empty():
		return violations

	var draw_ceiling: int = Params.budget(draw_call_key)
	if int(summary["draw_calls"]) > draw_ceiling:
		violations.append("draw calls: %d > %d" % [summary["draw_calls"], draw_ceiling])

	var tri_ceiling: int = Params.budget(&"visible_tris")
	if int(summary["triangles"]) > tri_ceiling:
		violations.append("triângulos visíveis: %d > %d" % [summary["triangles"], tri_ceiling])

	if float(summary["frame_ms_avg"]) > Params.FRAME_BUDGET_MS:
		violations.append(
			"frame time médio: %.2f ms > %.2f ms"
			% [summary["frame_ms_avg"], Params.FRAME_BUDGET_MS]
		)

	var material_ceiling: int = Params.budget(&"unique_materials")
	if int(summary["materials_loaded"]) > material_ceiling:
		violations.append(
			"materiais únicos: %d > %d" % [summary["materials_loaded"], material_ceiling]
		)
	return violations


static func _peak(samples: Array[Dictionary], key: String) -> int:
	var highest: int = 0
	for entry: Dictionary in samples:
		highest = maxi(highest, int(entry[key]))
	return highest


static func _average(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var total: float = 0.0
	for value: float in values:
		total += value
	return total / float(values.size())


static func _maximum(values: Array[float]) -> float:
	var highest: float = 0.0
	for value: float in values:
		highest = maxf(highest, value)
	return highest
