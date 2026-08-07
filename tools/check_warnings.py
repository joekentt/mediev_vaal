"""`make warnings` — prova que o projeto abre no Godot sem um único aviso.

O Godot só mostra aviso de GDScript no painel do editor: nem `--import` nem rodar o
projeto imprimem qualquer coisa na saída padrão. Isso torna "abre limpo" impossível de
verificar em CI — e fácil de deixar apodrecer sem ninguém notar.

A saída é elevar todo aviso ativo ao nível de **erro**, que aí sim aparece no console.
Como `project.godot` é gerado, não precisamos de backup: reescrevemos o arquivo com os
avisos em nível 2, rodamos, e regeneramos o original ao fim — inclusive se algo explodir
no meio. O resultado é byte a byte o mesmo arquivo que `make verify` espera.

(`override.cfg` seria mais elegante, mas o Godot não aplica níveis de aviso por lá:
foi testado e não funciona. Daí a reescrita temporária.)

Quais avisos estão ativos não é chute: o script pergunta ao próprio Godot, lendo o nível
padrão de cada `debug/gdscript/warnings/*` via `ProjectSettings`.
"""

from __future__ import annotations

import re
import shutil
import sys

from . import gen_project
from .util import GodotMissing, GodotTimeout, ROOT, fail, run_godot

PROBE = ROOT / "warning_probe.gd"
PROJECT_FILE = ROOT / "project.godot"
GODOT_CACHE = ROOT / ".godot"

WARNING_PREFIX = "debug/gdscript/warnings/"
LEVEL_IGNORE = "0"
LEVEL_ERROR = 2
NON_LEVEL_KEYS = {"enable", "exclude_addons"}

_PROBE_SOURCE = """extends SceneTree

func _initialize() -> void:
	for property in ProjectSettings.get_property_list():
		var key: String = property["name"]
		if key.begins_with("%s"):
			print("LEVEL %%s=%%s" %% [key, ProjectSettings.get_setting(key)])
	quit()
""" % WARNING_PREFIX

_DIAGNOSTIC_RE = re.compile(r"^(SCRIPT ERROR|ERROR):")


def _active_warning_keys() -> list[str]:
    """Pergunta ao Godot quais avisos vêm ligados, em vez de chutar uma lista."""
    PROBE.write_text(_PROBE_SOURCE, encoding="utf-8")
    try:
        process = run_godot(["--headless", "--script", f"res://{PROBE.name}"])
    finally:
        PROBE.unlink(missing_ok=True)

    keys: list[str] = []
    for line in process.stdout.splitlines():
        if not line.startswith("LEVEL "):
            continue
        setting, _, level = line[len("LEVEL "):].partition("=")
        name = setting[len(WARNING_PREFIX):]
        if name in NON_LEVEL_KEYS or level.strip() == LEVEL_IGNORE:
            continue
        keys.append(name)
    return sorted(keys)


def main(argv: list[str] | None = None) -> int:
    del argv
    try:
        keys = _active_warning_keys()
    except (GodotMissing, GodotTimeout) as error:
        fail(str(error))
        return 1

    if not keys:
        fail("Não consegui ler os níveis de aviso do Godot. O projeto foi gerado?")
        return 1

    strict = {key: LEVEL_ERROR for key in keys}
    PROJECT_FILE.write_text(gen_project.render(strict), encoding="utf-8")
    try:
        # O Godot só reanalisa os scripts com o cache frio; com ele quente, nada aparece.
        shutil.rmtree(GODOT_CACHE, ignore_errors=True)
        process = run_godot(["--headless", "--import"])
    finally:
        # Regenera o original: o arquivo volta idêntico ao que `make verify` espera.
        PROJECT_FILE.write_text(gen_project.render(), encoding="utf-8")
        shutil.rmtree(GODOT_CACHE, ignore_errors=True)

    diagnostics = [
        line for line in (process.stdout + process.stderr).splitlines()
        if _DIAGNOSTIC_RE.match(line) or "Warning treated as error" in line
    ]

    if diagnostics:
        print(f"  {len(keys)} avisos elevados a erro — o projeto NÃO está limpo:")
        for line in dict.fromkeys(diagnostics):
            print(f"    {line}")
        print("  Corrija os avisos acima: abrir limpo é critério de aceite de toda fase.",
              file=sys.stderr)
        return 1

    print(f"  {len(keys)} avisos ativos elevados a erro: nenhum disparou")
    print("  o projeto abre no Godot sem um único warning")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
