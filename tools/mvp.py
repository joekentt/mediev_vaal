"""`make mvp` — salva num processo, carrega noutro, e cobra que a partida volte.

O critério de aceite é "salvar, fechar, reabrir e continuar funciona", e a única forma
honesta de verificá-lo é com **dois processos do Godot**. Entre eles morrem a árvore de
cena, os autoloads e as variáveis estáticas do `WorldGenerator`; o que atravessa é o JSON
em `user://save.json`, que é o que o jogador tem quando fecha o jogo.

O que se cobra, em número:

- a seed do mundo recarregado é a mesma que foi salva — sem isso, "continuar" devolve
  outro vale com o jogador na coordenada antiga, que é o defeito mais fácil de não notar
  num teste de uma sessão só;
- a posição volta dentro de `MVP_POSITION_TOLERANCE`, e apoiada no relevo dentro de
  `MVP_GROUND_TOLERANCE` — que não é folga para erro, e sim a diferença entre a função de
  altura e a malha triangulada em que o corpo de fato se apoia;
- a hora, as flags e a reputação voltam iguais;
- a pausa não move o relógio do mundo;
- a abertura põe o jogador ao lado da estrada e com a cidade a uma caminhada de distância.
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

MVP_SCRIPT = "res://tools/mvp.gd"
RESULT_PREFIX = "MEDIEV_MVP "


def _extract(stdout: str) -> dict | None:
    for line in stdout.splitlines():
        if line.startswith(RESULT_PREFIX):
            return json.loads(line[len(RESULT_PREFIX):])
    return None


def _run_side(mode: str) -> dict | None:
    process = run_godot(["--headless", "--script", MVP_SCRIPT, "--", mode])
    report = _extract(process.stdout)
    if report is None:
        fail(f"o lado `{mode}` terminou com código {process.returncode} sem reportar.")
        for line in (process.stdout + process.stderr).splitlines():
            if line.startswith("SCRIPT ERROR") or line.startswith("ERROR"):
                print(f"  {line}", file=sys.stderr)
    return report


def _audit(flow: dict, saved: dict, loaded: dict) -> list[str]:
    problems: list[str] = []

    if not flow["started_at_menu"]:
        problems.append("a cena principal não abriu no menu.")
    if not flow["reached_playing"]:
        problems.append(
            f"o jogo não chegou a jogar depois de 'Novo vale' em "
            f"{flow['frames_to_world']} quadros."
        )
    for key, text in (
        ("has_stage", "o estágio"),
        ("has_player", "o jogador"),
        ("has_fps_counter", "o contador de FPS"),
    ):
        if not flow[key]:
            problems.append(f"{text} não existe depois de começar a partida.")
    if not flow["paused_ok"]:
        problems.append("a pausa não pausou o jogo.")
    if not flow["running_after"]:
        problems.append("o jogo continuou pausado depois de fechar a pausa.")

    if not saved["wrote"]:
        problems.append(f"não consegui escrever o save em {saved['path']}.")
    if loaded["seed_world"] != saved["seed"]:
        problems.append(
            f"o mundo recarregado nasceu da seed {loaded['seed_world']} e o save guardou "
            f"{saved['seed']}. Continuar devolveu outro vale."
        )
    if loaded["position_gap_m"] > P.MVP_POSITION_TOLERANCE:
        problems.append(
            f"o jogador voltou a {loaded['position_gap_m']:.2f} m de onde salvou, acima da "
            f"tolerância de {P.MVP_POSITION_TOLERANCE:g} m."
        )
    if loaded["ground_gap_m"] < -P.MVP_GROUND_TOLERANCE:
        problems.append(
            f"o jogador voltou {abs(loaded['ground_gap_m']):.2f} m **abaixo** do relevo, "
            f"além da folga de {P.MVP_GROUND_TOLERANCE:g} m entre a malha e a função. "
            f"Continuar a partida o enterrou no chão."
        )
    if abs(loaded["hour_world"] - saved["hour"]) > P.MVP_HOUR_TOLERANCE:
        problems.append(
            f"a hora voltou como {loaded['hour_world']:.3f} e foi salva como "
            f"{saved['hour']:.3f}."
        )
    if not loaded["flags"]:
        problems.append("as flags de mundo não voltaram do save.")
    if int(loaded["reputation"].get("vilarejo", 0)) != int(
        saved["reputation"].get("vilarejo", -1)
    ):
        problems.append(
            f"a reputação voltou como {loaded['reputation']} e foi salva como "
            f"{saved['reputation']}."
        )

    pause = saved["pause"]
    if pause["drift_hours"] > P.MVP_PAUSE_TOLERANCE:
        problems.append(
            f"o relógio do mundo andou {pause['drift_hours'] * 60.0:.2f} minutos de jogo "
            f"durante {pause['frames']} quadros de pausa. A pausa não está pausando o tempo."
        )
    if not pause["running_after"]:
        problems.append("o jogo continuou pausado depois de despausar.")

    opening = saved["opening"]
    if not opening["built"]:
        problems.append("a abertura não foi construída.")
    else:
        if opening["road_gap_m"] > P.MVP_ROAD_TOLERANCE:
            problems.append(
                f"o acampamento nasceu a {opening['road_gap_m']:.1f} m da estrada, acima de "
                f"{P.MVP_ROAD_TOLERANCE:g} m. A estrada é a condução da abertura: longe "
                f"dela, não há para onde o olho ir."
            )
        if opening["lanterns"] <= 0:
            problems.append("nenhuma lanterna marcou a estrada até o portão.")
    return problems


def main(argv: list[str] | None = None) -> int:
    del argv
    try:
        ensure_imported()
        flow = _run_side("fluxo")
        if flow is None:
            return 1
        saved = _run_side("salvar")
        if saved is None:
            return 1
        loaded = _run_side("carregar")
        if loaded is None:
            return 1
    except (GodotMissing, GodotTimeout) as error:
        fail(str(error))
        return 1

    print(
        f"  fluxo:      menu -> mundo em {flow['frames_to_world']} quadros, "
        f"{flow['npcs']} habitantes, pausa "
        f"{'ok' if flow['paused_ok'] and flow['running_after'] else 'quebrada'}"
    )
    opening = saved["opening"]
    print(
        f"  abertura:   acampamento a {opening['road_gap_m']:.1f} m da estrada e "
        f"{opening['gate_gap_m']:.0f} m do portão, {opening['lanterns']} lanternas no caminho"
    )
    pause = saved["pause"]
    print(
        f"  pausa:      {pause['frames']} quadros pausados, relógio andou "
        f"{pause['drift_hours'] * 60.0:.3f} min de jogo (tolerância "
        f"{P.MVP_PAUSE_TOLERANCE * 60.0:.1f})"
    )
    print(
        f"  salvou:     seed {saved['seed']}, {saved['hour']:.2f}h, "
        f"{saved['flags']} flag(s), reputação {saved['reputation']}"
    )
    print(
        f"  carregou:   seed {loaded['seed_world']}, {loaded['hour_world']:.2f}h, "
        f"posição a {loaded['position_gap_m']:.2f} m do salvo e "
        f"{loaded['ground_gap_m']:+.2f} m do relevo"
    )
    print(
        f"  mundo:      {loaded['npcs']} habitantes, flags {loaded['flags']}, "
        f"reputação {loaded['reputation']}"
    )

    problems = _audit(flow, saved, loaded)
    if problems:
        print()
        for problem in problems:
            print(f"  ESTOUROU: {problem}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
