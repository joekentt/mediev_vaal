"""Gera `resources/gaits/*.tres` — um perfil de marcha por postura.

Estes `.tres` são o que faz corpos diferentes andarem diferente sem uma linha de código
específica. `ProceduralLocomotion` não conhece guarda nem batedor: ele lê amplitude,
cadência e viés de um `GaitProfile`, e o perfil vem da postura que o corpo já declara em
`CHARACTER_ROSTER`.

Ao contrário de `assets/generated/`, `resources/` é **versionado**: é dado de design, não
derivado de malha, e o diff de um perfil de marcha é exatamente o tipo de mudança que se
quer ver numa revisão. Continua gerado, e `make verify` reprova se alguém editar à mão.
"""

from __future__ import annotations

from pathlib import Path

from . import params as P
from .util import GENERATED_HEADER, write_if_changed

OUTPUT_DIR = Path(P.GAIT_DIR)
SCRIPT_PATH = "res://scripts/gameplay/gait_profile.gd"
SCRIPT_ID = "1_gait_profile"

# Ordem dos campos no .tres. Fixa e explícita: o dicionário de params.py já tem ordem,
# mas depender dela deixaria o arquivo gerado mudar por um reordenamento inocente lá.
FIELDS = (
    "stride_scale", "cadence_scale", "foot_lift", "foot_lift_run", "knee_forward",
    "hip_bounce", "hip_sway_deg", "hip_drop_deg", "torso_lean_deg", "torso_twist_deg",
    "arm_swing_deg", "arm_bias_deg", "elbow_bend_deg", "head_bob",
)


def _profile_resource(posture: str, values: dict[str, float]) -> str:
    lines = [f'posture = &"{posture}"']
    for field in FIELDS:
        lines.append(f"{field} = {float(values[field])!r}")
    body = "\n".join(lines)
    return f"""{GENERATED_HEADER('tools/gen_gaits.py', 'tools/params.py', ';')}
[gd_resource type="Resource" script_class="GaitProfile" load_steps=2 format=3]

[ext_resource type="Script" path="{SCRIPT_PATH}" id="{SCRIPT_ID}"]

[resource]
script = ExtResource("{SCRIPT_ID}")
{body}
"""


def main() -> list[Path]:
    missing = sorted(set(FIELDS) - set(next(iter(P.GAIT_PROFILES.values()))))
    if missing:
        raise SystemExit(f"tools/params.py: perfil de marcha sem os campos {missing}.")

    postures = {spec["posture"] for spec in P.CHARACTER_ROSTER}
    unknown = sorted(postures - set(P.GAIT_PROFILES))
    if unknown:
        raise SystemExit(
            f"tools/params.py: o elenco usa a postura {unknown} e GAIT_PROFILES não a "
            f"define. Um corpo sem perfil andaria com a marcha de outro povo."
        )

    written: list[Path] = []
    for posture, values in P.GAIT_PROFILES.items():
        written += write_if_changed(
            OUTPUT_DIR / f"{posture}.tres", _profile_resource(posture, values)
        )
    print(f"  marchas: {len(P.GAIT_PROFILES)} perfis em {OUTPUT_DIR}/")
    return written


if __name__ == "__main__":
    main()
