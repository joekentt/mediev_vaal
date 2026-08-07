# O pipeline de geração

Este documento explica *como* a regra inegociável do projeto é implementada. O *o quê* e
o *porquê* estão no `CLAUDE.md`.

## Duas camadas

A geração acontece em dois lugares, e a divisão não é arbitrária:

**Python (`tools/`) gera arquivos.** Tudo que precisa existir em disco antes do Godot
abrir: `project.godot`, `scripts/core/params.gd`, materiais `.tres`, o layout de
barramentos, o `.wav` do tom de calibração, o esqueleto das cenas, o manifesto do mundo.
Roda sem o Godot instalado — é o que permite `make all` funcionar em qualquer máquina e
em CI.

**GDScript (`generators/`) gera nós e malhas.** Tudo que só existe enquanto o jogo roda:
`ArrayMesh`, `StaticBody3D`, `WorldEnvironment`, `MultiMeshInstance3D`. Roda dentro do
Godot, com acesso à API da engine.

A fronteira é simples: **se cabe num arquivo de texto e o Godot precisa dele para abrir,
é Python. Se é um nó ou uma malha, é GDScript.**

## O fluxo de uma mudança

Quer deixar o chão mais escuro? Não abra o editor.

```
tools/params.py            PALETTE["ground_default"] = "#6E6A61"
make assets                regenera assets/generated/materials/ground.tres
make preview               roda, mede, mostra a captura
```

Quer mudar a escala do grid do mundo de 2 m para 3 m?

```
tools/params.py            GRID_SIZE = 3.0
make all                   params.gd, project.godot, manifesto — tudo em cascata
```

Um valor, um lugar, um comando. É por isso que `params.py` é a fonte única: mudar a
escala do mundo em dez arquivos é como projetos apodrecem.

## Por que `params.gd` é gerado

O pipeline é Python e o jogo é GDScript — as constantes precisam existir nas duas
linguagens. Duas cópias editáveis à mão divergem em uma semana. Então só uma é editável:

```
tools/params.py  ──[tools/gen_params.py]──>  scripts/core/params.gd
   (fonte)                                        (espelho, versionado)
```

O espelho é versionado (o Godot precisa dele para abrir o projeto), mas carrega
`ARQUIVO GERADO — NÃO EDITE À MÃO` no topo, e `make verify` compara os dois. Editar o
`.gd` reprova o build.

## O que `make verify` cobra

1. **Deriva.** Regenera todo arquivo gerado em memória e compara com o disco. Pega o
   editor do Godot reescrevendo `project.godot`, e pega gente editando `.tres` gerado.
2. **Número mágico.** Varre `scripts/` e `generators/` procurando literal numérico fora
   de declaração `const`. Só passa o punhado de triviais (`0`, `1`, `2`, `-1`, `0.0`,
   `0.5`, `1.0`, `2.0`).
3. **Tipagem.** Todo `var` com tipo, toda `func` com tipo de retorno.
4. **Integridade.** Material aponta para cor que existe; barramento envia para barramento
   que existe; ação de input usa tecla conhecida; orçamentos batem.

Nada disso precisa do Godot.

## O que `make warnings` cobra

Aviso de GDScript é invisível fora do editor: nem `--import` nem rodar o projeto
imprimem qualquer coisa no console. Então "abre limpo no Godot" seria uma promessa que
ninguém consegue verificar.

`make warnings` resolve elevando todo aviso ativo a **erro**, que aí sim aparece:

1. Pergunta ao Godot o nível padrão de cada `debug/gdscript/warnings/*` — a lista de
   avisos ativos vem da engine, não de uma lista escrita à mão que envelhece.
2. Reescreve `project.godot` com todos eles em nível 2.
3. Limpa `.godot/` (com o cache quente o Godot não reanalisa os scripts, e o alvo
   passaria sem testar nada) e roda `--import`.
4. Regenera `project.godot` — o arquivo volta byte a byte ao que `make verify` espera.

`override.cfg` seria mais limpo que reescrever o arquivo, mas o Godot **não** aplica
níveis de aviso vindos de lá. Foi testado; não funciona.

## Medição

`make preview` e `make bench` rodam o projeto de verdade e passam argumentos depois de
`--`. `scripts/core/session_probe.gd` os lê, deixa o renderer aquecer, amostra N frames,
resume e imprime uma linha `MEDIEV_RESULT {json}` que o Python recupera do log.

```
godot --path . -- --bench --screenshot preview.png --out preview.json --budget draw_calls_city
```

O resumo compara os picos com `Params.BUDGET` e devolve a lista de violações.
`make bench` transforma essa lista em código de saída — é o alvo para CI.

> Medir sem display dá números de draw call e frame time que não valem nada. Por isso os
> alvos de medição **exigem** um display e falham dizendo o porquê, em vez de devolver
> zeros com cara de resultado. Em CI:
> `xvfb-run -a -s '-screen 0 1920x1080x24' make bench`.

### O cache de classes globais

O registro de `class_name` (`Params`, `MeshBuilder`, `WorldGenerator`, `SessionProbe`)
mora em `.godot/global_script_class_cache.cfg`, que só existe depois de um import. Rodar
o jogo sem ele falha com *"Identifier not declared in the current scope"* — e como o
`main.gd` não carrega, a janela abre vazia e fica assim **para sempre**, o que se parece
exatamente com uma medição lenta.

Foi um buraco de verdade: `make warnings` limpava `.godot` ao terminar e o `make preview`
seguinte pendurava até o timeout. Duas defesas hoje:

