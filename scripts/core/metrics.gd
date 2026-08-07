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
		# `TIME_PROCESS` é o passo *idle* inteiro da engine, não o tempo gasto em GDScript.
		# O Godot não expõe "tempo de script" como monitor — isso só sai no profiler do
		# editor, que não existe em execução headless. Chamar isto de `script_ms` daria uma
		# coluna com nome errado no histórico, que é pior que uma coluna a menos.
		"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * MS_PER_SEC,
		"physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * MS_PER_SEC,
		"memory_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / BYTES_PER_MB,
		"materials_loaded": MaterialLibrary.loaded_count(),
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


## Maior valor de uma chave na série. Pico, não média: é o pico que reprova uma cena.
static func peak(samples: Array[Dictionary], key: String) -> int:
	var highest: int = 0
	for entry: Dictionary in samples:
		highest = maxi(highest, int(entry[key]))
	return highest


## Média de uma chave na série.
static func average(samples: Array[Dictionary], key: String) -> float:
	if samples.is_empty():
		return 0.0
	var total: float = 0.0
	for entry: Dictionary in samples:
		total += float(entry[key])
	return total / float(samples.size())
