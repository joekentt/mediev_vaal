"""`make dialogue` — roda `tools/dialogue.gd` e cobra os critérios de aceite da fase.

Os dois critérios da fase viram checagem executável, e nenhum deles é sobre pixel:

- **"falar com um NPC e sair não quebra a rotina dele"**: o habitante volta ao mesmo
  estado, com o mesmo destino dentro de `DIALOGUE_PROOF_TOLERANCE`, e volta a andar. As
  três coisas juntas, porque cada uma sozinha aprova o defeito da outra: quem devolve o
  estado e esquece o destino faz o habitante recomeçar a agenda do começo; quem devolve os
  dois e não religa a física faz uma estátua com destino.
- **"adicionar conversa nova não exige tocar em código"**: a árvore aberta na prova é a que
  nenhum caminho de código referencia. Se o projeto tivesse um registro escondido em algum
  lugar, é ela que ficaria muda.

O que a prova não cobra é desenho — quadro, fade, ombro de câmera. Isso é do `make
preview`, que enxerga. Aqui não há renderizador, exatamente para não gastar meia hora de
llvmpipe respondendo à pergunta errada.
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

DIALOGUE_SCRIPT = "res://tools/dialogue.gd"
RESULT_PREFIX = "MEDIEV_DIALOGUE "


def _extract(stdout: str) -> dict | None:
    for line in stdout.splitlines():
        if line.startswith(RESULT_PREFIX):
            return json.loads(line[len(RESULT_PREFIX):])
    return None


def _audit(report: dict) -> list[str]:
    problems: list[str] = []

    if not report.get("chosen"):
        problems.append(
            "nenhum habitante estava a caminho de algum lugar quando a prova foi abrir "
            "conversa. Sem rotina em curso não há rotina para preservar — isto é falha da "
            "fase 10, não da 11."
        )
        return problems

    missing = [entry["id"] for entry in report["trees"] if not entry["loaded"]]
    if missing:
        problems.append(
            f"árvore(s) {missing} não carregaram de {P.DIALOGUE_DIR}/. Rode `make dialogues`."
        )

    routine = report["routine"]
    if not routine["opened"]:
        problems.append(
            "interagir com o habitante não abriu conversa nenhuma. A ligação entre "
            "Interactable, EventBus e DialogueRunner está partida."
        )
    if routine["tree"] != report["unreferenced_tree"]:
        problems.append(
            f"a conversa aberta foi '{routine['tree']}', e a prova pediu "
            f"'{report['unreferenced_tree']}'."
        )
    if not routine["paused"]:
        problems.append("o habitante não pausou a rotina ao ser abordado.")
    if routine["moved_before"] <= routine["min_move"]:
        problems.append(
            f"o habitante escolhido andou só {routine['moved_before']:.2f} m nos "
            f"{report['window_seconds']:g}s antes da conversa. Ele não estava em rotina, "
            f"e uma rotina parada não prova retomada nenhuma."
        )
    if routine["moved_during"] > report["tolerance"]:
        problems.append(
            f"o habitante andou {routine['moved_during']:.2f} m durante a conversa, acima "
            f"da tolerância de {report['tolerance']:.2f} m. Pausar a rotina não parou o corpo."
        )
    if routine["state_before"] != routine["state_after"]:
        problems.append(
            f"o habitante entrou na conversa em {routine['state_before']} e saiu em "
            f"{routine['state_after']}. A conversa trocou o que ele estava fazendo."
        )
    if routine["goal_shift"] > report["tolerance"]:
        problems.append(
            f"o destino do habitante andou {routine['goal_shift']:.2f} m entre o começo e o "
            f"fim da conversa, acima da tolerância de {report['tolerance']:.2f} m. A rotina "
            f"foi recalculada em vez de devolvida."
        )
    if routine["moved_after"] <= routine["min_move"]:
        problems.append(
            f"o habitante andou {routine['moved_after']:.2f} m nos {report['window_seconds']:g}s "
            f"depois da conversa. Ele recebeu o estado de volta mas não voltou a se mexer."
        )
    if not routine["prompt_before"]:
        problems.append("o prompt de contexto não apareceu com um interagível em foco.")
    if routine["prompt_during"]:
        problems.append(
            "o prompt de contexto continuou visível durante a conversa; a tecla abriria a "
            "mesma conversa por cima dela mesma."
        )
    if not routine["prompt_after"]:
        problems.append(
            "o prompt não voltou depois da conversa. A mudez vazou, e o jogador não veria "
            "mais um prompt nesta partida."
        )

    conditions = report["conditions"]
    if not conditions["flag_set"]:
        problems.append(
            f"a escolha do aldeão não acendeu a flag '{conditions['flag_key']}'. Efeito de "
            f"nó não está sendo aplicado."
        )
    if conditions["smith_unlocked"] <= conditions["smith_locked"]:
        problems.append(
            f"a flag não destrancou fala nenhuma no ferreiro: {conditions['smith_locked']} "
            f"escolhas antes e {conditions['smith_unlocked']} depois. Condição por flag não "
            f"está sendo avaliada."
        )
    gain = conditions["reputation_after"] - conditions["reputation_before"]
    if gain <= 0:
        problems.append(
            f"a escolha que paga reputação não mexeu em '{conditions['faction']}': "
            f"{conditions['reputation_before']} antes, {conditions['reputation_after']} depois."
        )
    if conditions["guard_unlocked"] <= conditions["guard_locked"]:
        problems.append(
            f"a reputação não destrancou fala nenhuma no guarda: "
            f"{conditions['guard_locked']} escolhas antes e {conditions['guard_unlocked']} "
            f"depois. Condição por reputação não está sendo avaliada."
        )
    for name, count in (
        ("guarda", conditions["guard_unlocked"]),
        ("ferreiro", conditions["smith_unlocked"]),
    ):
        if count > conditions["cap"]:
            problems.append(
                f"o nó do {name} ofereceu {count} escolhas, acima do teto de "
                f"{conditions['cap']}."
            )
    if conditions["talking_after"]:
        problems.append("a conversa não fechou ao chegar numa escolha sem destino.")

    voice = report["voice"]
    if not voice["stable"]:
        problems.append(
            "o pitch de um mesmo habitante mudou entre duas chamadas. Ele tem de sair do "
            "id, e não de um sorteio por fala."
        )
    if not voice["distinct"]:
        problems.append(
            "dois habitantes diferentes receberam o mesmo pitch. A derivação pelo id não "
            "está separando ninguém."
        )
    if voice["frames"] <= 0:
        problems.append("a síntese de voz devolveu um stream vazio.")

    if report["stuck"] > P.POPULATION_MAX_STUCK:
        problems.append(
            f"{report['stuck']} destravamento(s) no habitante da conversa. Pausar e retomar "
            f"o deixou preso."
        )
    return problems


def main(argv: list[str] | None = None) -> int:
    del argv
    try:
        ensure_imported()
        # Sem renderizador: a prova é de estado e de rotina. Ver o cabeçalho de dialogue.gd.
        process = run_godot(["--headless", "--script", DIALOGUE_SCRIPT])
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

    trees = ", ".join(f"{entry['id']} ({entry['nodes']} nós)" for entry in report["trees"])
    print(f"  árvores:   {trees}")

    if report.get("chosen"):
        routine = report["routine"]
        conditions = report["conditions"]
        voice = report["voice"]
        print(
            f"  conversa:  '{routine['tree']}' com {report['chosen']}, aberta pelo nome — "
            f"nenhum código a referencia"
        )
        print(
            f"  rotina:    {routine['state_before']} → {routine['state_after']}, destino "
            f"mudou {routine['goal_shift']:.2f} m (tolerância {report['tolerance']:.2f} m)"
        )
        print(
            f"  percurso:  {routine['moved_before']:.2f} m antes, "
            f"{routine['moved_during']:.2f} m durante, {routine['moved_after']:.2f} m depois "
            f"(janelas de {report['window_seconds']:g}s)"
        )
        print(
            f"  condições: ferreiro {conditions['smith_locked']}→"
            f"{conditions['smith_unlocked']} escolhas pela flag, guarda "
            f"{conditions['guard_locked']}→{conditions['guard_unlocked']} pela reputação"
        )
        print(
            f"  reputação: {conditions['faction']} "
            f"{conditions['reputation_before']} → {conditions['reputation_after']}"
        )
        print(
            f"  voz:       {voice['frames']} amostras a {voice['rate']} Hz, pitch "
            f"{voice['pitch']:.2f} estável por id, {voice['profiles']} perfis de postura"
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
