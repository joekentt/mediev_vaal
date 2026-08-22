## Capturas do jogo rodando, de pontos de câmera nomeados.
##
##     godot --script res://tools/godot_shot.gd
##
## Abre a cena principal, deixa o mundo se gerar, e salva um PNG por ponto de
## `Params.SHOT_POINTS` em `docs/shots/`. É o par do catálogo do kit: um mostra as peças
## isoladas, este mostra o que a engine de fato desenha.
##
## **Sem `--headless`, e não é descuido.** No Godot essa flag não significa "sem janela":
## significa *sem renderizador*, e o backend nulo devolve textura vazia. Captura de tela
## com `--headless` é uma contradição. O que se quer em CI é um display virtual:
##
##     xvfb-run -a -s '-screen 0 1920x1080x24' godot --script res://tools/godot_shot.gd
##
## Se ainda assim não houver renderizador, o script sai com erro em vez de gravar quatro
## PNGs pretos que alguém levaria meia hora para desconfiar.
extends SceneTree

const SCENE_PATH: String = "res://scenes/world/main.tscn"
const SHOT_EXTENSION: String = ".png"
const HEADLESS_DISPLAY: String = "headless"
const RESULT_PREFIX: String = "MEDIEV_SHOTS "

var _root: Node3D = null
var _camera: Camera3D = null


func _initialize() -> void:
	if DisplayServer.get_name() == HEADLESS_DISPLAY:
		push_error(
			"Sem display: o renderizador nulo não produz imagem. "
			+ "Rode com xvfb-run ou numa sessão gráfica."
		)
		quit(1)
		return
	_capture.call_deferred()


## Constrói o mundo direto, sem passar por `main.tscn`: a cena principal abre no menu
## desde o MVP, e as capturas querem o vale, não a tela de título.
func _capture() -> void:
	var holder: Node3D = Node3D.new()
	root.add_child(holder)
	_root = WorldGenerator.build_stage(holder)

	# O assado de navegação e o LOD precisam de alguns quadros para assentar; sem esperar,
	# a primeira captura sairia de um mundo pela metade.
	for _frame: int in Params.BENCH_WARMUP_FRAMES:
		await process_frame

	_camera = Camera3D.new()
	_camera.fov = Params.STAGE_CAMERA_FOV
	_camera.far = Params.STAGE_CAMERA_FAR
	root.add_child(_camera)
	_camera.make_current()

	# Mesma hora e mesmo tempo em toda execução: as capturas existem para comparar com as
	# da rodada passada, e duas fotos do mesmo ponto sob céus diferentes não se comparam.
	WorldGenerator.pin_sky(_root, Params.SHOT_HOUR)

	var written: Array[String] = []
	for shot: Array in Params.SHOT_POINTS:
		var shot_name: String = String(shot[0])
		_camera.global_position = _above_ground(shot[1], Params.BENCH_CAMERA_CLEARANCE)
		_camera.look_at(_above_ground(shot[2], 0.0), Vector3.UP)

		for _frame: int in Params.SCREENSHOT_WAIT_FRAMES:
			await RenderingServer.frame_post_draw

		var path: String = "%s/%s%s" % [Params.SHOTS_DIR, shot_name, SHOT_EXTENSION]
		if _save(path):
			written.append(shot_name)
			print("  %s -> %s" % [shot_name, path])

	print(RESULT_PREFIX + JSON.stringify({"shots": written, "dir": Params.SHOTS_DIR}))
	quit(0)


## Levanta um ponto até o relevo, tratando a altura escrita em `SHOT_POINTS` como piso.
##
## Os pontos são fixos e o vale muda com a seed. Sem isto, uma seed que levantasse o
## terreno naquele ponto punha a câmera **por baixo** do chão — e o que se grava então não
## é um vale ruim, é o nada: o terreno some por backface culling, as árvores ficam boiando
## no ar e o marrom do hemisfério inferior do céu toma metade do quadro. Já aconteceu, e
## demorou uma rodada de `make preview` para alguém desconfiar de que a cena estava certa e
## a câmera é que estava enterrada.
func _above_ground(point: Vector3, clearance: float) -> Vector3:
	var field: HeightField = WorldGenerator.last_field
	if field == null:
		return point
	return Vector3(point.x, maxf(point.y, field.height_at(point.x, point.z) + clearance), point.z)


func _save(path: String) -> bool:
	var image: Image = root.get_texture().get_image()
	if image == null:
		push_error("Viewport não devolveu imagem para %s" % path)
		return false
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var error: Error = image.save_png(path)
	if error != OK:
		push_error("Falha ao salvar %s (erro %d)" % [path, error])
		return false
	return true
