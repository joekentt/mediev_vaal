"""Renderiza um contato de cada peça do kit — os olhos que faltavam.

Quem escreve um gerador não vê o que ele gera. Até aqui a fábrica dizia "76 triângulos,
dentro do orçamento" e ninguém sabia se a árvore parecia uma árvore. Este módulo abre
cada `.glb` do manifesto e produz um PNG com quatro ângulos e uma figura humana ao lado,
para que o tamanho signifique alguma coisa.

**Uma renderização por peça, não quatro.** A câmera é ortográfica e fixa, olhando ao
longo de -Y; o que muda entre os quadrantes é a rotação da *cópia* da peça. Frente, 3/4 e
lateral são giros em Z; o topo é um giro em X. Quatro renderizações por peça custariam
quatro vezes mais por exatamente o mesmo resultado.

**A figura de escala não é um personagem.** É uma régua com forma de gente: proporções
canônicas, sem rosto, sem esqueleto, sem animação, e nunca exportada para o kit. Existe
só para responder "isto dá na cintura ou passa da cabeça?", que é a pergunta que uma
bounding box em metros não responde.
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from tools import params as P  # noqa: E402

IMAGE_DIR = ROOT / P.PREVIEW_IMAGE_DIR
MANIFEST = ROOT / P.KIT_DIR / "manifest.json"

# Proporções da figura de escala, como fração da altura total.
_FIGURE = {
    "head": 0.13, "neck": 0.04, "torso": 0.30, "hip": 0.06,
    "leg": 0.47, "shoulder_span": 0.26, "depth": 0.13,
}
_CELL_COLUMNS = 2
_ORTHO_MARGIN = 1.06


def _sun_direction(elevation_deg: float, azimuth_deg: float) -> tuple[float, float, float]:
    """Rotação Euler de um sol que aponta para a origem a partir de (elevação, azimute)."""
    return (math.radians(90.0 - elevation_deg), 0.0, math.radians(azimuth_deg))


def build_scale_figure(height: float = P.PREVIEW_FIGURE_HEIGHT):
    """Régua antropomórfica: caixas empilhadas nas proporções de uma pessoa de pé.

    Devolve um BMesh. Não vai para `assets/generated/kit/`, não tem osso, não tem UV e
    não entra no jogo — se um dia entrar, terá sido gerada por `kit_*.py` como qualquer
    outra peça, e não por aqui.
    """
    from tools import meshlib as M

    bm = M.new_bmesh()
    leg = height * _FIGURE["leg"]
    hip = height * _FIGURE["hip"]
    torso = height * _FIGURE["torso"]
    neck = height * _FIGURE["neck"]
    head = height * _FIGURE["head"]
    span = height * _FIGURE["shoulder_span"]
    depth = height * _FIGURE["depth"]

    leg_width = span * 0.30
    for side in (-1.0, 1.0):
        M.add_box(
            bm,
            (side * leg_width * 0.62 - leg_width * 0.5, -depth * 0.5, 0.0),
            (leg_width, depth * 0.8, leg),
            "slate",
        )
    M.add_box(bm, (-span * 0.42, -depth * 0.5, leg), (span * 0.84, depth, hip), "slate")
    M.add_box(bm, (-span * 0.5, -depth * 0.5, leg + hip), (span, depth, torso), "slate")
    M.add_box(
        bm, (-span * 0.18, -depth * 0.35, leg + hip + torso), (span * 0.36, depth * 0.7, neck),
        "slate",
    )
    M.add_box(
        bm, (-span * 0.28, -depth * 0.45, leg + hip + torso + neck),
        (span * 0.56, depth * 0.9, head), "slate",
    )
    arm = span * 0.18
    for side in (-1.0, 1.0):
        M.add_box(
            bm,
            (side * (span * 0.5 + arm * 0.1) - (arm * 0.5 if side > 0 else arm * 0.5),
             -depth * 0.35, leg + hip + torso * 0.05),
            (arm, depth * 0.6, torso * 0.92),
            "slate",
        )
    return bm


def _clear_scene() -> None:
    import bpy

    bpy.ops.wm.read_factory_settings(use_empty=True)


def _setup_world(background_hex: str) -> None:
    import bpy

    world = bpy.data.worlds.new("preview")
    bpy.context.scene.world = world
    world.use_nodes = True
    background = world.node_tree.nodes.get("Background")
    if background is not None:
        red, green, blue = P.hex_to_rgb(background_hex)
        background.inputs["Color"].default_value = (
            P.srgb_to_linear(red), P.srgb_to_linear(green), P.srgb_to_linear(blue), 1.0
        )


def _setup_lights() -> None:
    import bpy

    for name, elevation, azimuth, energy in P.PREVIEW_LIGHTS:
        light_data = bpy.data.lights.new(name, "SUN")
        light_data.energy = energy
        light_data.angle = math.radians(P.SUN_ANGLE_MAX)
        light = bpy.data.objects.new(name, light_data)
        light.rotation_euler = _sun_direction(elevation, azimuth)
        bpy.context.scene.collection.objects.link(light)


def _setup_render(size: int) -> None:
    import bpy

    scene = bpy.context.scene
    # Cycles em CPU: o EEVEE e o Workbench são rasterizadores de OpenGL e precisam de um
    # contexto gráfico, que não existe num contêiner sem GPU (`libEGL.so.1` ausente) —
    # e ali eles derrubam o processo em vez de reclamar. O Cycles roda em qualquer lugar.
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = P.PREVIEW_SAMPLES
    scene.cycles.use_denoising = False
    scene.cycles.seed = P.KIT_SEED
    scene.render.resolution_x = size
    scene.render.resolution_y = size
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "Standard"


def _load_part(path: Path):
    """Importa um `.glb` e devolve a malha em pé, no espaço Z-up do Blender.

    O `.glb` é Y-up e o importador compensa isso com uma rotação de 90° em X, guardada na
    hierarquia que ele cria. Zerar a `matrix_world` para "limpar" a hierarquia — que foi a
    primeira tentativa — joga essa correção fora e deixa a peça deitada de costas: os
    quatro ângulos renderizavam a mesma vista de topo, e o erro parecia estar na rotação
    das cópias. A correção é *assar* a transformação nos vértices, não descartá-la.
    """
    import bpy
    from mathutils import Matrix

    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(path))
    imported = [obj for obj in bpy.data.objects if obj not in before]
    meshes = [obj for obj in imported if obj.type == "MESH"]
    if not meshes:
        raise RuntimeError(f"{path.name}: nenhuma malha no arquivo")

    mesh = meshes[0]
    world = mesh.matrix_world.copy()
    mesh.parent = None
    mesh.data.transform(world)
    mesh.matrix_world = Matrix.Identity(4)

    for obj in imported:
        if obj is not mesh:
            bpy.data.objects.remove(obj, do_unlink=True)
    return mesh


def _world_bounds(obj) -> tuple[tuple[float, float, float], tuple[float, float, float]]:
    from mathutils import Vector

    corners = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    return (
        (min(c.x for c in corners), min(c.y for c in corners), min(c.z for c in corners)),
        (max(c.x for c in corners), max(c.y for c in corners), max(c.z for c in corners)),
    )


def _place_copy(source, rotation_deg: tuple[float, float, float], cell_center):
    """Duplica a peça, aplica a rotação do ângulo e centra a cópia na célula."""
    import bpy
    from mathutils import Euler, Vector

    copy = source.copy()
    copy.data = source.data
    bpy.context.scene.collection.objects.link(copy)

    # `rotation_mode` antes de `rotation_euler`, e não é detalhe: o importador de glTF
    # deixa os objetos em modo QUATERNION (é assim que o formato guarda rotação), e nesse
    # modo o `rotation_euler` é *escrito e ignorado*. O objeto reportava a rotação certa
    # quando perguntado e renderizava sem rotação nenhuma — os quatro ângulos saíam
    # idênticos e a culpa parecia ser da câmera.
    copy.rotation_mode = "XYZ"
    copy.rotation_euler = Euler([math.radians(value) for value in rotation_deg], "XYZ")
    bpy.context.view_layer.update()

    (min_x, min_y, min_z), (max_x, max_y, max_z) = _world_bounds(copy)
    center = Vector(((min_x + max_x) * 0.5, (min_y + max_y) * 0.5, (min_z + max_z) * 0.5))
    copy.location = Vector(cell_center) - center
    bpy.context.view_layer.update()
    return copy


def render_part(entry: dict, source_dir: Path, output: Path) -> None:
    """Renderiza os quatro ângulos de uma peça, com a figura de escala à esquerda."""
    import bpy
    from mathutils import Vector

    from tools import meshlib as M

    _clear_scene()
    _setup_world(P.PREVIEW_BACKGROUND)
    _setup_lights()
    _setup_render(P.PREVIEW_SIZE)

    part = _load_part(source_dir / entry["file"])
    size = entry["size"]
    extent = max(max(size), P.PREVIEW_FIGURE_HEIGHT)
    cell = extent * P.PREVIEW_MARGIN

    # A figura ocupa uma coluna própria à esquerda; a grade 2x2 fica à direita dela.
    figure_column = P.PREVIEW_FIGURE_HEIGHT * 0.5 + P.PREVIEW_FIGURE_GAP
    grid_width = cell * _CELL_COLUMNS
    total_width = figure_column + grid_width
    grid_left = -total_width * 0.5 + figure_column

    for index, (_label, rotation) in enumerate(P.PREVIEW_ANGLES):
        column = index % _CELL_COLUMNS
        row = index // _CELL_COLUMNS
        center = (
            grid_left + cell * (column + 0.5),
            0.0,
            cell * (0.5 - row) - cell * 0.5 + cell * 0.5,
        )
        _place_copy(part, rotation, center)

    bpy.data.objects.remove(part, do_unlink=True)

    figure_bm = build_scale_figure()
    figure_material = M.flat_material("preview_flat")
    figure = M.to_object(figure_bm, "scale_figure", figure_material)
    figure_bm.free()
    figure.location = Vector((-total_width * 0.5 + figure_column * 0.5, 0.0, -cell * 0.5))

    camera_data = bpy.data.cameras.new("preview")
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = max(total_width, cell * _CELL_COLUMNS) * _ORTHO_MARGIN
    camera = bpy.data.objects.new("preview", camera_data)
    camera.location = Vector((0.0, -extent * 8.0 - P.PREVIEW_FIGURE_HEIGHT, 0.0))
    camera.rotation_euler = (math.radians(90.0), 0.0, 0.0)
    bpy.context.scene.collection.objects.link(camera)
    bpy.context.scene.camera = camera

    output.parent.mkdir(parents=True, exist_ok=True)
    bpy.context.scene.render.filepath = str(output)
    bpy.ops.render.render(write_still=True)


def run_in_blender(selected: list[str]) -> int:
    import json

    if not MANIFEST.exists():
        print(f"ERRO: {MANIFEST.relative_to(ROOT)} não existe. Rode `make assets`.", file=sys.stderr)
        return 1

    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    parts = manifest["parts"]
    if selected:
        parts = [entry for entry in parts if entry["name"] in selected]

    IMAGE_DIR.mkdir(parents=True, exist_ok=True)
    for entry in parts:
        output = IMAGE_DIR / f"{entry['name']}.png"
        render_part(entry, ROOT / P.KIT_DIR, output)
        print(f"  {entry['name']:<16} {output.relative_to(ROOT)}")
    print(f"  {len(parts)} peças renderizadas em {IMAGE_DIR.relative_to(ROOT)}")
    return 0


def main(argv: list[str] | None = None) -> int:
    from tools import gen_assets

    argv = sys.argv[1:] if argv is None else argv
    selected = [arg for arg in argv if not arg.startswith("-")]
    return gen_assets.dispatch(Path(__file__), run_in_blender, selected)


if __name__ == "__main__":
    from tools import gen_assets

    if gen_assets._is_inside_blender():
        raise SystemExit(run_in_blender(gen_assets.script_args()))
    raise SystemExit(main())
