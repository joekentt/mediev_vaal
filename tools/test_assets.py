"""`make test-assets` — prova as garantias da fábrica em vez de afirmá-las.

Quatro provas, todas executáveis:

1. **Determinismo byte a byte.** A mesma peça gerada duas vezes, em processos separados,
   produz `.glb` idêntico no hash. Rodar em processos separados é o ponto: dentro de um
   processo só, um cache acidental ou um `PYTHONHASHSEED` estável mascarariam a falha.
2. **A semente manda.** Peça com semente diferente produz arquivo diferente. Sem isto,
   "determinístico" poderia significar apenas "ignora a semente".
3. **A paleta manda.** Trocar um hex em `params.py` muda o `.glb` de toda peça que usa
   aquela cor — e só delas. É o critério de aceite "trocar uma cor e regerar muda todas
   as peças coerentemente", verificado e não prometido.
4. **O orçamento reprova.** Uma peça acima do teto faz o build falhar, não avisar.

Precisa do Blender (binário ou módulo `bpy`), porque é ele que gera o que estamos
conferindo.
"""

from __future__ import annotations

import hashlib
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

# Antes do primeiro import, e não por capricho: bytecode obsoleto de `params.py`
# falsifica o teste inteiro (ver `_purge_bytecode`). Depois do import já é tarde — o
# módulo estaria carregado com os valores errados e as provas acusariam a peça errada.
shutil.rmtree(ROOT / "tools" / "__pycache__", ignore_errors=True)

from tools import gen_assets  # noqa: E402
from tools import params as P  # noqa: E402

KIT_DIR = ROOT / P.KIT_DIR

# A prova de determinismo roda sobre o kit **inteiro**, não sobre uma amostra. Custa
# ~1 s por passada e a amostra já mentiu uma vez: ela não incluía `beam`, a única peça
# chanfrada, e por isso deu determinismo como provado enquanto o kit variava a cada
# execução. Amostra serve para as provas 2 e 3, onde o que importa é *qual* peça reage.
SAMPLE = ("wall", "barrel", "rock", "tree_broadleaf")

# Cor trocada na prova 3, e as peças que a usam.
PALETTE_PROBE_KEY = "wood"
PALETTE_PROBE_VALUE = "#123456"

_failures: list[str] = []


def _fail(message: str) -> None:
    _failures.append(message)
    print(f"    FALHOU: {message}")


def _digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _run_factory(parts: tuple[str, ...], expect_failure: bool = False) -> int:
    """Roda a fábrica num processo novo. Processo novo é parte da prova.

    `expect_failure` cala a saída quando a falha *é* o resultado esperado — senão a prova
    4 despeja catorze mensagens de erro corretas no meio de um teste que passou.
    """
    command = [sys.executable, "-m", "tools.gen_assets", *parts]
    environment = dict(os.environ)
    environment["PYTHONDONTWRITEBYTECODE"] = "1"   # ver _purge_bytecode()
    process = subprocess.run(
        command, cwd=ROOT, capture_output=True, text=True, env=environment
    )
    if process.returncode != 0 and not expect_failure:
        print(process.stdout[-2000:])
        print(process.stderr[-2000:], file=sys.stderr)
    return process.returncode


def _snapshot(parts: tuple[str, ...]) -> dict[str, str]:
    return {name: _digest(KIT_DIR / f"{name}.glb") for name in parts}


# ---------------------------------------------------------------------------


def _all_part_names() -> tuple[str, ...]:
    return tuple(spec["name"] for spec in gen_assets.build_catalog())


def test_deterministic() -> None:
    """Prova 1: dois processos, mesma semente, o kit inteiro idêntico byte a byte."""
    every = _all_part_names()
    print(f"  [1] mesma semente, dois processos -> {len(every)} peças idênticas")
    if _run_factory(()) != 0:
        _fail("a fábrica não rodou na primeira passada")
        return
    first = _snapshot(every)

    if _run_factory(()) != 0:
        _fail("a fábrica não rodou na segunda passada")
        return
    second = _snapshot(every)

    drifted = [name for name in every if first[name] != second[name]]
    for name in drifted:
        _fail(f"{name}: hash mudou entre execuções ({first[name][:12]} != {second[name][:12]})")
    if not drifted:
        combined = hashlib.sha256("".join(first[name] for name in every).encode()).hexdigest()
        print(f"      {len(every)} peças estáveis, hash do kit {combined[:16]}")


def test_seed_changes_output() -> None:
    """Prova 2: semente diferente, arquivo diferente — a semente não é decorativa."""
    print("  [2] semente diferente -> .glb diferente")
    baseline = _snapshot(SAMPLE)

    # `KIT_SEED` alimenta `part_seed`, então mexer nele muda a semente de toda peça.
    with _patched_params({"KIT_SEED": P.KIT_SEED + 1}):
        if _run_factory(SAMPLE) != 0:
            _fail("a fábrica não rodou com a semente trocada")
            return
        shifted = _snapshot(SAMPLE)

    # Peças sem ruído (uma parede é geometria pura) legitimamente não mudam; as que usam
    # a semente têm de mudar, senão o parâmetro é fachada.
    seeded = ("barrel", "rock", "tree_broadleaf")
    for name in seeded:
        if baseline[name] == shifted[name]:
            _fail(f"{name}: usa `seed` mas o arquivo não mudou ao trocar a semente")
        else:
            print(f"      {name:<16} mudou, como deve")
    _run_factory(SAMPLE)


