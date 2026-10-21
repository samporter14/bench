#!/usr/bin/env python3
"""Regenerate Resources/AppIconVariants/<id>.icon, the six icons Settings -> General -> App icon offers.

Capsid's own icon (Resources/AppIcon.icon) is one layer, Assets/bench-glyph.png: the Solanum
broken ring with its escaped dot at the upper right, and inside it an icosahedral capsid, all in
Slate on transparent, 1024 x 1024. This script cuts that one file into three layers by geometry,
exactly (nothing is redrawn), and writes each variant as an Icon Composer document: a tile fill
and the three layers recoloured. Run it again after changing the table below:

    python3 Scripts/make-icon-variants.py            # write the documents
    python3 Scripts/make-icon-variants.py --check    # fail (exit 1) if the committed ones differ

It needs only Pillow and numpy. bench-glyph.png is read, never changed (embed-remote-web.py
embeds it for the phone's icon).

The split is by distance from the centre of the image, because the three parts sit in separate
bands: the capsid is inside radius 180, the ring is 271 to 297, the escaped dot 323 to 364. The
cut is at 230 and 310, in the gaps, and the script stops if a redrawn glyph ever puts ink near
a cut, leaves a band empty, or moves the escaped dot out of the upper right. The bands cover
every pixel exactly once, so the three layers add back to the glyph with nothing lost and
nothing doubled. The script proves it from the PNGs it wrote (not from memory): the Clay
document's layers, which keep the glyph's own colours, composite to bench-glyph.png byte for
byte, and every other document's layers have the same alpha, so their antialiasing is the
glyph's, with a single colour where there is ink.

Colours are Solanum's (the brand allows exactly three icon grounds: Ivory, Slate and Clay).
Structure (the ring and the capsid) takes ink; the organism (the escaped dot) takes Clay; a
one-colour version sets everything to ink. On a Slate tile the ink is Ivory.
"""
import io
import json
import pathlib
import sys

import numpy as np
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
GLYPH = ROOT / "Resources/AppIcon.icon/Assets/bench-glyph.png"
OUT = ROOT / "Resources/AppIconVariants"

IVORY = (250, 249, 245)  # #FAF9F5
SLATE = (20, 20, 19)  # #141413
CLAY = (217, 119, 87)  # #D97757
INK = None  # the glyph's own Slate, untouched (it is not one flat value: its edges are antialiased)

GROUNDS = {"clay": CLAY, "ivory": IVORY, "slate": SLATE}

# id: (tile, ring, capsid, escaped dot). INK on a layer means "leave the glyph's own Slate".
VARIANTS = {
    "clay": ("clay", INK, INK, INK),  # today's icon
    "ivory": ("ivory", INK, INK, CLAY),
    "slate": ("slate", IVORY, CLAY, CLAY),
    "ivoryMono": ("ivory", INK, INK, INK),
    "slateMono": ("slate", IVORY, IVORY, IVORY),
    "ivoryClay": ("ivory", INK, CLAY, CLAY),
}
LAYERS = ["ring", "capsid", "escapee"]  # the file names too: ring.png, capsid.png, escapee.png

# Where the three bands are cut, as distances from the centre of the 1024 px image.
CENTRE = 511.5
CUT_CAPSID_RING = 230
CUT_RING_ESCAPEE = 310
CUT_MARGIN = 5  # no ink may lie this close to a cut


def srgb(rgb):
    """Icon Composer's colour string, five decimals like the original document."""
    r, g, b = (c / 255 for c in rgb)
    return f"srgb:{r:.5f},{g:.5f},{b:.5f},1.00000"


def load_glyph():
    image = Image.open(GLYPH)
    if image.size != (1024, 1024) or image.mode != "RGBA":
        sys.exit(f"{GLYPH}: expected 1024 x 1024 RGBA, found {image.size} {image.mode}")
    return np.array(image)


def bands(glyph):
    """Three boolean masks (ring, capsid, escapee) that partition the whole image."""
    ys, xs = np.mgrid[0:1024, 0:1024]
    radius = np.hypot(xs - CENTRE, ys - CENTRE)
    ink = glyph[..., 3] > 0
    masks = {
        "capsid": radius < CUT_CAPSID_RING,
        "ring": (radius >= CUT_CAPSID_RING) & (radius < CUT_RING_ESCAPEE),
        "escapee": radius >= CUT_RING_ESCAPEE,
    }
    for name, mask in masks.items():
        if not (mask & ink).any():
            sys.exit(f"the {name} band holds no ink: the glyph has changed, so the cuts need a look")
    for cut in (CUT_CAPSID_RING, CUT_RING_ESCAPEE):
        near = ink & (abs(radius - cut) < CUT_MARGIN)
        if near.any():
            sys.exit(f"ink lies within {CUT_MARGIN} px of the cut at radius {cut} "
                     f"({int(near.sum())} pixels): the glyph has changed, so the cuts need a look")
    ys_e, xs_e = np.nonzero(masks["escapee"] & ink)
    if not (xs_e.min() > 512 and ys_e.max() < 512):
        sys.exit("the escaped dot is no longer in the upper right")
    # The ring is the annulus, the capsid lies inside it, the dot outside: assert the order.
    span = {name: (radius[mask & ink].min(), radius[mask & ink].max()) for name, mask in masks.items()}
    if not (span["capsid"][1] < span["ring"][0] and span["ring"][1] < span["escapee"][0]):
        sys.exit(f"the bands are not nested capsid, ring, dot: {span}")
    return masks


def split(glyph, masks):
    """The glyph's three parts, as RGBA arrays that are zero outside their own band."""
    parts = {}
    for name, mask in masks.items():
        part = np.zeros_like(glyph)
        part[mask] = glyph[mask]
        parts[name] = part
    return parts


