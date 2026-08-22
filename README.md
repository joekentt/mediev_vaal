# Mediev Vaal

Um RPG 3D low poly de fantasia medieval **original**, em Godot 4.4, em que **nada é feito
à mão**. Não há um único modelo modelado, uma cena montada no editor, uma textura pintada
ou um som gravado: o vale, a cidade, os corpos, as conversas, a música e os efeitos nascem
todos de scripts, e todos voltam a nascer iguais com um comando.

Um número gera um vale de 512 metros com relevo erodido, uma estrada que se ajusta ao
terreno, uma cidade murada de quarenta prédios com ruas irregulares, vinte habitantes com
rotina diária, um ciclo de dia e noite de 24 minutos, três climas e um banco de 49 sons
sintetizados. Trocar esse número troca o mundo inteiro.

---

## Como rodar

Depois de clonar, **antes de abrir o Godot**:

```
make all
```

Isso regenera tudo o que é derivado — materiais, as 34 peças do kit, os 7 humanoides, o
banco sonoro, as cenas e o `project.godot` — e verifica que nada está fora do lugar. Sem
isso o jogo abre com materiais faltando e cai no magenta de depuração.

Depois:

```
godot --path .              # ou abra o projeto no editor e rode
```

### O que você precisa ter

| Ferramenta | Para quê | Sem ela |
| --- | --- | --- |
| **Godot 4.4+** | rodar o jogo e as medições | nada roda |
| **Python 3.10+** | o pipeline inteiro | `make` não funciona |
| **Blender** (binário no `PATH`, variável `BLENDER`, ou `pip install bpy`) | `make assets` e `make characters` | sem malhas nem corpos |
| **NumPy** (`pip install numpy`) | `make audio` | sem som |

O resto é stdlib. Não há addon de terceiros, e não vai haver.

### Trocar o mundo

```
make world SEED=123     # outro vale, outra cidade, outra população
```

A seed não mora no código: mora no manifesto do mundo, e o jogo a lê de lá.

---

## Controles

| Ação | Teclado / mouse | Gamepad |
| --- | --- | --- |
| Andar | W A S D | Analógico esquerdo |
| Correr | Shift | L3 |
| Pular | Espaço | A |
| Interagir / conversar | E | X |
| Escolha de diálogo | 1 2 3 4 | Direcional |
| Olhar | mouse | Analógico direito |
| Zoom da câmera | roda do mouse | — |
| Soltar o mouse | Tab | — |
| Pausa / voltar | Esc | Start |
| Contador de FPS | F3 | — |
| Captura de tela | F12 | — |

Nenhum atalho está escrito em código: mexa em `INPUT_MAP` em `tools/params.py` e rode
`make project`.

---

## O que existe

**O vale.** 512 metros gerados de uma seed: ruído fractal em camadas, borda que fecha o
vale em montanha, planície que desliza com a seed, erosão térmica que corta os taludes que
ninguém sobe. A estrada é traçada por spline e **o terreno se ajusta a ela**, não o
contrário. Vegetação e rochas em `MultiMesh` com três faixas de LOD.

**A cidade.** Nasce da mesma seed, em sete etapas isoladas: sítio escolhido pela
inclinação, terraplenagem, muralha irregular de onze lados com o portão voltado para a
estrada, via principal curva, becos por subdivisão recursiva, lotes de testada variada,
prédios empilhados do kit por tipo, props e dois interiores de verdade. Peça igual vira
instância, colisão é sempre caixa, muralha e fachada grande são occluder.

**A vida.** Vinte habitantes com agenda diária guiada por sinal de hora, casa e trabalho
coerentes, navegação pela cidade e simulação barata para quem está longe. Mais fumaça de
chaminé, pássaros, folhas, varais ao vento, um cachorro em ronda e o martelo da ferraria
no compasso do artesão.

**A conversa.** Alvo escolhido por centralidade na tela, prompt discreto, árvores de
diálogo em `.tres` com condições de flag, raça e reputação, enquadramento em ombro, e a
rotina do habitante devolvida exatamente onde parou. Acrescentar uma conversa nova não
exige tocar em código.