def test_palette_propagates() -> None:
    """Prova 3: trocar uma cor em params.py repinta exatamente quem usa aquela cor."""
    print(f"  [3] trocar PALETTE[{PALETTE_PROBE_KEY!r}] -> repinta quem usa")
    baseline = _snapshot(SAMPLE)

    with _patched_params({"PALETTE_ENTRY": (PALETTE_PROBE_KEY, PALETTE_PROBE_VALUE)}):
        if _run_factory(SAMPLE) != 0:
            _fail("a fábrica não rodou com a paleta trocada")
            return
        repainted = _snapshot(SAMPLE)

    # O barril é de madeira; a pedra não. Uma cor trocada tem de repintar exatamente
    # quem a usa — mudar tudo seria tão errado quanto não mudar nada.
    for name in ("barrel",):
        if baseline[name] == repainted[name]:
            _fail(f"{name}: usa a cor {PALETTE_PROBE_KEY!r} mas não mudou")
        else:
            print(f"      {name:<16} repintado")
    for name in ("rock",):
        if baseline[name] != repainted[name]:
            _fail(f"{name}: não usa {PALETTE_PROBE_KEY!r} e mesmo assim mudou")
        else:
            print(f"      {name:<16} intacto, como deve")
    _run_factory(SAMPLE)


def test_budget_is_enforced() -> None:
    """Prova 4: peça acima do teto reprova o build, não emite um aviso."""
    print("  [4] estourar o orçamento -> build falha")
    with _patched_params({"KIT_TRI_BUDGET_ARCH": 1}):
        code = _run_factory(("wall",), expect_failure=True)
    if code == 0:
        _fail("uma parede de 24 tris passou por um teto de 1 — o orçamento não é cobrado")
    else:
        print("      teto de 1 tri reprovou a parede, como deve")
    _run_factory(SAMPLE)


# ---------------------------------------------------------------------------


def _purge_bytecode() -> None:
    """Apaga o `.pyc` de `tools/`. Sem isto o teste mente.

    O Python invalida bytecode comparando **mtime em segundos inteiros e tamanho** do
    fonte. As trocas deste arquivo preservam os dois de propósito (`7717` -> `7718`,
    `"#6B4A2F"` -> `"#123456"`), então patch e restauração no mesmo segundo deixam o
    `.pyc` antigo parecendo válido — e o subprocesso seguinte importa o `params.py`
    errado. Foi medido: depois de restaurar, um subprocesso ainda lia a semente patchada.

    O sintoma era pior que o bug: uma prova falhava uma vez em cada tantas execuções,
    acusando a peça errada. Cinto e suspensório — apagamos o cache e ainda proibimos o
    subprocesso de escrever um novo.
    """
    cache = ROOT / "tools" / "__pycache__"
    if cache.exists():
        shutil.rmtree(cache, ignore_errors=True)


class _patched_params:
    """Aplica uma mudança em `tools/params.py`, roda o bloco, e restaura o original.

    Editar o arquivo (em vez de passar variável de ambiente) é de propósito: é assim que
    a mudança acontece na vida real, e é o caminho que queremos provar. O `__exit__`
    restaura o conteúdo exato, inclusive se o teste explodir no meio.
    """

    def __init__(self, changes: dict) -> None:
        self.changes = changes
        self.path = ROOT / "tools/params.py"
        self.original = ""

    def __enter__(self) -> None:
        self.original = self.path.read_text(encoding="utf-8")
        patched = self.original
        if "KIT_SEED" in self.changes:
            patched = patched.replace(
                f"KIT_SEED = {P.KIT_SEED}", f"KIT_SEED = {self.changes['KIT_SEED']}"
            )
        if "PALETTE_ENTRY" in self.changes:
            key, value = self.changes["PALETTE_ENTRY"]
            patched = patched.replace(f'"{key}":' + " " * 11 + f'"{P.PALETTE[key]}"',
                                      f'"{key}":' + " " * 11 + f'"{value}"')
            if patched == self.original:
                # O alinhamento da paleta pode mudar; caia para uma troca menos exigente.
                patched = self.original.replace(f'"{P.PALETTE[key]}"', f'"{value}"')
        if "KIT_TRI_BUDGET_ARCH" in self.changes:
            patched = patched.replace(
                f'"architecture": {P.KIT_TRI_BUDGET["architecture"]},',
                f'"architecture": {self.changes["KIT_TRI_BUDGET_ARCH"]},',
            )
        if patched == self.original:
            raise AssertionError(f"a substituição {self.changes} não achou o alvo em params.py")
        self.path.write_text(patched, encoding="utf-8")
        _purge_bytecode()

    def __exit__(self, *exc_info) -> None:
        self.path.write_text(self.original, encoding="utf-8")
        _purge_bytecode()


def main(argv: list[str] | None = None) -> int:
    del argv
    _failures.clear()

    if not gen_assets._is_inside_blender() and gen_assets.find_blender() is None:
        print(
            "ERRO: o teste precisa do Blender. Deixe `blender` no PATH, aponte $BLENDER,\n"
            "  ou instale o módulo com `pip install bpy`.",
            file=sys.stderr,
        )
        return 1

    test_deterministic()
    test_seed_changes_output()
    test_palette_propagates()
    test_budget_is_enforced()

    if _failures:
        print(f"\n  {len(_failures)} prova(s) falharam.", file=sys.stderr)
        return 1
    print("\n  4 provas passaram: determinismo, semente, paleta e orçamento")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
