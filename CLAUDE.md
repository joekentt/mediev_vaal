# Mediev Vaal — guia de engenharia

RPG 3D low poly de fantasia medieval **original**. Alta fantasia clássica de tom:
florestas antigas, reinos humanos, povos das montanhas. Todo nome próprio, mapa, povo e
peça de lore é invenção deste projeto — não copiamos nomenclatura nem lore de obras
protegidas, e não "renomeamos" material existente.

---

## A regra inegociável

**Nada é criado manualmente.**

Todo modelo 3D, toda cena, todo material, todo som e todo layout de mundo é gerado por
script e regenerável com um comando. Se algo só existe porque alguém clicou no editor,
está errado — apague e escreva o gerador.

Isso vale inclusive para o que normalmente se considera "configuração":

| Artefato | Gerado por | Fonte |
| --- | --- | --- |
| `project.godot` | `tools/gen_project.py` | `tools/params.py` |
| `scripts/core/params.gd` | `tools/gen_params.py` | `tools/params.py` |
| `assets/generated/materials/*.tres` | `tools/gen_materials.py` | `tools/params.py` |
| `assets/generated/kit/*.glb` + manifesto | `tools/gen_assets.py` (Blender) | `tools/params.py` |
| `assets/generated/audio/*` | `tools/gen_audio.py` | `tools/params.py` |
| `scenes/world/main.tscn` | `tools/gen_world.py` | `tools/params.py` |
| Céu, sol, chão, colisão, câmera | `generators/world_generator.gd` | `Params` |
| Toda malha | `generators/mesh_builder.gd` | `Params` |
| `docs/assets.html` + renders | `tools/preview_assets.py` + `tools/contact_sheet.py` | manifesto do kit |
| `docs/shots/*.png` | `tools/godot_shot.gd` | `Params.SHOT_POINTS` |
| `docs/bench.json` + histórico | `tools/bench.gd` | `Params.BENCH_ROUTE` |

Consequências práticas:

- **Não mexa em Project Settings pelo editor.** O Godot reescreve `project.godot` e
  `make verify` reprova o build na hora. Mude `tools/params.py` e rode `make project`.
- **Não arraste nós para dentro de `main.tscn`.** Ela tem um `Node3D` e um script, e é
  assim que fica. Nó novo nasce em `generators/`.
- **Não importe .glb, .obj, .fbx nem textura de imagem que você não tenha gerado.**
  A fronteira é a origem, não a extensão: `assets/generated/kit/*.glb` sai de
  `tools/gen_assets.py` e volta idêntico com um comando, então é tão gerado quanto um
  `.tres`. Um `.glb` baixado, comprado ou modelado à mão no Blender, não — esse é
  exatamente o artefato que a regra existe para barrar. Textura de imagem continua
  proibida sem exceção: cor é vertex color, ponto.
- **Arquivo gerado tem cabeçalho de arquivo gerado.** Se você está editando um arquivo com
  `ARQUIVO GERADO — NÃO EDITE À MÃO` no topo, pare e vá para o gerador.
- `assets/generated/` está no `.gitignore`. É derivado: sai do git e volta com `make all`.

`make verify` cobra isso automaticamente — ele regenera tudo em memória e compara com o
que está na árvore. Deriva reprova o build.

---

## Comandos

```
make all      regenera tudo e verifica            (não precisa do Godot)
make params   scripts/core/params.gd
make project  project.godot
make materials  biblioteca de materiais do Godot
make assets     34 peças do kit em .glb + manifesto      (precisa do Blender)
make test-assets prova determinismo, paleta e orçamento  (precisa do Blender)
make audio    barramentos + tom de calibração
make world    cenas e manifesto do mundo
make verify   cobra a regra inegociável
make warnings prova que o Godot não acusa nenhum aviso (precisa do Godot)
make preview  renders do kit + docs/assets.html + capturas da cena
make bench    percorre a rota fixa e acumula docs/bench_history.csv
make clean    apaga o derivado
make regen    clean + all — prova de reprodutibilidade
```