**O dia.** 24 minutos reais, cinco períodos, quatro gradientes de cor e seis curvas de
número amostrados pela fração do dia. À noite as janelas acendem por emissão de material e
os lampiões da praça ganham luz. Três climas que multiplicam o que o ciclo decidiu: sol,
nublado e chuva com partículas, névoa mais densa e o som abafado.

**O som.** 49 arquivos sintetizados em NumPy: passos por superfície, vento em camadas,
chilro de pássaro por FM, martelo, porta, água, murmúrio de multidão, o banco de sílabas
de cada raça com formantes distintos, três leitos de ambiência com crossfade de potência
constante, chuva e três temas de música generativa — modo, progressão por regras e timbres
sintetizados, com a afinação conferida por FFT na geração.

**O MVP.** Menu principal, tela de carregamento, pausa que congela o relógio do mundo,
opções (qualidade, distância de renderização, densidade de habitantes, sensibilidade,
volumes, V-Sync), contador de FPS em F3, e save/load em JSON legível — posição, hora, seed,
flags e reputação.

**A abertura.** O jogador acorda num acampamento à beira da estrada, ao amanhecer. Não há
uma linha de tutorial: a fogueira é o único ponto quente do quadro, a estrada é a única
linha reta do vale, e o portão é o único ponto aceso ao longe. A condução é o cenário.

---

## O que virá

- **Kit modular de arquitetura ampliado** (fase 7): a cidade de hoje é montada sobre as 34
  peças da fase 2. Portas, janelas, telhados e escadas no grid de 2 m dariam variedade sem
  custar draw call.
- **Interiores e props** (fase 9): hoje há dois interiores de verdade e cartas escuras
  atrás das outras janelas. Interiores por planta, mobiliário procedural e luz interna
  dentro do teto de luzes com sombra.
- **Itens, combate e fechamento** (fase 13): equipamento gerado, combate corpo a corpo e à
  distância, IA hostil e build de release.
- **Água e biomas**, que ficaram de fora do vale de propósito: não há bioma que a peça
  ainda, e a ambiência de hoje é por zona, não por região.
- **Raça como `Resource` de povo**: hoje a raça é o corpo de `CHARACTER_ROSTER`, e a facção
  existe como reputação que o diálogo lê e escreve.

---

## Como o projeto é feito

A regra é uma só: **nada é criado manualmente**. Todo modelo, cena, material, som e layout
é gerado por script e regenerável com um comando; se algo só existe porque alguém clicou no
editor, está errado. `make verify` cobra isso automaticamente — ele regenera tudo em
memória e compara com o que está na árvore.

```
make all        regenera tudo e verifica          (não precisa do Godot)
make regen      clean + all: a prova de que o projeto sai de tools/
make verify     cobra a regra inegociável
make warnings   prova que o Godot não acusa um único aviso
```

E as medições, que são o que fecha cada fase:

```
make preview    catálogo do kit e capturas da cena
make bench      percorre a rota fixa e mede três estações: vale, portão e praça lotada
make audit      de que a cena é feita em cada estação, e quantos materiais distintos
make anim       tiras de quadros da locomoção e o desvio do pé apoiado
make playtest   dirige o jogador e mede velocidade, salto e folga da câmera
make valley     prova que duas seeds dão vales diferentes e jogáveis
make city       gera três cidades, valida e captura seis pontos
make population três minutos de praça: movimento, entalo e parede
make dialogue   prova que conversar não quebra a rotina do habitante
make daynight   acelera o dia e prova que a cor não salta
make soundscape prova que entrar na cidade não corta o som
make mvp        salva num processo, carrega noutro, e prova que a partida volta
```

Os alvos que desenham precisam de display. Em CI, envolva com um display virtual:

```
xvfb-run -a -s '-screen 0 1920x1080x24' make bench
```

A engenharia do projeto — a regra inegociável, as convenções, o orçamento de performance e
o raciocínio por trás de cada sistema — está em [`CLAUDE.md`](CLAUDE.md). Ele é longo de
propósito: cada decisão não óbvia está escrita ao lado do defeito que a motivou.
