"""Utilidades compartilhadas pelos geradores."""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def GENERATED_HEADER(generator: str, source: str, comment: str = "#") -> str:
    """Cabeçalho padrão de arquivo gerado. Nenhum arquivo gerado é editável à mão."""
    return (
        f"{comment} ARQUIVO GERADO — NÃO EDITE À MÃO.\n"
        f"{comment} Gerado por: {generator}\n"
        f"{comment} Fonte:      {source}\n"
        f"{comment} Regenerar:  make all\n"
    )


def write_if_changed(relative_path: str | Path, content: str) -> list[Path]:
    """Escreve o arquivo só se o conteúdo mudou. Devolve o que de fato foi tocado."""
    path = ROOT / relative_path
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists() and path.read_text(encoding="utf-8") == content:
        return []
    path.write_text(content, encoding="utf-8")
    return [path]


def report(step: str, written: list[Path]) -> None:
    """Log uniforme dos geradores."""
    if not written:
        print(f"  {step}: em dia")
        return
    for path in written:
        print(f"  {step}: {path.relative_to(ROOT)}")


# Renderizador por software (llvmpipe, CI sem GPU) leva minutos onde uma GPU leva
# segundos. Ajuste com GODOT_TIMEOUT=600 quando for o caso.
DEFAULT_GODOT_TIMEOUT = int(os.environ.get("GODOT_TIMEOUT", "300"))

# Quantas linhas de erro do Godot mostrar quando ele trava.
MAX_DIAGNOSTIC_LINES = 8


class GodotMissing(RuntimeError):
    """Godot não foi encontrado. Só afeta `make preview` e `make bench`."""


class GodotTimeout(RuntimeError):
    """O Godot não terminou a tempo."""


def find_godot() -> str:
    """Localiza o executável do Godot: $GODOT, depois nomes comuns no PATH."""
    from_env = os.environ.get("GODOT")
    if from_env:
        if shutil.which(from_env) or Path(from_env).is_file():
            return from_env
        raise GodotMissing(f"$GODOT aponta para algo que não existe: {from_env}")
    for name in ("godot", "godot4", "Godot", "godot-4"):
        found = shutil.which(name)
        if found:
            return found
    raise GodotMissing(
        "Godot 4.x não encontrado no PATH.\n"
        "Instale-o ou aponte a variável de ambiente GODOT para o executável:\n"
        "  GODOT=/caminho/para/godot make preview"
    )


def run_godot(args: list[str], timeout: int | None = None) -> subprocess.CompletedProcess:
    """Roda o Godot neste projeto e devolve o processo terminado."""
    binary = find_godot()
    command = [binary, "--path", str(ROOT), *args]
    seconds = DEFAULT_GODOT_TIMEOUT if timeout is None else timeout
    print(f"  $ {' '.join(command)}")
    try:
        return subprocess.run(command, capture_output=True, text=True, timeout=seconds)
    except subprocess.TimeoutExpired as expired:
        # Sem o que o Godot chegou a imprimir, "não terminou" é indistinguível de um
        # erro de script que trava o jogo numa janela vazia. Mostre o que houver.
        captured = _decode(expired.stdout) + _decode(expired.stderr)
        diagnostics = [
            line for line in captured.splitlines()
            if line.startswith("SCRIPT ERROR") or line.startswith("ERROR")
        ]
        detail = ""
        if diagnostics:
            joined = "\n    ".join(dict.fromkeys(diagnostics[:MAX_DIAGNOSTIC_LINES]))
            detail = f"\n\n  O Godot reclamou antes de travar:\n    {joined}"
        raise GodotTimeout(
            f"O Godot não terminou em {seconds}s.\n"
            f"Sem GPU (llvmpipe, CI headless) a medição fica ordens de grandeza mais "
            f"lenta — dê mais tempo com GODOT_TIMEOUT=1800.\n"
            f"Se houver erro de script abaixo, o jogo travou numa janela vazia e o "
            f"tempo não era o problema.{detail}"
        ) from expired


def _decode(stream: bytes | str | None) -> str:
    if stream is None:
        return ""
    if isinstance(stream, bytes):
        return stream.decode("utf-8", errors="replace")
    return stream


def ensure_imported() -> None:
    """Garante que o Godot já importou o projeto ao menos uma vez.

    O registro de classes globais (`class_name`) vive em `.godot/`. Sem ele, rodar o
    jogo direto falha com "Identifier not declared in the current scope" e a janela fica
    parada para sempre — que foi exatamente o que aconteceu depois de `make warnings`
    limpar o cache. Clone novo cai no mesmo buraco.
    """
    if (ROOT / ".godot" / "global_script_class_cache.cfg").exists():
        return
    print("  (importando o projeto: o cache de classes globais não existe ainda)")
    run_godot(["--headless", "--import"])


def fail(message: str) -> None:
    """Encerra o passo com erro visível e código de saída não-zero."""
    print(f"ERRO: {message}", file=sys.stderr)
    raise SystemExit(1)