Depois de clonar o repositório: **`make all` antes de abrir o Godot.** Sem isso a
biblioteca de materiais não existe e o jogo cai para o magenta de depuração.

`make all` inclui `make assets`, então **precisa do Blender** — pelo binário no `PATH`,
pela variável `BLENDER`, ou pelo módulo `bpy` (`pip install bpy`) no Python que roda o
`make`. Os três produzem exatamente os mesmos `.glb`; a fábrica confere isso.

```
BLENDER=/opt/blender/blender make assets
make assets PARTS="wall barrel"     # só as peças citadas, para iterar rápido
```

`make preview` e `make bench` acham o Godot pelo `PATH` ou pela variável `GODOT`:

```
GODOT=/opt/godot/godot4 make preview
```

Os dois **precisam de um display** — e note que `--headless` no Godot não significa "sem
janela", significa *sem renderizador*: com ela, captura de tela vem preta e draw call vem
zero. Por isso `preview` e `bench` chamam o Godot **sem** `--headless` e recusam rodar se
não houver renderizador, em vez de gravar números falsos no histórico. Numa sessão gráfica
funcionam direto; em CI, envolva com um display virtual:

```
xvfb-run -a -s '-screen 0 1920x1080x24' make bench
```

Sem GPU (llvmpipe) a medição fica ordens de grandeza mais lenta. Use `GODOT_TIMEOUT`
(segundos, padrão 300) para dar mais tempo, ou baixe `BENCH_SAMPLE_FRAMES` em
`tools/params.py`.

---

## Stack

| Item | Escolha |
| --- | --- |
| Engine | Godot 4.x |
| Linguagem do jogo | GDScript, sempre tipado |
| Linguagem do pipeline | Python 3 (stdlib apenas) |
| Modelagem | Blender headless, via script — nunca pela interface |
| Renderer | Forward+ |
| Anti-aliasing | MSAA 3D 2x, debanding ligado |
| Sombras | filtro *soft medium* (3), atlas direcional 4096, posicional 2048 |
| Alvo | 60 FPS a 1080p em GPU integrada moderna |
| Addons de terceiros | **nenhum** |

### Estética

Cor flat + vertex color. **Zero textura de imagem** em todo o projeto. Toda malha é
gerada com shading flat: cada triângulo tem os seus próprios vértices e uma normal de
face — é isso que dá a silhueta dura do low poly. A variação de tom vem do vertex color,
não de material novo: material novo é agrupamento perdido e draw call a mais.

Paleta em `tools/params.py`, acessível no jogo por `Params.color(&"stone")`.

---

## Estrutura

```
/tools              pipeline em Python: geradores, verificador, medição
  params.py         FONTE ÚNICA DE VERDADE — todo número do projeto
  gen_*.py          geradores (params, project, materials, assets, audio, world)
  meshlib.py        helpers de malha no Blender: primitivas, chanfro, ruído, cor
  kit_*.py          as 34 peças paramétricas (arquitetura, props, natureza)
  test_assets.py    prova determinismo, paleta e orçamento do kit
  verify.py         cobra a regra inegociável
  preview_assets.py renderiza cada peça em 4 ângulos, com figura de escala (Blender)
  contact_sheet.py  monta docs/assets.html a partir dos renders e do manifesto
  godot_shot.gd     capturas da cena de pontos nomeados (Godot)
  bench.gd          percorre a rota fixa e mede (Godot)
  preview.py        orquestra os renders, o catálogo e as capturas
  bench.py          roda bench.gd e traduz falha de ambiente
/generators         geração em GDScript (runtime)
  mesh_builder.gd   ArrayMesh flat + vertex color; valida orçamento de tris
  material_library.gd  materiais compartilhados, um por nome
  world_generator.gd   monta o mundo sob a raiz da cena
/scenes             cenas — quase vazias por construção
/scripts
  core/             autoloads, Params gerado, métricas, harness de medição
  gameplay/         regras de jogo
  ai/               comportamento de NPC
  ui/               telas e widgets
/resources          dados de design gerados (raças, diálogos, itens), versionados
/assets/generated   DERIVADO — no .gitignore, volta com `make all`
  kit/              as 34 peças em .glb + manifest.json
/docs               documentação do pipeline
  assets.html       catálogo visual do kit (derivado)
  bench_history.csv VERSIONADO: uma linha por execução de `make bench`
```

