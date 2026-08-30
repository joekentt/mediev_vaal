"""`make soundscape` — roda `tools/soundscape.gd` e cobra o aceite do som por zona.

O critério da fase é "o som muda ao entrar e sair da cidade sem corte perceptível", e
aqui ele vira três números por travessia:

- a **potência somada** dos dois leitos na pior amostra, contra `SOUNDSCAPE_MIN_TOTAL`.
  É o buraco: um crossfade linear em amplitude afunda para 0,707 no meio da troca, um de
  potência constante fica em 1,0, e o teto está entre os dois;
- o maior **salto** de potência entre duas amostras consecutivas, contra
  `SOUNDSCAPE_MAX_STEP`. É o clique: pega um "para um e começa o outro" disfarçado de fade;
- a **duração** do crossfade medida, contra `AUDIO_ZONE_CROSSFADE`.

Mais a prova de que o banco existe de verdade: todo arquivo do manifesto de `make audio`
tem de carregar como `AudioStream` dentro do Godot. Existir em disco não basta.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from tools import params as P  # noqa: E402
from tools.util import GodotMissing, GodotTimeout, ensure_imported, fail, run_godot  # noqa: E402

SOUNDSCAPE_SCRIPT = "res://tools/soundscape.gd"
RESULT_PREFIX = "MEDIEV_SOUNDSCAPE "


def _extract(stdout: str) -> dict | None:
    for line in stdout.splitlines():
        if line.startswith(RESULT_PREFIX):
            return json.loads(line[len(RESULT_PREFIX):])
    return None


def _audit_pass(name: str, leg: dict, report: dict) -> list[str]:
    problems: list[str] = []
    if leg["from"] == leg["to"]:
        problems.append(
            f"{name}: o ouvinte saiu de {leg['from']!r} e chegou em {leg['to']!r} — a zona "
            f"não mudou, e não há travessia nenhuma para medir."
        )
        return problems
    if leg["min_total"] < report["min_total"]:
        problems.append(
            f"{name}: a potência somada dos dois leitos caiu para {leg['min_total']:.3f}, "
            f"abaixo do mínimo de {report['min_total']:.3f}. É um buraco audível no meio "
            f"da troca."
        )
    if leg["max_step"] > report["max_step"]:
        problems.append(
            f"{name}: o volume mudou {leg['max_step']:.3f} de uma amostra para a seguinte, "
            f"acima do teto de {report['max_step']:.3f}. É um salto, não um fade."
        )
    measured = leg["crossfade_seconds"]
    # A tolerância cresce com o intervalo entre observações: nenhum instante pode ser
    # medido com mais precisão que o espaçamento das amostras, e sem GPU um quadro da
    # cidade leva frações de segundo — bem mais que o período de amostragem pedido. Dois
    # intervalos porque tanto o começo quanto o fim do crossfade são detectados assim.
    allowed = report["tolerance"] + 2.0 * leg.get("worst_gap", 0.0)
    if measured < 0.0:
        problems.append(f"{name}: o crossfade não terminou dentro da travessia medida.")
    elif abs(measured - report["crossfade_target"]) > allowed:
        problems.append(
            f"{name}: o crossfade levou {measured:.2f}s, e o pedido é "
            f"{report['crossfade_target']:.2f}s (tolerância {allowed:.2f}s, sendo "
            f"{report['tolerance']:.2f}s de folga e {2.0 * leg.get('worst_gap', 0.0):.2f}s "
            f"de granularidade de amostragem)."
        )
    return problems


def _audit(report: dict) -> list[str]:
    problems: list[str] = []
    problems += _audit_pass("entrando", report["entering"], report)
    problems += _audit_pass("saindo", report["leaving"], report)

    interior = report["interior"]
    if not interior.get("reached", False):
        problems.append(
            f"dentro da taverna a zona é {interior.get('zone', '?')!r} e devia ser "
            f"'interior'. A caixa do prédio não está sendo reconhecida."
        )

    bank = report["bank"]
    if bank["listed"] == 0:
        problems.append("o manifesto do banco sonoro não foi encontrado. Rode `make audio`.")
    elif bank["loaded"] < bank["listed"]:
        problems.append(
            f"{bank['listed'] - bank['loaded']} de {bank['listed']} arquivos do banco não "
            f"carregaram no Godot: {', '.join(bank['missing'][:5])}"
        )
    if len(bank.get("themes", [])) < len(P.MUSIC_THEMES):
        problems.append(
            f"o banco tem {len(bank.get('themes', []))} temas e a fase pede "
            f"{len(P.MUSIC_THEMES)}."
        )
    if bank.get("compressed"):
        problems.append(
            f"{len(bank['compressed'])} arquivo(s) chegaram ao jogo recomprimidos com "
            f"perda em vez de PCM 16 bits: {', '.join(bank['compressed'][:3])}. O preset "
            f"de import em project.godot não está valendo — e a voz, que costura bytes de "
            f"sílabas, sai muda."
        )
    if bank.get("beds_looping", 0) < bank.get("beds", 0):
        problems.append(
            f"só {bank.get('beds_looping', 0)} de {bank.get('beds', 0)} leitos de ambiência "
            f"estão marcados para repetir. Uma zona fica muda quando o leito acaba."
        )
    return problems


def main(argv: list[str] | None = None) -> int:
    del argv
    try:
        ensure_imported()
        # Driver de áudio mudo: o que se mede são os ganhos que o AudioManager escreve, e
        # eles são os mesmos com ou sem placa de som. Pedir saída de áudio num contêiner
        # sem uma faria o Godot recusar antes de chegar à medição.
        process = run_godot(
            ["--headless", "--audio-driver", "Dummy", "--script", SOUNDSCAPE_SCRIPT]
        )
    except (GodotMissing, GodotTimeout) as error:
        fail(str(error))
        return 1

    report = _extract(process.stdout)
    if report is None:
        fail(f"o Godot terminou com código {process.returncode} sem reportar medição.")
        for line in (process.stdout + process.stderr).splitlines():
            if line.startswith("SCRIPT ERROR") or line.startswith("ERROR"):
                print(f"  {line}", file=sys.stderr)
        return 1

    bank = report["bank"]
    print(
        f"  banco:      {bank['loaded']}/{bank['listed']} arquivos carregados em PCM 16 "
        f"bits, {bank['seconds']:.0f} s de som, temas {', '.join(sorted(bank['themes']))}"
    )
    print(
        f"  laço:       {bank.get('beds_looping', 0)}/{bank.get('beds', 0)} leitos marcados "
        f"para repetir"
    )
    for name, key in (("entrando", "entering"), ("saindo", "leaving")):
        leg = report[key]
        print(
            f"  {name:<10s}: {leg['from']} -> {leg['to']} em "
            f"{leg['crossfade_seconds']:.2f}s (pedido "
            f"{report['crossfade_target']:.1f}s), potência mínima "
            f"{leg['min_total']:.3f}, maior salto {leg['max_step']:.3f} "
            f"em {leg['samples']} amostras; zonas {' -> '.join(leg['zones'])}"
        )
    interior = report["interior"]
    print(
        f"  interior:   zona {interior.get('zone', '?')}, tema "
        f"{interior.get('music', '?')}, potência {interior.get('total', 0.0):.3f}"
    )
    print(
        f"  tetos:      potência ≥ {report['min_total']:.2f}, salto ≤ "
        f"{report['max_step']:.2f}, crossfade "
        f"{report['crossfade_target']:.1f}±{report['tolerance']:.2f}s"
    )

    problems = _audit(report)
    if problems:
        print()
        for problem in problems:
            print(f"  ESTOUROU: {problem}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
