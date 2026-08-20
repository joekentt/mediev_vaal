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
.PHONY: all params project materials dialogues gaits player assets test-assets characters audio world verify warnings preview anim playtest valley city population dialogue bench clean regen help

## Agendas diárias dos arquétipos em resources/schedules/.
schedules:
	@echo "== schedules =="
	@$(PY) -m tools.gen_schedules

## Árvores de conversa em resources/dialogues/.
dialogues:
	@echo "== dialogues =="
	@$(PY) -m tools.gen_dialogues

## Cena do habitante em scenes/npc/.
npc:
	@echo "== npc =="
	@$(PY) -m tools.gen_npc

## Regenera tudo e verifica. É o alvo que precisa passar antes de qualquer commit.
all: params project materials gaits schedules dialogues player npc assets characters audio world verify
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

## Cena do jogador: corpo, colisor, aplicador de povo, locomoção e braço de câmera.
player:
	@echo "== player =="
	@$(PY) -m tools.gen_player

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

## Cenas e manifesto do mundo. A seed vai para o manifesto e o jogo a lê de lá.
## Uso: make world [SEED=123]
world:
	@echo "== world =="
	@$(PY) -m tools.gen_world $(SEED)

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

## Dirige o jogador por uma sequência fixa numa arena com paredes e mede: velocidades
## atingidas, altura do salto, janela de coyote time e distância da câmera à parede.
## Precisa do Godot com display.
playtest:
	@echo "== playtest =="
	@GODOT=$(GODOT) $(PY) -m tools.playtest

## Gera o vale com duas seeds, mede a diferença entre elas e prova que os dois são
## jogáveis. Precisa do Godot com display.
valley:
	@echo "== valley =="
	@GODOT=$(GODOT) $(PY) -m tools.valley

## Gera as cidades de prova, valida cada uma e captura 6 pontos em docs/shots/city/.
## `make city SEED=123` gera só aquela seed. Precisa do Godot com display.
city:
	@echo "== city =="
	@GODOT=$(GODOT) $(PY) -m tools.city $(SEED)

## Roda 3 minutos de praça e cobra vida contínua, sem entalo e sem atravessar parede.
population:
	@echo "== population =="
	@GODOT=$(GODOT) $(PY) -m tools.population

## Abre uma conversa com um habitante em rotina e prova que a rotina volta como estava.
dialogue:
	@echo "== dialogue =="
	@GODOT=$(GODOT) $(PY) -m tools.dialogue

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
	@rm -rf docs/assets docs/shots docs/anim docs/player docs/valley docs/population docs/assets.html docs/bench.json
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
	@echo "  make player   cena do jogador em scenes/player/"
	@echo "  make assets   fábrica de peças no Blender (precisa do Blender)"
	@echo "  make test-assets prova determinismo e orçamento do kit"
	@echo "  make characters humanoides rigados (precisa do Blender)"
	@echo "  make audio    barramentos e tom de calibração"
	@echo "  make world    cenas e manifesto do mundo (SEED=123 troca o vale)"
	@echo "  make verify   cobra a regra inegociável"
	@echo "  make warnings prova que o Godot não acusa nenhum aviso (precisa do Godot)"
	@echo "  make preview  renders do kit + catálogo + capturas da cena"
	@echo "  make anim     tiras de quadros da locomoção (precisa do Godot)"
	@echo "  make playtest dirige o jogador e mede o controle (precisa do Godot)"
	@echo "  make population roda 3 min de praça e prova que a cidade tem vida (precisa do Godot)"
	@echo "  make dialogue prova que a conversa não quebra a rotina (precisa do Godot)"
	@echo "  make city     gera 3 cidades, valida e captura 6 pontos (precisa do Godot)"
	@echo "  make valley   compara dois vales por seed (precisa do Godot)"
	@echo "  make bench    mede a rota fixa e acumula docs/bench_history.csv"
	@echo "  make clean    apaga o derivado"
	@echo "  make regen    clean + all"