---

## Convenções

### Nomes

- **Arquivos e pastas**: `snake_case` — `world_generator.gd`, `main.tscn`.
- **Classes e nós**: `PascalCase` — `class_name MeshBuilder`, nó `GroundMesh`.
- **Funções e variáveis**: `snake_case`.
- **Constantes**: `SCREAMING_SNAKE_CASE`. Enums em `PascalCase`, valores em
  `SCREAMING_SNAKE_CASE`.
- **Membros internos**: prefixo `_`. É contrato: nada fora da classe toca neles.
- **Sinais**: fato consumado no passado (`hour_changed`) ou pedido com sufixo
  `_requested` (`dialogue_requested`).
- **Booleanos**: `is_`, `has_`, `can_`.

### GDScript sempre tipado

Tipo explícito em toda declaração, parâmetro e retorno:

```gdscript
var speed: float = 0.0
var targets: Array[Node3D] = []
func build_ground() -> StaticBody3D:
```

Nada de `var x = 0` nem de `:=`. Os avisos `untyped_declaration` e
`inferred_declaration` estão ligados no `project.godot`, e `make verify` reprova o build
por conta própria.

**O projeto abre no Godot sem um único warning** — é critério de aceite de toda fase, e
`make warnings` prova isso. O Godot só mostra aviso de GDScript no painel do editor,
então o alvo eleva temporariamente os 43 avisos ativos a erro (reescrevendo o
`project.godot` gerado e regenerando-o ao fim) para que apareçam no console. É a única
forma de checar isso em CI.

### Números mágicos: nenhum

Todo número que afeta jogo, arte ou performance vive em `tools/params.py` e chega ao
GDScript por `Params`. Fora dali, `make verify` só aceita literal numérico em duas
situações:

1. Dentro de uma declaração `const` — constante *estrutural* e nomeada
   (`const VERTS_PER_TRIANGLE: int = 3`). Não use isso para esconder um valor de
   jogabilidade: se o número afeta como o jogo se sente, parece ou roda, ele é de
   `params.py`.
2. Os triviais: `0`, `1`, `2`, `-1`, `0.0`, `0.5`, `1.0`, `2.0`.

### Sinais via EventBus, nunca caminho longo de nó

Proibido:

```gdscript
get_node("../../UI/HUD/StatusBar").update()   # quebra ao mover qualquer nó
```

Correto:

```gdscript
EventBus.toast_requested.emit("Portão trancado.")
EventBus.toast_requested.connect(_on_toast_requested)
```

Regras:

- Entre sistemas → `EventBus`.
- De pai para filho direto → `@onready var x: Type = $Filho` é aceitável.
- De filho para pai → sinal do próprio nó, nunca `get_parent()`.
- O `EventBus` **só declara sinais**. Estado global vive no `GameState`.
- Sinal novo entra em `scripts/core/event_bus.gd` com `@warning_ignore("unused_signal")`
  e um comentário `##` dizendo quando é emitido.

### Autoloads

| Autoload | Papel |
| --- | --- |
| `EventBus` | Só sinais globais. Sem estado, sem lógica. |
| `GameState` | Fase do jogo, pausa, preferências, flags de mundo. |
| `AudioManager` | Único dono de players de áudio. Pools fixos. |
| `TimeSystem` | Relógio do mundo; anuncia hora, dia e período. |

