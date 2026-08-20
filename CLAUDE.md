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
| `assets/generated/characters/*.glb` + manifesto | `tools/gen_characters.py` (Blender) | `tools/params.py` |
| `assets/generated/audio/*` | `tools/gen_audio.py` (NumPy) | `tools/params.py` |
| `resources/daycycle/ciclo.tres` e `resources/weather/*.tres` | `tools/gen_daycycle.py` | `tools/params.py` |
| Temas de música, por regra e modo | `tools/music.py` | `tools/params.py` |
| `resources/gaits/*.tres` | `tools/gen_gaits.py` | `tools/params.py` |
| `scenes/player/player.tscn` | `tools/gen_player.py` | `tools/params.py` |
| `scenes/world/main.tscn` + manifesto do mundo | `tools/gen_world.py` | `tools/params.py` |
| Céu, sol, chão, colisão, câmera | `generators/world_generator.gd` | `Params` |
| Relevo do vale, colisão e cor | `generators/terrain_gen.gd` | `Params` + seed |
| Estrada e terraplenagem | `generators/road_gen.gd` | `Params` + seed |
| Vegetação e rochas em `MultiMesh` | `generators/scatter_gen.gd` | `Params` + seed |
| Traçado da cidade (sítio, muralha, ruas, lotes) | `generators/city_gen.gd` | `Params` + seed |
| Prédios, props, interiores e marcadores | `generators/city_builder.gd` | `CityLayout` |
| `resources/schedules/*.tres` | `tools/gen_schedules.py` | `tools/params.py` |
| `resources/dialogues/*.tres` | `tools/gen_dialogues.py` | `tools/params.py` |
| `scenes/npc/npc.tscn` | `tools/gen_npc.py` | `tools/params.py` |
| População: corpo, rotina e posto | `generators/population_gen.gd` | `CityLayout` + seed |
| Fumaça, pássaros, folhas, cachorro, martelo | `generators/ambient_gen.gd` | `Params` + seed |
| Sol, céu, névoa e a noite acesa | `scripts/gameplay/day_night_cycle.gd` | `DayCycleProfile` |
| Chuva, nuvem e o abafamento do som | `scripts/gameplay/weather_system.gd` | `WeatherProfile` |
| Zona sonora e tema em cartaz | `scripts/gameplay/soundscape.gd` | `CityLayout` + relógio |
| Toda malha | `generators/mesh_builder.gd` | `Params` |
| `docs/assets.html` + renders | `tools/preview_assets.py` + `tools/contact_sheet.py` | manifesto do kit |
| `docs/shots/*.png` | `tools/godot_shot.gd` | `Params.SHOT_POINTS` |
| `docs/bench.json` + histórico | `tools/bench.gd` | `Params.BENCH_ROUTE` |
| `docs/anim/*.png` | `tools/anim_preview.gd` | `Params.GAIT_PROFILES` |
| `docs/player/controle.png` + medidas | `tools/playtest.gd` | `Params.PLAYER_*` |
| `docs/valley/seeds.png` + medidas | `tools/valley.gd` | `Params.VALLEY_SEEDS` |
| `docs/shots/city/*.png` + medidas | `tools/city.gd` | `Params.CITY_SEEDS` |
| Medidas de 3 min de praça | `tools/population.gd` | `Params.POPULATION_*` |
| Medidas da conversa e da rotina | `tools/dialogue.gd` | `Params.DIALOGUE_*` |
| `docs/daynight/dia.png` + medidas do ciclo | `tools/daynight.gd` | `Params.DAYNIGHT_*` |
| Medidas do crossfade de zona | `tools/soundscape.gd` | `Params.SOUNDSCAPE_*` |

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
make gaits    perfis de marcha em resources/gaits/
make schedules agendas diárias em resources/schedules/
make dialogues árvores de conversa em resources/dialogues/
make daycycle ciclo do dia em resources/daycycle/ e climas em resources/weather/
make npc      cena do habitante em scenes/npc/
make player   cena do jogador em scenes/player/
make assets     34 peças do kit em .glb + manifesto      (precisa do Blender)
make test-assets prova determinismo, paleta, orçamento e rig (precisa do Blender)
make characters 7 humanoides rigados em .glb + manifesto    (precisa do Blender)
make audio    banco sonoro inteiro em assets/generated/audio/  (precisa do NumPy)
make world    cenas e manifesto do mundo; `make world SEED=123` troca o vale
make verify   cobra a regra inegociável
make warnings prova que o Godot não acusa nenhum aviso (precisa do Godot)
make preview  renders do kit + docs/assets.html + capturas da cena
make anim     tiras de quadros da locomoção em docs/anim/  (precisa do Godot)
make playtest dirige o jogador e mede o controle          (precisa do Godot)
make valley   gera duas seeds e prova que diferem e são jogáveis (precisa do Godot)
make city     gera 3 cidades, valida e captura 6 pontos; `make city SEED=123` (precisa do Godot)
make population roda 3 min de praça e prova que a cidade tem vida (precisa do Godot)
make dialogue prova que conversar não quebra a rotina do habitante (precisa do Godot)
make daynight acelera o dia e prova que a cor não salta      (precisa do Godot)
make soundscape prova que entrar na cidade não corta o som   (precisa do Godot)
make bench    percorre a rota fixa e acumula docs/bench_history.csv
make clean    apaga o derivado
make regen    clean + all — prova de reprodutibilidade
```

Depois de clonar o repositório: **`make all` antes de abrir o Godot.** Sem isso a
biblioteca de materiais não existe e o jogo cai para o magenta de depuração.

`make all` inclui `make assets` e `make characters`, então **precisa do Blender** — pelo binário no `PATH`,
pela variável `BLENDER`, ou pelo módulo `bpy` (`pip install bpy`) no Python que roda o
`make`. Os três produzem exatamente os mesmos `.glb`; a fábrica confere isso.

```
BLENDER=/opt/blender/blender make assets
make assets PARTS="wall barrel"       # só as peças citadas, para iterar rápido
make characters WHO="guarda anciao"   # idem, para os corpos
```

A seed do vale **não mora em `params.py`**: mora no manifesto do mundo, escrita por
`make world SEED=123` e lida por `WorldGenerator.current_seed()`. Trocar de vale é uma
linha de comando, não uma edição de fonte seguida de `make params`.

`make preview`, `make anim`, `make valley`, `make city` e `make bench` acham o Godot pelo `PATH` ou pela variável
`GODOT`:

```
GODOT=/opt/godot/godot4 make preview
```

Os dois **precisam de um display** — e note que `--headless` no Godot não significa "sem
janela", significa *sem renderizador*: com ela, captura de tela vem preta e draw call vem
zero. Por isso `preview`, `anim` e `bench` chamam o Godot **sem** `--headless` e recusam rodar se
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
| Linguagem do pipeline | Python 3 (stdlib, mais NumPy só na síntese de áudio) |
| Modelagem | Blender headless, via script — nunca pela interface |
| Renderer | Forward+ |
| Anti-aliasing | MSAA 3D 2x, debanding ligado |
| Sombras | filtro *soft medium* (3), atlas direcional 4096, posicional 2048, **2 cascatas** |
| Alvo | 60 FPS a 1080p em GPU integrada moderna |
| Addons de terceiros | **nenhum** |

**A dependência de NumPy é nova e vale explicar.** Até a fase 11 o pipeline inteiro era
stdlib. Síntese de som é a primeira coisa do projeto que trabalha em vetores de milhões de
amostras: um leito de ambiência de 22 s são 970 mil amostras, e um filtro por FFT sobre
elas é uma linha em NumPy e um laço de horas em Python puro. O banco inteiro — 49 arquivos,
256 segundos de som — leva **7 segundos** para nascer. É a mesma troca que o Blender já é
para a malha: uma ferramenta especializada rodando por script, nunca pela interface.
`make audio` é o único alvo que a pede; todo o resto continua stdlib.

### Estética

Cor flat + vertex color. **Zero textura de imagem** em todo o projeto. Toda malha é
gerada com shading flat: cada triângulo tem os seus próprios vértices e uma normal de
face — é isso que dá a silhueta dura do low poly. A variação de tom vem do vertex color,
não de material novo: material novo é agrupamento perdido e draw call a mais.

Paleta em `tools/params.py`, acessível no jogo por `Params.color(&"stone")`.

### Humanoides

Mesma estética e mesmo caminho: `make characters` monta cada corpo empilhando seções
(pés, pernas, quadril, tronco, ombros, braços, mãos, pescoço, cabeça) a partir de
`CHARACTER_ROSTER`. Todas as medidas são **fração da altura**, então mudar `height`
produz alguém baixo, e não uma miniatura de alguém alto.

- **Membros são cascas contínuas**, não caixas soltas. Caixa nunca rasga porque nunca
  dobra; anel costurado reparte peso entre dois ossos e o cotovelo dobra de verdade.
- **Esqueleto Mixamo** (`Params.MIXAMO_BONES`, 21 ossos) — os nomes são contrato com o
  retargeting do Godot. As posições saem das mesmas medidas da malha.
- **Skinning é envelope + distância**: cada face nasce carimbada com a seção de corpo a
  que pertence, e a seção diz quais ossos podem disputá-la. Peso puramente por distância
  penduraria o peito no úmero. Máximo de 2 influências por vértice.
- **Rosto não tem geometria de olho.** Olho e boca são planos com vertex color afundados
  na face. A 900 triângulos, um olho modelado custaria mais que a cabeça inteira.
- **No Blender o personagem olha para +Y**, e sai olhando para -Z no Godot, que é a
  frente da engine.
- **Dois arquivos por corpo**: `<nome>.glb` é o entregável (malha + esqueleto em T-pose)
  e `<nome>_pose.glb` é prova — a mesma malha já deformada na pose de teste. É a
  geometria que o catálogo mostra e que o teste de rasgo mede.

### Locomoção

**Não há animação autoral neste projeto.** Nenhum `.anim`, nenhuma curva capturada,
nenhum clipe. O movimento nasce em runtime, de IK de duas juntas e de senos, em
`scripts/gameplay/procedural_locomotion.gd`. É escolha estética, não economia: uma malha
de 470 triângulos com silhueta dura não pede a sutileza de uma curva, pede leitura clara
a 10 m — e em troca a passada responde à velocidade real e o pé encontra o degrau que o
terreno procedural acabou de gerar.

- **O pé não é animado, é pregado.** Durante o apoio ele fica numa posição *de mundo*
  fixa e o corpo passa por ela; só no balanço viaja até o próximo apoio, escolhido por
  raycast no relevo. Deslizamento não é um defeito a combater com tuning: aqui é
  impossível por construção.
- **A cadência sai da velocidade**, pela igualdade `cadência = velocidade / (2 · passo)`.
  Um ciclo com relógio próprio patina no chão assim que o personagem acelera.
- **Camadas somam, não substituem**: quadril → coluna → pernas (IK) → braços → cabeça →
  respiração e olhar. Respiração some quando o corpo anda; o bob de câmera só existe
  correndo, e o nó apenas *publica* o deslocamento — quem move a câmera é quem tem uma.
- **Marcha é dado, não código.** `resources/gaits/*.tres` traz um `GaitProfile` por
  postura, e a postura já vem do corpo. Não existe `if raca == ...` em lugar nenhum:
  trocar o `.tres` troca a marcha.
- **Todo parâmetro é `@export`**, para tunar com o jogo rodando. O valor de fábrica sai
  de `Params`; o inspetor ajusta, mas quem manda no que nasce é o gerador.

`make anim` prova as duas coisas que só se veem olhando: grava tiras de quadros em
`docs/anim/` e **mede** o desvio do pé apoiado, reprovando o build acima de
`ANIM_FOOT_SLIDE_LIMIT`. A tira `marchas.png` põe três posturas lado a lado — se as três
silhuetas saírem iguais, o perfil não está chegando ao corpo.

`make characters` reprova o build quando um corpo estoura `TRI_BUDGET["npc"]`, quando um
vértice ganha mais de `BONE_MAX_INFLUENCES` ossos, ou quando uma aresta estica acima de
`CHARACTER_MAX_EDGE_STRETCH` na pose de teste — que é a forma executável de "nenhum
vértice se deforma de forma quebrada". `prova_baixo` e `prova_alto` existem só para o
critério de silhueta: diferem apenas em altura e ombros, e a fábrica mede se a diferença
chegou à malha.

### O vale

Um vale de 512 m nasce inteiro de um número. A ordem das camadas é o projeto:

1. **Ruído** — fractal base para as montanhas, detalhe por cima, e a altura normalizada
   elevada a `TERRAIN_VALLEY_POWER`. A potência é o que separa um vale de um mar de
   colinas: ela afunda os fundos e rarefaz os picos.
2. **Borda** — subida nos últimos `1 - TERRAIN_RIM_START` do lado, para o vale fechar em
   montanha em vez de terminar no vazio depois do último polígono.
3. **Planície** — o disco onde a fase 8 vai construir, puxado para a própria altura média.
   Ele **desliza com a seed** (`TERRAIN_PLAIN_WANDER`): parado no centro, entregaria o
   mundo como procedural na primeira vista aérea.
4. **Erosão térmica** — o que passa do ângulo de talude escorrega para o vizinho mais
   baixo. Não é hidráulica e não cava rios; corta as encostas que o ruído cru produz e que
   nenhum personagem sobe.
5. **Estrada** — e aqui **o terreno se ajusta à curva, não o contrário**. A curva amostra
   o relevo, o perfil é suavizado e limitado, e só então o terreno é cortado para encontrar
   a estrada. Traçar por cima do relevo pronto herdaria cada lombada do ruído.
6. **Espalhamento**, **navegação** e **ambiente**, que só leem o que já está pronto.

Tudo isso vive num `HeightField` só, e não é recalculado por consumidor. A árvore fica *em
cima* do chão porque lê a mesma altura que a malha usou.

Duas coisas aprendidas medindo, e que o código explica no lugar:

- **A estrada é projetada abaixo do limite que tem de cumprir.** O nivelamento trabalha no
  perfil, amostrado a cada 1,2 m; quem respeita `ROAD_MAX_SLOPE` é o terreno, que é uma
  grade de 4 m. `ROAD_GRADE_MARGIN` é a folga entre projeto e aceite. Sem ela a estrada
  cumpria o limite no papel e o estourava no relevo — medido em 0,125 contra 0,11.
- **O leito é cravado por projeção no eixo**, não copiando a altura da amostra mais
  próxima. Copiar de uma amostra discreta faz vértices vizinhos do mesmo leito herdarem
  pontos diferentes da curva, e o leito sai serrilhado.

`make valley` prova a fase em número: gera cada seed num processo do Godot só, mede a
diferença de relevo entre elas **para dentro da borda** (a borda é idêntica em qualquer
seed, e no denominador ela só dilui), confere que a mesma seed duas vezes dá diferença
zero, e cobra estrada, navegação e ponto de nascimento em cada vale.

### A cidade

Uma cidade murada nasce da mesma seed do vale, em sete etapas isoladas. Cada uma lê só o
que a anterior escreveu, e nenhuma delas cria um nó: quem instancia é `city_builder.gd`,
depois que o traçado inteiro está fechado **e validado**. É o que permite reprovar uma
cidade quebrada antes de ela custar mil instâncias, e testar a subdivisão sem abrir janela.

1. **Sítio** — sorteia candidatos na planície e pontua cada um pela inclinação média sob a
   futura muralha. Cravar o centro da planície seria mais simples e poria fileiras de casas
   em ladeira que a vista aérea não mostra.
2. **Terraplenagem** — o platô recebe a altura média medida. Sem isso o kit não fecha: as
   peças de parede são prismas retos de 3 m e não há remate para encostar em ladeira.
3. **Muralha** — polígono de 11 lados com raio e ângulo ruidosos. Anel perfeito lê como
   cerca de arena. O portão é a aresta cujo meio está mais perto do **eixo da estrada**.
4. **Ruas** — via principal curva do portão à praça, anel logo dentro da muralha, e becos
   por subdivisão recursiva com o corte perto do meio, mas nunca no meio.
5. **Lotes** — cada quarteirão vira uma ou duas fileiras de testadas de largura variada.
   Duas quando é fundo, que é como uma quadra real funciona: fundos encostados, cada
   fachada olhando a sua própria rua.
6. **Prédios** — o lote empilha peças do kit conforme o tipo. Taverna e ferraria são
   atribuídas primeiro, aos lotes mais perto da praça; o resto é sorteado com o peso
   corrigido pela distância ao centro, e é assim que o celeiro vai para a periferia sem um
   único `if tipo == ...`.
7. **Props e interiores** — poço e bancas na praça, lanternas nas ruas, cercas e varais nos
   becos; dois interiores de verdade e cartas escuras atrás das outras janelas.

A ordem com a estrada é o que mais custou a acertar, e o código explica no lugar:

- **A cidade terraplena antes de a estrada ser traçada.** Ao contrário, o platô desceria
  sobre um leito já cravado.
- **A estrada para de cravar o terreno na muralha.** Ela desce da borda do vale com
  inclinação limitada, então chega à planície ainda alta; como aqui o terreno é que se
  ajusta à estrada, ela erguia o leito para a própria cota — e o leito passava por dentro
  da cidade. Medido na seed 123: platô a 19,1 m e uma crista de estrada de 32,8 m
  atravessando a praça. Dentro da muralha quem manda é a via principal, que é traçado e
  não terraplenagem.
- **O portão lê a curva da estrada, não o campo de distância.** Consequência do item
  anterior: dentro da muralha o campo devolve "sem estrada", todas as arestas empatam e o
  portão sai nas costas da cidade. O relatório entregou o defeito com um `portão a
  1000000,0 m da estrada`.

Otimização é parte da geração, não um passe depois:

- **Peça igual vira instância.** Toda cópia de `wall` da cidade mora num `MultiMesh` só, e
  o tom de cada prédio viaja na instância — tom não custa material.
- **Colisão é sempre caixa.** Um prédio é uma caixa; um prédio com interior de verdade são
  quatro, uma por parede, e a da frente fica de fora para não fechar a porta.
- **Muralha e fachada grande são occluder**, por corte de área: uma casa de 4 m esconde
  pouco e custa um teste.
- **Piso só onde é visto.** `floor_tile` custa 48 triângulos, mais que as duas paredes que
  o cercam. Ladrilhar todos os prédios gastava um terço do orçamento em chão que ninguém
  pisa.

`make city` prova a fase em número, e `make city SEED=123` gera uma cidade só.

### A vida

Vinte habitantes com rotina, e centenas de coisas se mexendo que não têm rotina nenhuma.
A divisão é deliberada: uma cidade viva precisa de movimento contínuo no campo de visão o
tempo todo, e movimento que custa uma decisão por quadro não escala para "o tempo todo".

**O habitante** é o corpo da fase 6 inteiro — `RaceApplier` veste a malha,
`ProceduralLocomotion` move as pernas por IK — mais uma máquina de seis estados (IDLE,
WALK_TO, WORK, SOCIALIZE, SLEEP, REACT) e uma `NPCSchedule`.

- **A agenda fala em nomes de marcador, nunca em coordenadas.** `praca`, `poco`,
  `taverna`, `casa`, `trabalho`. `population_gen.gd` resolve os nomes contra os `Marker3D`
  da fase 8 e troca `casa` pela casa daquele habitante. É isso que faz três rotinas
  servirem a vinte pessoas em qualquer seed de cidade.
- **A hora chega por sinal.** `EventBus.hour_changed` dispara 24 vezes por dia; vinte NPCs
  perguntando as horas a 60 Hz seriam 1200 consultas por segundo para a mesma resposta.
- **Casa e trabalho são coerentes.** Sortear os dois independentemente daria a metade da
  cidade atravessando a praça oito vezes por dia — movimento que parece vida por dez
  segundos e vira ruído depois disso.
- **Todo alvo passa pela malha de navegação antes de virar destino**, e não basta ser
  navegável: tem de ser *alcançável*. O chão da taverna é uma ilha de navmesh ligada ao
  resto por uma porta de 1,2 m que o raio de agente de 0,5 m nem sempre atravessa.

**O diretor** (`npc_director.gd`) decide quem custa física. Dentro de
`NPC_ACTIVE_RADIUS` o habitante é um `CharacterBody3D` com navegação; fora dele é uma
posição avançando sobre a rota que já tinha, sem malha e sem física. A fronteira tem
histerese, a reavaliação é por temporizador e não por quadro, e o teto de
`BUDGET["active_npcs"]` vence o raio quando os dois discordam.

**A vida ambiente** não tem IA nenhuma: fumaça e folhas são `GPUParticles3D`, os pássaros
são um `MultiMesh` por bando com as transformações reescritas por quadro, o vento do varal
é um shader de vértice sobre o `MultiMesh` de panos que a fase 8 já montava, e o cachorro
percorre uma rota fixa. Só o martelo da ferraria lê alguma coisa do mundo, e lê uma só: a
fase de trabalho do artesão que está de pé na frente dela.

Três coisas que só apareceram medindo, e que o código explica no lugar:

- **A malha de navegação flutua sobre o chão.** O Recast rasteriza em células de
  `NAV_CELL_HEIGHT` e o polígono fica acima do relevo — medido em 0,7 m. O
  `NavigationAgent3D` decide que chegou a um ponto do caminho por distância em **três**
  dimensões, então o primeiro ponto, que fica em cima do agente e 0,7 m mais alto, nunca é
  considerado alcançado: o agente devolve esse mesmo ponto para sempre. Vinte habitantes
  passaram três minutos imóveis em `WALK_TO` por causa disso. A correção é ler o caminho e
  avançar o índice por distância **em planta**.
- **O identificador de um autoload não existe em script de ferramenta.** `EventBus` e
  `TimeSystem` são resolvidos por `/root/...` dentro do habitante, e não pelo identificador
  global, porque `bench.gd`, `city.gd` e `population.gd` alcançam `WorldGenerator`, que
  agora alcança o habitante — e o identificador global quebrava a compilação de toda a
  medição do projeto. A cena do jogador escapa disso por ser carregada em runtime.
- **O mapa de navegação padrão tem de nascer com a mesma célula da região.** Sem
  `navigation/3d/default_cell_size` no `project.godot`, o Godot recusa a região inteira e a
  cidade fica com navegação vazia.

`make population` prova a fase em número: três minutos de praça sem renderizador, medindo
quanta gente se move em cada janela, quanto do percurso de cada um cai em terreno novo,
quantos entalos houve e quantas amostras caíram dentro de uma parede.

### A conversa

Falar com alguém atravessa seis peças, e nenhuma delas conhece mais de uma vizinha. É o
que faz a sétima conversa custar um arquivo `.tres` e zero linha de código.

- **`Interactable` é a interface inteira**: um verbo, um prompt e quem é o dono. Com
  árvore, interagir emite `dialogue_requested`; sem ela, só anuncia `interacted` — é o que
  deixa um baú da fase 9 existir sem inventar uma conversa de uma linha para ele. É
  `Area3D` porque o alvo é escolhido por sobreposição: varrer a cena atrás de nós de um
  tipo custaria uma busca por quadro para responder o que a física já responde de graça.
- **O alvo é o mais central na tela, não o mais próximo.** Numa praça com três habitantes
  encostados, distância escolhe o que o ombro do jogador está tapando. A pontuação mistura
  centralidade e proximidade, e recusa qualquer coisa fora do cone de
  `INTERACT_MAX_ANGLE_DEG` — sem esse corte, `unproject_position` devolve o centro da tela
  para um alvo **atrás** da câmera, e o prompt oferece conversar com quem ficou para trás.
- **`DialogueTree` não conhece o `GameState`.** As condições são avaliadas contra um
  dicionário de contexto que o chamador monta. Não é purismo: identificador de autoload não
  existe quando um script de ferramenta compila — a fase 10 já pagou esse preço — e com
  contexto explícito a prova percorre uma árvore inteira sem abrir o jogo.
- **A rotina volta exatamente onde parou.** `pause_routine()` guarda estado, tarefa,
  destino, posto e temporizador; `resume_routine()` devolve os cinco. Só o caminho se
  refaz, e não por escolha: o agente descartou o dele enquanto ninguém andava. Recalcular a
  agenda na saída faria um habitante a meio caminho da taverna recomeçar da casa dele, e o
  jogador veria a conversa apagar o que ele estava fazendo.
- **A voz é sintetizada, e o pitch sai do id.** Sílabas curtas com pitch escorregando
  dentro de cada uma, perfil por postura do corpo — a mesma chave que a marcha usa, então
  um corpo novo herda voz sem tabela nova. O pitch vem do hash do nome do habitante: um
  sorteio por fala soaria aleatório, não soaria errado, e é o defeito que ouvido nenhum
  pega.
- **A UI nasce em código, inclusive o painel.** Uma cena de UI montada no editor seria o
  primeiro arquivo do repositório que ninguém revisa, e o próximo tamanho de fonte não
  voltaria para `params.py`.

Duas coisas que a ordem de execução ensinou:

- **A rotina volta antes de a câmera soltar.** Ao contrário, há um quadro em que o
  habitante já está andando e a câmera ainda está no ombro dele, e o corte fica visível.
- **A árvore é carregada pelo nome, e o nome é o caminho.** Sem registro, sem `match`, sem
  lista para atualizar. `make dialogue` prova isso abrindo `guarda_portao`, que é a árvore
  que caminho de código nenhum referencia: se um registro escondido tivesse aparecido em
  algum lugar do projeto, é ela que ficaria muda.

`make dialogue` prova a fase em número: pega um habitante **em rotina** — não um parado,
que não provaria retomada nenhuma —, grava estado e destino, conversa com ele, e cobra que
os dois voltem e que ele volte a andar. De quebra percorre a máquina de condições na ordem
em que uma partida a percorreria: uma escolha trancada por flag abre depois que outra
conversa acende a flag, e uma trancada por reputação abre depois que a escolha do ferreiro
paga os pontos.

### O dia

Um dia dura 24 minutos reais e cabe inteiro numa tabela de onze chaves. A decisão de
projeto está no formato: **as chaves são pontos de gradiente, não estados**. O que o
jogador vê às 6h32 não está escrito em lugar nenhum — é a interpolação entre a chave das
5h30 e a das 7h. Não existe transição para escrever, e transição escrita à mão é
exatamente onde nasce o salto de cor.

`resources/daycycle/ciclo.tres` traz quatro `Gradient` de cor (zênite, horizonte, névoa,
sol) e seis `Curve` de número (energia, densidade de névoa, ambiente, elevação, azimute e
*luz*). `DayNightCycle` amostra os dez pela fração do dia e escreve em `DirectionalLight3D`
e em `Environment`. Cinco períodos — madrugada, amanhecer, dia, entardecer, noite — chegam
por `EventBus.day_period_changed`; a madrugada é um período separado da noite de propósito,
porque o vale às 2h e o vale às 21h têm luz parecida e cidade diferente.

Quatro coisas que o código explica no lugar, e que a medição encontrou:

- **O sol nunca se apaga: à noite ele é a lua.** O orçamento tem uma luz direcional. Apagar
  a única deixaria a cidade sem sombra nenhuma, e sem sombra a noite lê como cinza chapado
  em cima de tudo. A tabela nunca põe a elevação abaixo do horizonte, e o gerador reprova
  quem tentar.
- **Nada é aplicado por quadro.** O ciclo só reescreve luz e cor quando a fração do dia
  andou mais que `DAY_CYCLE_MIN_STEP` — medido, uma vez a cada 30 quadros na velocidade
  normal. Entre elas o nó custa uma subtração. O degrau que essa economia introduz é o
  **único** degrau possível no ciclo, e é o que `make daynight` mede.
- **A noite acende um material, não mil janelas.** Toda carta de interior falso da cidade
  divide um `StandardMaterial3D` emissivo; subir a emissão dele acende a cidade inteira
  numa atribuição. O mesmo material serve o vidro dos lampiões, e só os seis mais próximos
  da praça ganham `OmniLight3D` — sem sombra, que é atlas e o orçamento tem quatro.
- **O clima multiplica, nunca substitui.** `WeatherProfile` só tem fatores: nublado ao
  meio-dia continua sendo meio-dia com um terço menos de sol. Um clima que escrevesse "o
  céu é cinza" apagaria o ciclo, e o dia pararia de andar até parar de chover.

A chuva acompanha a câmera numa caixa de 26 m com novecentas gotas — chover no vale
inteiro simularia milhões de gotas para que 99,99% delas caíssem onde ninguém está —, deixa
a névoa três vezes mais densa e fecha um passa-baixa em 1,4 kHz nos barramentos de mundo.

E uma coisa que só a medida encontrou: **a virada do tempo tem teto de avanço por quadro**.
Um quadro longo — um carregamento, o assado da navegação terminando — chega com um `delta`
de vários segundos, e sem teto ele completava os doze segundos da transição de uma vez. O
céu saltava de ensolarado para chuva num quadro só, e `make daynight` entregou o defeito
como 0,78 de energia de sol e 0,18 de cor num quadro.

`make daynight` prova a fase em número, e a tira `docs/daynight/dia.png` mostra o dia
inteiro em cores lado a lado — sem renderizador, desenhada com os mesmos valores medidos.

### O som

Todo som do jogo nasce em `tools/gen_audio.py`, em NumPy, e sai em `.wav`. Nada é baixado,
gravado ou comprado: é a regra inegociável aplicada ao que se ouve. São 49 arquivos —
passos por superfície, vento em camadas, chilro por FM, martelo, porta, água do poço,
murmúrio, o banco de sílabas de cada raça, três leitos de ambiência, chuva e três temas.

O que separa cada som do vizinho é físico, não é volume:

- **Passo**: terra é grave e morre em 55 ms, pedra é aguda e seca, madeira tem uma
  ressonância no meio que continua soando depois do golpe. Três variantes de cada — o mesmo
  passo repetido lê como metrônomo.
- **Vento**: três camadas com rajadas de frequências primas entre si. Uma camada só, por
  mais filtrada que seja, tem período audível.
- **Porta**: um trem de pulsos que desacelera passando por uma ressonância **parada**, que
  é literalmente o que uma dobradiça faz. Filtro que varia no tempo não é preciso; quem
  varia é a fonte. É a mesma razão pela qual todo filtro do módulo é por FFT e não por
  recursão: multiplicar um espectro é vetorizado, um biquad é um laço de 44 100 iterações
  por segundo de som.
- **Voz**: fonte e filtro, como a voz humana. Um trem de pulsos faz a glote e dois
  formantes dizem que vogal é — e é mover F1 e F2 que muda **quem** está falando sem mexer
  na altura da voz. Por isso a tabela de raças é uma tabela de formantes.
- **Música**: um modo, uma tabela de transição entre graus e três regras de melodia (grau
  de acorde no tempo forte, passo antes de salto, salto resolve por passo contrário). Não
  há partitura em lugar nenhum. Cada tema fecha o laço somando a cauda de volta no começo,
  que é a única das três formas de fechar um laço que não se ouve.

E a música se prova sozinha: `make audio` mede os oito picos mais fortes do espectro de
cada tema e reprova a geração se algum cair fora do modo declarado ou desafinado acima de
`MUSIC_TUNING_CENTS`. É a diferença entre "gerou som" e "gerou música", e é a única forma
de pegar um erro de oitava ou uma razão de harmônico trocada sem ouvir — nada disso muda o
número de notas nem a duração, muda só onde as notas caem. Medido: 1,5 a 1,9 centésimos nos
três temas, tudo dentro da escala.

Três coisas que a medição do som ensinou, e que agora `make soundscape` vigia:

- **O padrão de import de .wav é com perda.** Godot 4.3+ recomprime todo .wav em QOA. Num
  projeto que sintetiza cada byte e recusa textura de imagem, deixar isso passar seria a
  transformação escondida que a regra inegociável existe para barrar — e tem consequência
  prática: a voz costura uma fala concatenando bytes de sílabas, e bytes de QOA não se
  concatenam. A voz saía muda, e foi assim que o defeito apareceu. O preset vive em
  `[importer_defaults]` no `project.godot` gerado, uma linha para o banco inteiro.
- **Leito e trilha precisam ser marcados para repetir.** Um leito de 22 s que toca uma vez
  deixa a floresta em silêncio no vigésimo terceiro segundo — o defeito mais fácil de não
  notar num teste curto e o mais óbvio de notar jogando. A marca é posta no carregamento e
  não no import, porque o mesmo importador serve as sílabas e os passos, e um passo em
  laço é um pé arrastando para sempre.
- **O `AudioManager` é dono dos leitos, não inquilino.** Com dois players de ambiência, o
  leito que sai de cena a cada troca perde a última referência e é descarregado — e o
  próximo `load` traz uma cópia nova do disco, sem a marca de laço. Andar para dentro e
  para fora da cidade três vezes deixava um dos três leitos sem repetir. Agora eles ficam
  num cache que nunca solta, o que de quebra tira a leitura de disco do meio da travessia:
  entrar na cidade não é o momento de descomprimir vinte segundos de áudio.

**As zonas são a peça nova do `AudioManager`.** Floresta, cidade e interior têm cada uma o
seu leito, e trocar de zona é um crossfade de dois segundos entre dois players. O crossfade
é de **potência constante**, e essa é a decisão de peso: escrever as duas rampas em reta é
o que sai naturalmente, e afunda o volume percebido para 71% no meio da troca — o "corte"
que o critério da fase proíbe. Com seno e cosseno a soma dos quadrados é 1 do começo ao
fim. `make soundscape` mede exatamente isso, e o teto de 0,72 está entre as duas
implementações de propósito: reprova a ingênua e aprova a certa.

`Soundscape` decide a zona a 4 Hz, com histerese de 6 m na muralha — sem ela, parar em cima
da linha alterna o leito quatro vezes por segundo e o crossfade de dois segundos nunca
chega ao fim. O interior é medido contra a caixa dos prédios que **têm** interior de
verdade: os outros são fachada com carta escura atrás da janela, e abafar o som ao encostar
neles seria abafar por causa de um cômodo que não existe.

---

## Estrutura

```
/tools              pipeline em Python: geradores, verificador, medição
  params.py         FONTE ÚNICA DE VERDADE — todo número do projeto
  gen_*.py          geradores (params, project, materials, assets, audio, world)
  meshlib.py        helpers de malha no Blender: primitivas, chanfro, ruído, cor
  kit_*.py          as 34 peças paramétricas (arquitetura, props, natureza)
  gen_characters.py humanoides rigados: corpo, esqueleto Mixamo, skinning e prova de pose
  gen_gaits.py      perfis de marcha por postura, em resources/gaits/
  gen_player.py     scenes/player/player.tscn: corpo, colisor, locomoção e câmera
  playtest.gd       dirige o jogador pelo input map e mede o controle (Godot)
  playtest.py       roda playtest.gd e cobra os critérios de aceite do controle
  anim_preview.gd   tiras de quadros da locomoção + medida de deslizamento (Godot)
  anim.py           roda anim_preview.gd e reprova o build se o pé patinar
  test_assets.py    prova determinismo, paleta, orçamento e rig
  verify.py         cobra a regra inegociável
  preview_assets.py renderiza cada peça em 4 ângulos, com figura de escala (Blender)
  contact_sheet.py  monta docs/assets.html a partir dos renders e do manifesto
  godot_shot.gd     capturas da cena de pontos nomeados (Godot)
  bench.gd          percorre a rota fixa e mede (Godot)
  preview.py        orquestra os renders, o catálogo e as capturas
  valley.gd         gera cada seed num processo só e mede o vale (Godot)
  valley.py         roda valley.gd e cobra os critérios de aceite do vale
  city.gd           gera cada cidade, valida a navegação e captura 6 pontos (Godot)
  city.py           roda city.gd e cobra os critérios de aceite da cidade
  population.gd     roda 3 min de praça e mede vida, entalo e parede (Godot)
  population.py     roda population.gd e cobra os critérios de aceite da vida
  gen_dialogues.py  árvores de conversa em resources/dialogues/, com auditoria do grafo
  gen_daycycle.py   o dia em gradientes e curvas, e os três climas, em .tres
  dsp.py            síntese em NumPy: osciladores, envelopes, filtros por FFT, mistura
  music.py          modo, progressão por regras e três timbres — a trilha nasce aqui
  imagelib.py       escrita de PNG em stdlib, para a tira do dia
  daynight.gd       acelera o dia, mede o salto de cor e desenha a tira (Godot)
  daynight.py       roda daynight.gd e cobra os critérios de aceite do ciclo
  soundscape.gd     atravessa a fronteira da cidade e mede o crossfade (Godot)
  soundscape.py     roda soundscape.gd e cobra os critérios de aceite do som
  dialogue.gd       conversa com um habitante em rotina e mede a retomada (Godot)
  dialogue.py       roda dialogue.gd e cobra os critérios de aceite da conversa
  bench.py          roda bench.gd e traduz falha de ambiente
/generators         geração em GDScript (runtime)
  mesh_builder.gd   ArrayMesh flat + vertex color; valida orçamento de tris
  material_library.gd  materiais compartilhados, um por nome
  height_field.gd   o vale como dado: alturas e distância até a estrada
  terrain_gen.gd    ruído em camadas, borda, planície, erosão e malha colorida
  road_gen.gd       traçado por spline, nivelamento e terraplenagem do leito
  scatter_gen.gd    vegetação e rochas em MultiMesh, com máscara e 3 LODs
  city_layout.gd    a cidade como dado: sítio, muralha, ruas, lotes, prédios, marcadores
  city_gen.gd       o traçado em sete etapas isoladas, sem tocar na árvore de cena
  city_builder.gd   empilha o kit, agrupa em MultiMesh, colide por caixa e ocluis
  population_gen.gd resolve corpo, rotina, casa e posto de cada habitante
  ambient_gen.gd    fumaça, pássaros, folhas, varal ao vento, cachorro e martelo
  world_generator.gd   monta o mundo sob a raiz da cena
/scenes             cenas — quase vazias por construção
/scripts
  core/             autoloads, Params gerado, métricas, harness de medição
  gameplay/         regras de jogo
    procedural_locomotion.gd  marcha, corrida, salto e camadas aditivas por IK
    two_bone_ik.gd            solver analítico de duas juntas
    gait_profile.gd           Resource de marcha, um por postura
    player_controller.gd      máquina de estados, peso, coyote time e buffer de salto
    third_person_camera.gd    braço de mola com colisão, atraso, FOV e tranco de pouso
    race_applier.gd           veste um corpo: malha, marcha e dimensão do colisor
    npc_controller.gd         agenda, navegação, percepção e simulação barata
    npc_director.gd           quem custa física e quem custa quase nada
    npc_schedule.gd           Resource de agenda, um por arquétipo
    ambient_life.gd           pássaros, cachorro e martelo, sem IA
    interactable.gd           a interface: um verbo, um prompt e quem é o dono
    interaction_sensor.gd     escolhe o alvo por centralidade na tela
    dialogue_tree.gd          Resource de conversa: nós, condições e escolhas
    dialogue_runner.gd        costura árvore, NPC, câmera, voz e GameState
    procedural_voice.gd       costura sílabas do banco gerado; pitch estável por id
    day_cycle_profile.gd      Resource do dia: quatro gradientes e seis curvas
    day_night_cycle.gd        move sol, céu, névoa e a luz de dentro das casas
    weather_profile.gd        Resource de clima: só multiplicadores, nunca valor absoluto
    weather_system.gd         chuva na câmera, nuvem na névoa e passa-baixa no som
    soundscape.gd             que zona sonora é esta, e que tema toca nela
  ai/               comportamento de NPC
  ui/               telas e widgets, construídos em código
    context_prompt.gd         a linha do rodapé que aparece e some
    dialogue_screen.gd        painel, fala revelada e escolhas
/resources          dados de design gerados (raças, diálogos, itens), versionados
  gaits/            perfis de marcha por postura (gerado, versionado)
  schedules/        agendas diárias por arquétipo (gerado, versionado)
  dialogues/        árvores de conversa (gerado, versionado)
  daycycle/         o dia em gradientes e curvas (gerado, versionado)
  weather/          os três climas, em multiplicadores (gerado, versionado)
/assets/generated   DERIVADO — no .gitignore, volta com `make all`
  kit/              as 34 peças em .glb + manifest.json
  characters/       os 7 humanoides em .glb com esqueleto + manifest.json
  audio/            49 .wav sintetizados + manifest.json: efeitos, vozes, leitos, música
/docs               documentação do pipeline
  assets.html       catálogo visual do kit (derivado)
  anim/             tiras de quadros da locomoção (derivado)
  player/           tira do controle do jogador (derivado)
  valley/           vista aérea de cada seed, uma sobre a outra (derivado)
  shots/city/       seis pontos da cidade (derivado)
  daynight/dia.png  o dia inteiro em cores, faixa por faixa (derivado)
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
| Draw calls na cidade | 240 |
| Draw calls em campo aberto | 150 |
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
- LOD e `visibility_range` em qualquer coisa que apareça mais de 20 vezes. A partir da
  segunda faixa, **todos os tipos dividem um `MultiMesh` só**: o proxy é um prisma unitário
  esticado e tingido por instância, então uma faixa custa um draw call por bloco em vez de
  um por tipo por bloco.
- **Cascata de sombra é draw call.** Cada uma redesenha todo caster dentro de
  `SHADOW_MAX_DISTANCE`. Foi o que estourou o orçamento do vale — 141 draw calls com as 4
  cascatas padrão, 90 com 2 — e não a geometria, que era onde eu estava procurando.
- **Um corpo animado custa três draw calls, não um**: a cor mais uma passada por cascata.
  Vinte habitantes custam sessenta, e é por isso que a sombra deles é cortada além de
  `NPC_SHADOW_RADIUS`. Fumaça, cachorro e martelo não projetam sombra nenhuma.
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
| `dialogue_choice_1` … `dialogue_choice_4` | 1 / 2 / 3 / 4 | Direcional |
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

3. **Olhos: catálogo e medição** ✅
   `make preview` renderiza o kit em `docs/assets.html` e captura a cena; `make bench`
   percorre uma rota fixa e acumula `docs/bench_history.csv`. Nenhuma fase fecha sem os
   dois.

4. **Terreno e mundo** ✅
   O vale de 512 m inteiro por seed: ruído em camadas com borda, planície e erosão
   térmica em `terrain_gen.gd`; estrada por spline que nivela o terreno sob si em
   `road_gen.gd`; vegetação e rochas em `MultiMesh` com máscara de estrada e três LODs
   com fade em `scatter_gen.gd`; céu procedural, névoa e tonemap Filmic; navegação
   assada ao fim da geração. `make world SEED=123` troca o vale e `make valley` prova
   que duas seeds dão vales diferentes e jogáveis. *Água ficou de fora — não há bioma
   que a peça ainda, e ela entra com os biomas.*

5. **Ciclo dia/noite** ✅
   Um dia de 24 minutos reais, exportável, com cinco períodos anunciados por sinal.
   `DayCycleProfile` em `resources/daycycle/`: quatro gradientes de cor e seis curvas de
   número, amostrados pela fração do dia — não há estado por período, só interpolação.
   `DayNightCycle` move sol, céu, névoa e ambiente, e reaplica uma vez a cada 30 quadros
   na velocidade normal. À noite as janelas acendem por emissão de material e seis
   lampiões da praça ganham luz pontual; a praça esvazia porque a agenda da fase 10 manda
   todo mundo para casa. Mais três climas em `resources/weather/`, que **multiplicam** o
   que o ciclo decidiu: chuva de partículas acompanhando a câmera, névoa mais densa e
   passa-baixa nos barramentos de mundo. `make daynight` mede.

6. **Jogador e câmera** ✅
   `scenes/player/player.tscn` gerada por `tools/gen_player.py`: `CharacterBody3D`,
   cápsula, `RaceApplier`, locomoção procedural e braço de câmera. Máquina de estados
   (IDLE, WALK, RUN, JUMP, FALL, INTERACT), aceleração e desaceleração separadas, coyote
   time e buffer de salto, câmera de terceira pessoa com `SpringArm3D`, atraso posicional,
   FOV de corrida e tranco de pouso. `make playtest` dirige tudo pelo input map e mede.

7. **Kit modular de arquitetura**
   Paredes, portas, janelas, telhados e escadas gerados no grid de 2 m. Prédios montados
   por composição, dentro do teto de tris por categoria.

8. **Cidade** ✅ *(esta etapa, fora de ordem e a pedido explícito)*
   Layout urbano procedural em sete etapas: sítio medido, muralha irregular com portão
   voltado para a estrada, rede de ruas por subdivisão, lotes de testada variada, prédios
   empilhados do kit por tipo, props e dois interiores reais. `MultiMesh` por peça,
   colisão por caixa, occluders por área, `Marker3D` nomeados para a fase 10 e validação
   que reprova sobreposição, porta inalcançável e beco sem saída. `make city SEED=123`.
   *As fases 5 e 7 continuam abertas: a cidade foi construída sobre o kit de 34 peças da
   fase 2, e não sobre um kit modular ampliado.*

9. **Interiores e props**
   Interiores gerados por planta, mobiliário procedural, iluminação interna dentro do
   teto de luzes com sombra.

10. **NPCs e rotinas** ✅ *(esta etapa, fora de ordem e a pedido explícito)*
   Vinte habitantes com agenda diária guiada por `EventBus.hour_changed`, três arquétipos
   em `resources/schedules/`, casa e posto coerentes, navegação pela cidade, percepção por
   `Area3D` com olhar e fala flutuante, e simulação barata acima de `NPC_ACTIVE_RADIUS`
   com teto de 40 corpos com física. Mais a vida ambiente sem IA: fumaça, pássaros,
   folhas, varal ao vento, cachorro em ronda e o martelo da ferraria no compasso do
   artesão. `make population` mede três minutos de praça.
   *As fases 5, 7 e 9 continuam abertas.*

11. **Raças, facções e diálogo** ✅ *(esta etapa, fora de ordem e a pedido explícito)*
    `Interactable` com alvo escolhido por centralidade na tela, prompt de contexto e tela
    de conversa construídos em código, `DialogueTree` em `resources/dialogues/` com
    condições de flag, raça e reputação e até quatro escolhas por nó, enquadramento em
    ombro durante a fala, rotina do habitante pausada e devolvida onde parou, voz
    sintetizada com pitch estável por id e silenciável, e reputação por facção no
    `GameState`. `make dialogue` mede a retomada da rotina.
    *As fases 5, 7 e 9 continuam abertas. A raça ainda é o corpo de `CHARACTER_ROSTER`, e
    não um `Resource` de povo: a facção existe como reputação que o diálogo lê e escreve,
    e nada fora do diálogo depende dela ainda.*

12. **Áudio procedural** ✅ *(junto com a fase 5, a pedido explícito)*
    Banco sonoro inteiro sintetizado em NumPy por `tools/gen_audio.py`: passos por
    superfície, vento em camadas, chilro por FM, martelo, porta, água, murmúrio de
    multidão, o banco de sílabas de cada raça com formantes distintos, três leitos de
    ambiência, chuva e três temas de música generativa — modo, progressão por regras e
    timbres sintetizados. `AudioManager` ganhou zonas com crossfade de potência constante
    de 2 s, e `Soundscape` decide a zona pela posição do ouvinte e o tema pelo período.
    `make soundscape` mede. *A ambiência é por zona, não por bioma: bioma é assunto da
    fase que trouxer água e vegetação por região.*

13. **Itens, combate e fechamento**
    Itens e equipamento gerados, combate corpo a corpo e à distância, IA hostil,
    salvamento/carregamento, passe de perfilamento contra todo o orçamento, build de
    release.

---

## Ao terminar qualquer fase

**Nenhuma fase está concluída sem `make preview` e `make bench` rodados, com os números
colados no commit** — mais o alvo de medição que a fase tenha criado (`make anim`,
`make playtest`, `make valley`, `make city`, `make population`, `make dialogue`,
`make daynight`, `make soundscape`). Não é
cerimônia. Um gerador não tem como saber se o que ele produziu
parece certo, e uma contagem de triângulos dentro do orçamento não impede uma árvore de
sair torta ou um chão de sumir por winding invertido — as duas coisas já aconteceram
neste projeto e foram encontradas *olhando*, não lendo log.

`make preview` responde "está certo?":

- `docs/assets.html` com as 34 peças em quatro ângulos e uma figura de 1,75 m ao lado,
  para o tamanho significar alguma coisa;
- `docs/shots/*.png` com a cena de verdade, dos pontos de câmera nomeados.

`make anim` responde "move certo?":

- `docs/anim/*.png` com o ciclo de caminhada, corrida e salto quadro a quadro;
- o desvio do pé apoiado em metros, que é o critério "o pé não desliza" em número;
- `docs/anim/marchas.png`, com três posturas andando lado a lado.

`make playtest` responde "controla bem?":

- velocidade estabilizada andando e correndo, contra o alvo de `params.py`;
- tempo até 90% da velocidade — a sensação de peso em segundos;
- altura do salto, e se o coyote time aceita um pulo *depois* da beirada;
- a menor folga da lente numa órbita completa encostado num muro. Negativa é a câmera
  dentro da parede, que é o critério de aceite em número.

`make valley` responde "a seed manda?":

- a diferença média de relevo entre duas seeds, medida para dentro da borda e como fração
  da amplitude que elas cobrem — e a mesma seed duas vezes, que tem de dar zero;
- a maior inclinação da estrada **no terreno construído**, contra `ROAD_MAX_SLOPE`;
- a fração do vale que a malha de navegação cobre, e a folga do ponto de nascimento;
- `docs/valley/seeds.png`, com os dois vales do mesmo ponto de câmera.

`make city` responde "é habitável?":

- prédios, lotes e ruas por seed, e quantas peças em quantos nós de desenho;
- draw calls e triângulos **na praça**, que é o pior ângulo da cidade;
- quantas portas o navmesh alcança **com caminho saindo da praça** — perguntar só se há
  navegação perto da porta aprovaria uma casa murada dentro de um quarteirão fechado;
- becos sem saída não intencionais, que têm de ser zero;
- `docs/shots/city/*.png`, seis pontos que respondem o que número nenhum responde.

`make population` responde "tem vida?":

- que fração dos habitantes saiu do lugar na **pior** janela de 20 s — média esconderia
  uma cidade que congela por meio minuto e compensa depois;
- quanto do percurso de cada um cai em terreno onde ele ainda não esteve, que é a medida
  anti-repetição: parado dá 0,003, andando de um lado para o outro dá 0,006, e cobrir
  terreno dá dez vezes isso;
- entalos e amostras dentro de parede, que têm de ser zero nos dois casos;
- o pico de corpos com física, contra o teto de `BUDGET["active_npcs"]`.

`make dialogue` responde "a conversa devolve a rotina?":

- o estado e o destino do habitante antes e depois da conversa, e o quanto o destino andou
  entre os dois — tolerância em metro, não "voltou a andar";
- quanto ele andou nos segundos antes, durante e depois: antes prova que havia rotina,
  durante prova que a pausa parou o corpo, depois prova que a retomada religou a física;
- quantas escolhas cada nó ofereceu antes e depois de a flag acender e de a reputação ser
  paga, que é a máquina de condições medida contra o estado que a partida acumulou;
- a estabilidade do pitch por id, que é o único critério de voz que ouvido nenhum pega.

`make daynight` responde "o dia anda sem saltar?":

- quanto a cor andou **além** do que a interpolação pedia, com o tempo 360 vezes
  acelerado. É a medida certa: a 360x a paleta do amanhecer **tem** de passar em fração de
  segundo, e cobrar degrau por quadro seria cobrar que o amanhecer demore. O excesso sobre
  o ideal é o salto que o sistema introduz, e é o único que o jogador leria como corte;
- a velocidade máxima do gradiente, em cor por hora de jogo — o amanhecer real mede 0,47 e
  uma descontinuidade mediria 10, então o teto de 2,0 separa os dois sem ambiguidade;
- o degrau na virada da meia-noite, que é a única emenda do laço e a que ninguém está
  olhando quando quebra;
- quantas vezes o ciclo reescreveu a iluminação em 240 quadros na velocidade normal — é
  "sem custo por quadro" medido, e não prometido;
- a emissão das janelas e os lampiões acesos de dia e de noite, e quantos habitantes
  restam na praça à 1h depois de 70 s de cidade respondendo à hora;
- névoa, sol, chuva e abafamento nos três climas, que é a prova de que eles são estados
  diferentes em número e não três nomes na mesma tabela;
- `docs/daynight/dia.png`, o dia inteiro em cores lado a lado — um salto vira listra.

`make soundscape` responde "o som entra sem corte?":

- a potência somada dos dois leitos na pior amostra de cada travessia. Um crossfade linear
  em amplitude afunda para 0,707 no meio e um de potência constante fica em 1,0: o teto de
  0,72 está entre os dois e reprova a implementação ingênua;
- o maior salto de volume entre duas amostras, que pega um "para um e começa o outro"
  disfarçado de fade;
- a duração medida do crossfade contra os 2 s pedidos, nos dois sentidos;
- se a taverna é reconhecida como interior, com o passa-baixa que vem com isso;
- quantos dos arquivos do manifesto de `make audio` o Godot de fato carrega. Existir em
  disco não é o mesmo que importar.

**Toda medição e toda captura travam o céu em `SHOT_HOUR`** e no tempo firme. Uma rota
fixa existe para que duas execuções sejam comparáveis, e um sorteio de clima no meio faria
a diferença de draw calls entre elas ser nuvem — sem que ninguém saiba disso lendo o CSV.
Nove da manhã porque é a primeira hora do dia com a névoa no fator 1,0, que é a névoa sob
a qual as fases 2 a 11 foram calibradas.

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
