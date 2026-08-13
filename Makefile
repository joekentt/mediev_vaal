# Mediev Vaal — pipeline de geração.
#
# Regra inegociável do projeto: nada é criado manualmente. Todo artefato do jogo nasce
# de um script e volta a nascer igual com um comando. Este Makefile é esse comando.
#
#   make all      regenera tudo e verifica (não precisa do Godot)
#   make preview  roda o jogo, mede e reporta os números do orçamento
#
# Configuração muda em tools/params.py, nunca no editor do Godot.

PY ?= python3
GODOT ?= godot
# Vazio de propósito: com valor, `find_blender()` trata como pedido explícito e
# reclama se não existir, em vez de procurar no PATH.
BLENDER ?=

.DEFAULT_GOAL := all
.PHONY: all params project materials gaits assets test-assets characters audio world verify warnings preview anim bench clean regen help

## Regenera tudo e verifica. É o alvo que precisa passar antes de qualquer commit.
all: params project materials gaits assets characters audio world verify
	@echo "== pronto: projeto regenerado e verificado =="

## scripts/core/params.gd a partir de tools/params.py.
params:
	@echo "== params =="
	@$(PY) -m tools.gen_params

## project.godot: renderer, MSAA, sombras, camadas de física, autoloads, input map.
project:
	@echo "== project.godot =="
	@$(PY) -m tools.gen_project

## Perfis de marcha em resources/gaits/, um por postura. Versionado: é dado de design.
gaits:
	@echo "== gaits =="
	@$(PY) -m tools.gen_gaits

## Biblioteca de materiais do Godot em assets/generated/materials/.
materials:
	@echo "== materials =="
	@$(PY) -m tools.gen_materials

## Fábrica de peças em Blender headless: 34 .glb + manifesto em assets/generated/kit/.
## Uso: make assets [PARTS="wall barrel"]
assets:
	@echo "== assets =="
	@BLENDER=$(BLENDER) $(PY) -m tools.gen_assets $(PARTS)

## Prova determinismo, propagação da paleta e cobrança do orçamento da fábrica.
test-assets:
	@echo "== test-assets =="
	@BLENDER=$(BLENDER) $(PY) -m tools.test_assets

## Humanoides rigados em assets/generated/characters/: .glb com esqueleto + manifesto.
## Uso: make characters [WHO="guarda anciao"]
characters:
	@echo "== characters =="
	@BLENDER=$(BLENDER) $(PY) -m tools.gen_characters $(WHO)

## Layout de barramentos e tom de calibração em assets/generated/audio/.
audio:
	@echo "== audio =="
	@$(PY) -m tools.gen_audio

## Cenas e manifesto do mundo.
world:
	@echo "== world =="
	@$(PY) -m tools.gen_world

## Cobra a regra inegociável: sem deriva, sem número mágico, tudo tipado.
verify:
	@echo "== verify =="
	@$(PY) -m tools.verify

## Prova que o projeto abre no Godot sem um único warning.
warnings:
	@echo "== warnings =="
	@GODOT=$(GODOT) $(PY) -m tools.check_warnings

## Os olhos: renderiza o kit, monta docs/assets.html e captura a cena no Godot.
## Precisa do Blender e, para as capturas, de display.
preview:
	@echo "== preview =="
	@GODOT=$(GODOT) BLENDER=$(BLENDER) $(PY) -m tools.preview

## Tiras de quadros da locomoção procedural em docs/anim/, e a medida de deslizamento
## do pé apoiado. Precisa do Godot com display.
anim:
	@echo "== anim =="
	@GODOT=$(GODOT) $(PY) -m tools.anim

## Percorre a rota fixa, mede, e acrescenta uma linha a docs/bench_history.csv.
## Precisa do Godot com display.
bench:
	@echo "== bench =="
	@GODOT=$(GODOT) $(PY) -m tools.bench

## Apaga tudo que é derivado. `make all` traz de volta idêntico.
clean:
	@echo "== clean =="
	@rm -rf assets/generated
	@rm -rf .godot
	@rm -rf docs/assets docs/shots docs/anim docs/assets.html docs/bench.json
	@find tools -name __pycache__ -type d -exec rm -rf {} + 2>/dev/null || true
	@echo "  derivado removido (docs/bench_history.csv é versionado e fica)"

## clean + all: a prova de que o projeto inteiro é reprodutível do zero.
regen: clean all

help:
	@echo "Mediev Vaal — alvos disponíveis:"
	@echo "  make all      regenera tudo e verifica (sem Godot)"
	@echo "  make params   scripts/core/params.gd"
	@echo "  make project  project.godot"
	@echo "  make materials biblioteca de materiais do Godot"
	@echo "  make gaits    perfis de marcha em resources/gaits/"
	@echo "  make assets   fábrica de peças no Blender (precisa do Blender)"
	@echo "  make test-assets prova determinismo e orçamento do kit"
	@echo "  make characters humanoides rigados (precisa do Blender)"
	@echo "  make audio    barramentos e tom de calibração"
	@echo "  make world    cenas e manifesto do mundo"
	@echo "  make verify   cobra a regra inegociável"
	@echo "  make warnings prova que o Godot não acusa nenhum aviso (precisa do Godot)"
	@echo "  make preview  renders do kit + catálogo + capturas da cena"
	@echo "  make anim     tiras de quadros da locomoção (precisa do Godot)"
	@echo "  make bench    mede a rota fixa e acumula docs/bench_history.csv"
	@echo "  make clean    apaga o derivado"
	@echo "  make regen    clean + all"