def recolour(part, rgb):
    """The same alpha, one colour where there is ink. RGB stays (0, 0, 0) where alpha is 0, as the glyph has it."""
    if rgb is INK:
        return part
    out = part.copy()
    out[..., :3] = 0
    out[part[..., 3] > 0, :3] = rgb
    return out


def png(array):
    buffer = io.BytesIO()
    Image.fromarray(array).save(buffer, "PNG", optimize=True)  # uint8, (1024, 1024, 4): RGBA
    return buffer.getvalue()


def document(identifier):
    """The icon.json: the original document's settings, the tile as an sRGB solid, three layers."""
    tile = GROUNDS[VARIANTS[identifier][0]]
    layers = [
        {
            "hidden": False,
            "image-name": f"{name}.png",
            "name": name,
            "position": {"scale": 1.0, "translation-in-points": [0, 0]},
        }
        for name in LAYERS
    ]
    return json.dumps(
        {
            "fill": {"solid": srgb(tile)},
            "groups": [
                {
                    "layers": layers,
                    "shadow": {"kind": "none", "opacity": 0.5},
                    "translucency": {"enabled": False, "value": 0.5},
                    "specular": False,
                }
            ],
            "supported-platforms": {"circles": ["watchOS"], "squares": "shared"},
        },
        indent=2,
    ) + "\n"


def files(glyph):
    """Every file of every document: {relative path: bytes}."""
    parts = split(glyph, bands(glyph))
    result = {}
    for identifier, (_, *colours) in VARIANTS.items():
        base = f"{identifier}.icon"
        result[f"{base}/icon.json"] = document(identifier).encode()
        for name, colour in zip(LAYERS, colours):
            result[f"{base}/Assets/{name}.png"] = png(recolour(parts[name], colour))
    return result


def read(path):
    return np.array(Image.open(path))


def verify(glyph):
    """Check the documents on disk against the glyph. Reads the PNGs back; exits on the first failure."""
    problems = []
    for identifier, (tile, *colours) in VARIANTS.items():
        base = OUT / f"{identifier}.icon"
        try:
            icon = json.loads((base / "icon.json").read_text())
        except (OSError, ValueError) as error:
            problems.append(f"{identifier}: icon.json unreadable ({error})")
            continue
        if icon["fill"]["solid"] != srgb(GROUNDS[tile]):
            problems.append(f"{identifier}: tile fill {icon['fill']['solid']} is not {tile}")
        names = [layer["image-name"] for layer in icon["groups"][0]["layers"]]
        if names != [f"{name}.png" for name in LAYERS]:
            problems.append(f"{identifier}: layers are {names}")
            continue
        try:
            layers = {name: read(base / "Assets" / f"{name}.png") for name in LAYERS}
        except OSError as error:
            problems.append(f"{identifier}: {error}")
            continue
        # The layers' ink is disjoint, and its union is the glyph's ink, with the glyph's alpha.
        count = sum((layer[..., 3] > 0).astype(int) for layer in layers.values())
        if count.max() > 1:
            problems.append(f"{identifier}: two layers have ink on the same pixel")
        alpha = np.maximum.reduce([layer[..., 3] for layer in layers.values()])
        if not np.array_equal(alpha, glyph[..., 3]):
            problems.append(f"{identifier}: the layers' alpha is not the glyph's")
        # Each layer is one colour where it has ink (or the glyph's own, for ink), and clear elsewhere.
        for name, colour in zip(LAYERS, colours):
            layer = layers[name]
            inked = layer[..., 3] > 0
            if layer[~inked][:, :3].any():
                problems.append(f"{identifier}/{name}: colour where alpha is 0")
            if colour is not INK and not (layer[inked][:, :3] == colour).all():
                problems.append(f"{identifier}/{name}: not one colour {colour}")
            if colour is INK and not np.array_equal(layer[inked], glyph[inked]):
                problems.append(f"{identifier}/{name}: Slate layer differs from the glyph")
        # Where the layer is the glyph's own colours, stacking the layers gives the glyph back exactly.
        if all(colour is INK for colour in colours):
            stacked = np.zeros_like(glyph)
            for layer in layers.values():
                mask = layer[..., 3] > 0
                stacked[mask] = layer[mask]
            if not np.array_equal(stacked, glyph):
                problems.append(f"{identifier}: the layers do not composite to bench-glyph.png pixel for pixel")
    if problems:
        sys.exit("verification failed:\n  " + "\n  ".join(problems))


def main():
    check = "--check" in sys.argv[1:]
    glyph = load_glyph()
    wanted = files(glyph)
    if check:
        stale = []
        for relative, data in wanted.items():
            path = OUT / relative
            if not path.exists():
                stale.append(f"{relative}: missing")
            elif relative.endswith(".png"):
                # Compared as pixels: another Pillow may compress the same pixels differently.
                if not np.array_equal(read(path), np.array(Image.open(io.BytesIO(data)))):
                    stale.append(f"{relative}: pixels differ")
            elif path.read_bytes() != data:
                stale.append(f"{relative}: differs")
        on_disk = {p.name for p in OUT.glob("*.icon")}
        for extra in sorted(on_disk - {f"{i}.icon" for i in VARIANTS}):
            stale.append(f"{extra}: not in the table")
        if stale:
            sys.exit("Resources/AppIconVariants is out of date; run Scripts/make-icon-variants.py:\n  " + "\n  ".join(stale))
    else:
        for relative, data in wanted.items():
            path = OUT / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
    verify(glyph)
    print(("Checked" if check else "Wrote") + f" {len(VARIANTS)} icon documents in {OUT.relative_to(ROOT)}; "
          "the layers composite back to bench-glyph.png.")


if __name__ == "__main__":
    main()
