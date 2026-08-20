"""Gera `scenes/npc/npc.tscn`.

O habitante reaproveita o corpo inteiro do jogador — `RaceApplier` veste a malha e
dimensiona a cápsula, `ProceduralLocomotion` move as pernas por IK — e troca o que é
específico: entra `NavigationAgent3D` no lugar do braço de câmera, e entra uma `Area3D` de
percepção que o jogador não precisa.

Duas coisas aqui existem por erro cometido antes, e vale dizer quais:

- `Race` é `Node3D`, não `Node`. A propagação de transformação do Godot sobe pela cadeia
  de `Node3D` e um `Node` cru no meio a corta — foi o que deixou a malha do jogador
  cravada na origem enquanto a cápsula andava, na fase 6.
- A `Area3D` de percepção **não colide**, só detecta: ela está na camada de gatilho e
  observa jogador e NPC. Uma área de percepção com colisão física empurraria os
  habitantes uns pelos outros pela cidade inteira.
"""

from __future__ import annotations

from pathlib import Path

from . import params as P
from .util import GENERATED_HEADER, write_if_changed

OUTPUT = Path(P.NPC_SCENE)

CONTROLLER_SCRIPT = "res://scripts/gameplay/npc_controller.gd"
RACE_SCRIPT = "res://scripts/gameplay/race_applier.gd"
LOCOMOTION_SCRIPT = "res://scripts/gameplay/procedural_locomotion.gd"
INTERACTABLE_SCRIPT = "res://scripts/gameplay/interactable.gd"

# Altura de partida da cápsula, só até o RaceApplier medir o corpo de verdade. O elenco vai
# de 1,45 m a 2,05 m, e uma cápsula fixa aqui seria a mentira mais fácil de não perceber.
_START_HEIGHT = 1.75


def _scene() -> str:
    half = P.num(_START_HEIGHT / 2.0)
    speech_y = P.num(_START_HEIGHT + P.NPC_SPEAK_HEIGHT)
    return f"""{GENERATED_HEADER('tools/gen_npc.py', 'tools/params.py', ';')}
[gd_scene load_steps=8 format=3]

[ext_resource type="Script" path="{CONTROLLER_SCRIPT}" id="1_npc"]
[ext_resource type="Script" path="{RACE_SCRIPT}" id="2_race"]
[ext_resource type="Script" path="{LOCOMOTION_SCRIPT}" id="3_legs"]
[ext_resource type="Script" path="{INTERACTABLE_SCRIPT}" id="4_talk"]

[sub_resource type="CapsuleShape3D" id="CapsuleShape3D_body"]
radius = {P.num(P.PLAYER_CAPSULE_RADIUS)}
height = {P.num(_START_HEIGHT)}

[sub_resource type="SphereShape3D" id="SphereShape3D_sense"]
radius = {P.num(P.NPC_SENSE_RADIUS)}

[sub_resource type="SphereShape3D" id="SphereShape3D_talk"]
radius = {P.num(P.INTERACT_AREA_RADIUS)}

[node name="NPC" type="CharacterBody3D"]
collision_layer = {P.layer_mask('npc')}
collision_mask = {P.layer_mask('world')}
script = ExtResource("1_npc")

[node name="Collider" type="CollisionShape3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, {half}, 0)
shape = SubResource("CapsuleShape3D_body")

[node name="Race" type="Node3D" parent="."]
script = ExtResource("2_race")
body = &"{P.CHARACTER_ROSTER[0]['name']}"
locomotion_path = NodePath("../Locomotion")
collider_path = NodePath("../Collider")

[node name="Locomotion" type="Node3D" parent="."]
script = ExtResource("3_legs")

[node name="Agent" type="NavigationAgent3D" parent="."]
radius = {P.num(P.NAV_AGENT_RADIUS)}
height = {P.num(P.NAV_AGENT_HEIGHT)}
path_desired_distance = {P.num(P.NPC_ARRIVE_RADIUS / 2.0)}
target_desired_distance = {P.num(P.NPC_ARRIVE_RADIUS)}
avoidance_enabled = true

[node name="Sense" type="Area3D" parent="."]
monitorable = false
collision_layer = {P.layer_mask('trigger')}
collision_mask = {P.layer_mask('player', 'npc')}

[node name="SenseShape" type="CollisionShape3D" parent="Sense"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, {half}, 0)
shape = SubResource("SphereShape3D_sense")

[node name="Talk" type="Area3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, {P.num(P.INTERACT_FOCUS_HEIGHT)}, 0)
script = ExtResource("4_talk")
prompt_text = "Conversar"
focus_height = {P.num(P.INTERACT_FOCUS_HEIGHT)}
owner_path = NodePath("..")

[node name="TalkShape" type="CollisionShape3D" parent="Talk"]
shape = SubResource("SphereShape3D_talk")

[node name="Speech" type="Label3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, {speech_y}, 0)
billboard = 1
no_depth_test = true
fixed_size = true
pixel_size = 0.0035
outline_size = 10
visible = false
"""


def main() -> list[Path]:
    written = write_if_changed(OUTPUT, _scene())

    # A percepção tem de alcançar mais que a chegada, senão o NPC só nota alguém depois de
    # já estar parado em cima dele.
    if P.NPC_SENSE_RADIUS <= P.NPC_ARRIVE_RADIUS:
        raise SystemExit(
            f"NPC_SENSE_RADIUS ({P.NPC_SENSE_RADIUS}) tem de ser maior que "
            f"NPC_ARRIVE_RADIUS ({P.NPC_ARRIVE_RADIUS})."
        )
    # Um habitante mais rápido que o jogador andando lê como fuga, não como rotina.
    if P.NPC_WALK_SPEED >= P.PLAYER_WALK_SPEED:
        raise SystemExit(
            f"NPC_WALK_SPEED ({P.NPC_WALK_SPEED}) alcança o jogador andando "
            f"({P.PLAYER_WALK_SPEED}); o habitante deve andar mais devagar."
        )
    print(f"  npc: {OUTPUT} (percepção {P.num(P.NPC_SENSE_RADIUS)} m, {P.NPC_COUNT} habitantes)")
    return written


if __name__ == "__main__":
    main()