Ordem de carga: `EventBus → GameState → AudioManager → TimeSystem`. Nenhum autoload usa
`class_name` (colidiria com o próprio singleton). `Params`, `Metrics`, `MeshBuilder`,
`MaterialLibrary`, `WorldGenerator` e `SessionProbe` **não** são autoloads: são classes
globais com `class_name`.

---

## Orçamento de performance

Tetos, não metas. `make bench` reprova quem estourar.

| Métrica | Teto |
| --- | --- |
| Draw calls na cidade | 200 |
| Draw calls em campo aberto | 140 |
| NPCs ativos simultâneos | 40 |
| Materiais únicos visíveis | 16 |
| Triângulos visíveis | 150 000 |
| Frame time | 16,6 ms @ 1080p |
| Luzes com sombra | 1 direcional + 4 pontuais |
| Instâncias de MultiMesh | 20 000 |

Cada categoria de malha tem também um teto de triângulos (`Params.TRI_BUDGET`);
`MeshBuilder.commit()` reclama alto quando a malha estoura.

Como o orçamento é mantido:

- Reuso de material acima de tudo. Cor por vertex color, nunca por material novo.
- `MultiMeshInstance3D` para tudo que se repete: vegetação, cercas, telhados, pedras.
- Malhas da cidade agrupadas por quadra, não um nó por tijolo.
- Occlusion culling ligado; prédios grandes são occluders.
- LOD e `visibility_range` em qualquer coisa que apareça mais de 20 vezes.
- NPCs além do teto de ativos são simulados de forma abstrata (posição e agenda em
  dados, sem nó na árvore).
- Nada de busca ou pathfinding por frame. Rotina de NPC reage a `EventBus.hour_changed`;
  percepção roda em timer escalonado.

Camadas de física (nomeadas em `params.PHYSICS_LAYERS`, acessíveis por `Params.LAYER_*`):

| Bit | Nome | Uso |
| --- | --- | --- |
| 1 | `world` | Chão, prédios, colisão estática |
| 2 | `player` | Corpo do jogador |
| 3 | `npc` | Corpos de NPC |
| 4 | `interactable` | Portas, baús, placas |
| 5 | `trigger` | Áreas de evento, sem colisão física |

---

## Input Map

| Ação | Teclado/Mouse | Gamepad |
| --- | --- | --- |
| `move_forward` / `move_back` / `move_left` / `move_right` | W / S / A / D | Analógico esquerdo |
| `sprint` | Shift | L3 |
| `jump` | Espaço | A |
| `interact` | E | X |
| `pause` | Esc | Start |
| `camera_toggle_capture` | Tab | — |
| `camera_zoom_in` / `camera_zoom_out` | Roda do mouse | — |
| `debug_screenshot` | F12 | — |

A rotação de câmera pelo mouse **não é uma ação**: é `InputEventMouseMotion` lido pelo
controlador de câmera, multiplicado por `GameState.mouse_sensitivity`. As teclas usam
`physical_keycode`, então WASD continua em WASD num teclado AZERTY.

Para mudar um atalho: `tools/params.py` → `INPUT_MAP` → `make project`.

---

## Roteiro — fases 1 a 13

Uma fase por vez. Nada de adiantar trabalho da fase seguinte.

1. **Fundação do pipeline** ✅
   Estrutura de pastas, `params.py`/`params.gd`, `project.godot` gerado, autoloads,
   input map, Makefile, verificador da regra inegociável, estágio vazio com chão e céu.

2. **Fábrica de assets** ✅
   `tools/meshlib.py` e as 34 peças paramétricas de `kit_architecture`, `kit_props` e
   `kit_nature`, geradas em Blender headless, exportadas em `.glb` com manifesto, dentro
   dos tetos de `KIT_TRI_BUDGET` e com determinismo provado byte a byte.