- `ensure_imported()` roda um `--import` antes de medir quando o cache não existe — o que
  também cobre o caso de clone novo.
- `make warnings` reimporta ao restaurar o `project.godot`, em vez de deixar o cache frio.
- Quando o Godot estoura o tempo, o erro mostra as linhas de `SCRIPT ERROR` que ele
  chegou a imprimir, para separar "lento" de "travado".

## A fábrica de assets

`make assets` roda `tools/gen_assets.py` dentro do Blender headless e produz 34 `.glb` em
`assets/generated/kit/`, mais um `manifest.json` com nome, categoria, triângulos, bounding
box e pegada em células de cada peça.

### Três camadas

```
tools/params.py       paleta, grid, tetos, semente-mãe
tools/meshlib.py      primitivas, chanfro, ruído, cor, conferência de normais
tools/kit_*.py        as 34 peças paramétricas
tools/gen_assets.py   driver: constrói, confere, exporta, escreve o manifesto
```

Nenhuma peça exporta a si mesma. Elas devolvem um `BMesh` pintado e o driver faz o resto —
é o que garante que *toda* peça passe pelas mesmas conferências, sem exceção esquecida.

### Dois pontos de entrada

```
blender --background --python tools/gen_assets.py -- [nomes]
python -m tools.gen_assets [nomes]
```

O segundo procura o binário e reexecuta o primeiro; sem binário, cai para o módulo `bpy`
do PyPI, que é o mesmo Blender sem a casca de aplicativo. Máquina de desenvolvedor tem o
binário; CI acha mais fácil `pip install bpy`. Os `.glb` são idênticos nos dois caminhos.

### O que reprova uma peça

O driver levanta `AssetError` e o build inteiro para:

- triângulos acima do teto da categoria (`KIT_TRI_BUDGET`);
- arestas com faces em sentidos opostos (face invertida na malha);
- malha fechada com volume assinado negativo (normais para dentro);
- camada de UV presente;
- pegada fora do grid nos eixos que a peça declara como modulares.

O alinhamento ao grid é **por eixo, declarado por peça**, e não um booleano global: uma
parede vence uma célula em X e tem 25 cm de espessura em Y; um telhado ultrapassa a
célula de propósito, por causa do beiral. Exigir 2 m nos dois eixos de tudo reprovaria o
kit inteiro sem que nada estivesse errado.

### Duas armadilhas que custaram caro

**O vertex color só é exportado se o material o usar.** O exportador de glTF ignora o
atributo de cor quando ele não está ligado na árvore de nós do material — e avisa com uma
linha discreta no meio da conversa do Blender, entregando um `.glb` cinza. `meshlib`
liga um nó `ShaderNodeVertexColor` na Base Color justamente para isso.

**Blender é Z-up, Godot é Y-up.** A conversão é `(x, y, z) → (x, z, -y)`. Zerar o mínimo
dos três eixos no Blender daria, no Godot, uma peça de `Z = -espessura` a `0`: a origem
cairia no canto errado e a fase 6 teria de compensar peça a peça. Por isso
`snap_origin_to_grid` zera o mínimo em X e Z e o **máximo** em Y. Conferido carregando os
34 `.glb` no Godot e medindo o AABB, não deduzido do papel.

### O teste

`make test-assets` prova quatro coisas rodando o Blender, não afirmando:

1. mesma semente, dois processos separados → `.glb` idêntico no SHA-256;
2. semente diferente → arquivo diferente (senão "determinístico" seria só "ignora a
   semente");
3. trocar um hex da paleta repinta exatamente as peças que usam aquela cor, e nenhuma
   outra;
4. peça acima do teto reprova o build.

> **Cuidado ao editar `params.py` por script.** O Python invalida bytecode comparando
> mtime **em segundos inteiros** e tamanho do fonte. Trocar `7717` por `7718` ou um hex
> por outro preserva os dois, então patch e restauração dentro do mesmo segundo deixam o
> `.pyc` antigo parecendo válido — e o processo seguinte importa os valores errados. O
> sintoma é pior que o bug: uma prova falha uma vez a cada tantas execuções, acusando a
> peça errada. `test_assets.py` apaga `tools/__pycache__` antes do primeiro import e
> proíbe os subprocessos de escrever bytecode.

## Determinismo

`Params.WORLD_SEED` controla toda a aleatoriedade da geração. Mesmo seed, mesmo mundo,
byte a byte. Gerador novo deve receber um `RandomNumberGenerator` semeado a partir dele —
nunca chamar `randf()` global, que herda um seed de tempo e quebra a reprodutibilidade.

`make regen` (que é `clean` + `all`) é a prova viva: apaga todo o derivado e reconstrói.
Se o resultado difere, algum gerador não é determinístico.

## Adicionando um gerador

1. Novo número vai para `tools/params.py`, e o campo correspondente em
   `tools/gen_params.py` para chegar ao GDScript.
2. Gerador de arquivo: novo `tools/gen_<coisa>.py` com `main() -> list[Path]`, usando
   `write_if_changed` e o cabeçalho `GENERATED_HEADER`. Registre-o em
   `tools/verify.py::check_drift` e num alvo do `Makefile`.
3. Gerador de nó/malha: novo `generators/<coisa>.gd` com `class_name`, funções `static`
   puras, orçamento de tris declarado em `Params.TRI_BUDGET` e validado no
   `MeshBuilder.commit()`.
4. `make regen && make preview`.
