"""Gera `scenes/player/player.tscn`.

A cena do jogador é a primeira do projeto com hierarquia de verdade — corpo, colisor,
aplicador de povo, locomoção, braço de câmera e câmera — e é exatamente por isso que ela
tem de nascer daqui. Uma cena montada no editor vira o arquivo que ninguém revisa: o diff
de um `.tscn` arrastado à mão é ilegível, e a próxima pessoa que mexer numa altura de
cápsula não vai saber que ela devia ter vindo de `params.py`.

`Race` é um `Node3D`, e não um `Node`. Parece detalhe e não é: a propagação de
transformação do Godot sobe pela cadeia de `Node3D`, e um `Node` cru no meio a corta. Com
ele, a malha do personagem ficava cravada na origem enquanto a cápsula andava — o corpo
some do quadro e todos os números de velocidade continuam corretos, porque quem se move é
o colisor. Foi encontrado olhando a tira do `make playtest`, não lendo log.

O que fica de fora de propósito: nenhuma medida do corpo. A cápsula nasce com um valor de
partida e é o `RaceApplier` que a redimensiona quando monta a malha — o elenco vai de
1,45 m a 2,05 m, e uma cápsula fixa aqui seria a mentira mais fácil de não perceber.
"""

from __future__ import annotations

from pathlib import Path

from . import params as P
from .util import GENERATED_HEADER, write_if_changed

OUTPUT = Path(P.PLAYER_SCENE)

CONTROLLER_SCRIPT = "res://scripts/gameplay/player_controller.gd"
RACE_SCRIPT = "res://scripts/gameplay/race_applier.gd"
LOCOMOTION_SCRIPT = "res://scripts/gameplay/procedural_locomotion.gd"
CAMERA_SCRIPT = "res://scripts/gameplay/third_person_camera.gd"
SENSOR_SCRIPT = "res://scripts/gameplay/interaction_sensor.gd"

# Altura de partida da cápsula, só até o RaceApplier medir o corpo de verdade.
_START_HEIGHT = 1.8


def _scene() -> str:
    radius = P.num(P.PLAYER_CAPSULE_RADIUS)
    height = P.num(_START_HEIGHT)
    half = P.num(_START_HEIGHT / 2.0)
    return f"""{GENERATED_HEADER('tools/gen_player.py', 'tools/params.py', ';')}
[gd_scene load_steps=7 format=3]

[ext_resource type="Script" path="{CONTROLLER_SCRIPT}" id="1_player"]
[ext_resource type="Script" path="{RACE_SCRIPT}" id="2_race"]
[ext_resource type="Script" path="{LOCOMOTION_SCRIPT}" id="3_legs"]
[ext_resource type="Script" path="{CAMERA_SCRIPT}" id="4_camera"]
[ext_resource type="Script" path="{SENSOR_SCRIPT}" id="5_sensor"]

[sub_resource type="CapsuleShape3D" id="CapsuleShape3D_body"]
radius = {radius}
height = {height}

[node name="Player" type="CharacterBody3D"]
collision_layer = {P.layer_mask('player')}
collision_mask = {P.layer_mask('world')}
script = ExtResource("1_player")
locomotion_path = NodePath("Locomotion")
camera_path = NodePath("CameraArm")
race_path = NodePath("Race")
sensor_path = NodePath("Sensor")

[node name="Collider" type="CollisionShape3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, {half}, 0)
shape = SubResource("CapsuleShape3D_body")

[node name="Race" type="Node3D" parent="."]
script = ExtResource("2_race")
body = &"{P.PLAYER_BODY}"
locomotion_path = NodePath("../Locomotion")
collider_path = NodePath("../Collider")

[node name="Locomotion" type="Node3D" parent="."]
script = ExtResource("3_legs")

[node name="Sensor" type="Area3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, {half}, 0)
script = ExtResource("5_sensor")

[node name="CameraArm" type="SpringArm3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, {half}, 0)
spring_length = {P.num(P.CAMERA_DISTANCE)}
margin = {P.num(P.CAMERA_SPRING_MARGIN)}
collision_mask = {P.layer_mask('world')}
script = ExtResource("4_camera")

[node name="Camera3D" type="Camera3D" parent="CameraArm"]
fov = {P.num(P.CAMERA_FOV)}
far = {P.num(P.STAGE_CAMERA_FAR)}
"""


def main() -> list[Path]:
    if P.PLAYER_BODY not in {spec["name"] for spec in P.CHARACTER_ROSTER}:
        raise SystemExit(
            f"tools/params.py: PLAYER_BODY={P.PLAYER_BODY!r} não está em CHARACTER_ROSTER."
        )
    if P.CAMERA_PITCH_MIN_DEG >= P.CAMERA_PITCH_MAX_DEG:
        raise SystemExit("tools/params.py: o pitch mínimo da câmera não é menor que o máximo.")
    if P.PLAYER_DECELERATION < P.PLAYER_ACCELERATION:
        raise SystemExit(
            "tools/params.py: desacelerar mais devagar do que acelerar faz o corpo patinar "
            "ao soltar o comando. Se for intencional, mude esta checagem junto."
        )

    written = write_if_changed(OUTPUT, _scene())
    print(
        f"  jogador: {OUTPUT} — corpo {P.PLAYER_BODY}, "
        f"{P.num(P.PLAYER_WALK_SPEED)}/{P.num(P.PLAYER_RUN_SPEED)} m/s, "
        f"salto de {P.num(P.PLAYER_JUMP_HEIGHT)} m"
    )
    return written


if __name__ == "__main__":
    main()