3. **Olhos: catálogo e medição** ✅ *(esta etapa)*
   `make preview` renderiza o kit em `docs/assets.html` e captura a cena; `make bench`
   percorre uma rota fixa e acumula `docs/bench_history.csv`. Nenhuma fase fecha sem os
   dois.

4. **Terreno e mundo**
   Altura procedural com seed, chunks de 32 m, streaming por distância, biomas por
   paleta, água. Vegetação em `MultiMesh`.

5. **Ciclo dia/noite**
   `TimeSystem` passa a mover o sol, a cor do céu e a névoa. Iluminação por período,
   sem custo por frame além da interpolação.

6. **Jogador e câmera**
   `CharacterBody3D` gerado, caminhar/correr/pular, câmera de terceira pessoa com
   colisão contra o cenário, captura de mouse.

7. **Kit modular de arquitetura**
   Paredes, portas, janelas, telhados e escadas gerados no grid de 2 m. Prédios montados
   por composição, dentro do teto de tris por categoria.

8. **Cidade**
   Layout urbano procedural: grafo de ruas, quadras, praça, muralha. Agrupamento por
   quadra e occluders para segurar os 200 draw calls. `NavigationRegion3D` gerada.

9. **Interiores e props**
   Interiores gerados por planta, mobiliário procedural, iluminação interna dentro do
   teto de luzes com sombra.

10. **NPCs e rotinas**
   Corpos gerados por composição paramétrica, agenda diária guiada por
   `EventBus.hour_changed`, teto de 40 ativos com simulação abstrata acima disso,
   navegação pela cidade.

11. **Raças, facções e diálogo**
    `Resource`s de raça e povo gerados em `resources/`, árvores de diálogo geradas, UI de
    conversa, reputação por facção.

12. **Áudio procedural**
    Síntese de música e efeitos em `tools/gen_audio.py` — o mesmo caminho do tom de
    calibração da fase 1. Trilha adaptativa por período do dia, ambiência por bioma.

13. **Itens, combate e fechamento**
    Itens e equipamento gerados, combate corpo a corpo e à distância, IA hostil,
    salvamento/carregamento, passe de perfilamento contra todo o orçamento, build de
    release.

---

## Ao terminar qualquer fase

**Nenhuma fase está concluída sem `make preview` e `make bench` rodados, com os números
colados no commit.** Não é cerimônia. Um gerador não tem como saber se o que ele produziu
parece certo, e uma contagem de triângulos dentro do orçamento não impede uma árvore de
sair torta ou um chão de sumir por winding invertido — as duas coisas já aconteceram
neste projeto e foram encontradas *olhando*, não lendo log.

`make preview` responde "está certo?":

- `docs/assets.html` com as 34 peças em quatro ângulos e uma figura de 1,75 m ao lado,
  para o tamanho significar alguma coisa;
- `docs/shots/*.png` com a cena de verdade, dos pontos de câmera nomeados.

`make bench` responde "cabe?":

- FPS médio **e 1% low** — a média esconde engasgo, o 1% low é o que o jogador sente;
- draw calls e triângulos (pico) contra os tetos;
- frame time médio e pior frame;
- tempo de física e do passo idle;
- uma linha nova em `docs/bench_history.csv`, que é como a regressão aparece: um número
  solto não diz nada, uma coluna de números diz tudo.

Se `make bench` acusa estouro, a fase **não terminou**. Otimize ou renegocie o teto em
`tools/params.py` — explicitamente, com o diff mostrando a mudança.

**O que vai no commit.** Cole a saída de `make bench` e diga o que mudou desde a linha
anterior do histórico. Se algo piorou, diga por quê antes de alguém perguntar.

Antes de commitar, dois alvos também precisam passar:

- `make regen` — apaga tudo que é derivado e reconstrói do zero. É a prova de que o
  projeto inteiro sai de `tools/`.
- `make warnings` — a prova de que o Godot não tem nada a reclamar.
