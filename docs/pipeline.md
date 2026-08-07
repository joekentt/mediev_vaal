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
