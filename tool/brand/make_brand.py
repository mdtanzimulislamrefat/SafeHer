"""Builds the SafeHer logo SVGs and every Android icon size from one definition.

The mark: her (the amber dot) at the centre, held by her circle of three (the arcs).

Run from the repo root:  python3 tool/brand/make_brand.py
Needs ImageMagick (`magick`) for the PNGs.
"""
import math
import os
import shutil
import subprocess
import tempfile

PLUM, PAPER, AMBER, WHITE = '#4B1D6B', '#FAF6F1', '#F2B544', '#FFFFFF'

# Geometry in a 1024 box; the outer edge of the ring reaches 300 + 74/2 = 337 from the centre.
R, WIDTH, DOT, SPAN = 300, 74, 118, 84
ARC_CENTRES = (-90, 30, 150)
OUTER = R + WIDTH / 2

RES = 'android/app/src/main/res'
DENSITIES = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}


def _arc(cx, cy, r, a1, a2):
    p = lambda a: (cx + r * math.cos(math.radians(a)), cy + r * math.sin(math.radians(a)))
    (x1, y1), (x2, y2) = p(a1), p(a2)
    return f'M{x1:.2f} {y1:.2f} A{r:.2f} {r:.2f} 0 0 1 {x2:.2f} {y2:.2f}'


def mark(cx, cy, outer_radius, ring, dot):
    """The mark centred at (cx, cy), scaled so the ring's outer edge is outer_radius."""
    s = outer_radius / OUTER
    arcs = ''.join(
        f'<path d="{_arc(cx, cy, R * s, c - SPAN / 2, c + SPAN / 2)}" fill="none" stroke="{ring}" '
        f'stroke-width="{WIDTH * s:.2f}" stroke-linecap="round"/>'
        for c in ARC_CENTRES
    )
    return arcs + f'<circle cx="{cx}" cy="{cy}" r="{DOT * s:.2f}" fill="{dot}"/>'


def svg(size, body, bg=None, radius=0):
    back = f'<rect width="{size}" height="{size}" rx="{radius}" fill="{bg}"/>' if bg else ''
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" '
            f'viewBox="0 0 {size} {size}">{back}{body}</svg>\n')


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w') as f:
        f.write(text)


def render(svg_text, out_png, px):
    os.makedirs(os.path.dirname(out_png), exist_ok=True)
    with tempfile.NamedTemporaryFile('w', suffix='.svg', delete=False) as t:
        t.write(svg_text)
    try:
        subprocess.run(['magick', '-background', 'none', '-density', '384', t.name, '-resize', f'{px}x{px}',
                        out_png], check=True)
    finally:
        os.unlink(t.name)


def main():
    # Masters, for docs, the deck and Figma.
    write('assets/brand/safeher_icon.svg', svg(1024, mark(512, 512, OUTER, PAPER, AMBER), PLUM, 232))
    write('assets/brand/safeher_mark.svg', svg(1024, mark(512, 512, 480, PLUM, AMBER)))
    write('assets/brand/safeher_mark_on_dark.svg', svg(1024, mark(512, 512, 480, PAPER, AMBER)))
    write('assets/brand/safeher_mark_mono.svg', svg(1024, mark(512, 512, 480, WHITE, WHITE)))

    icon = svg(1024, mark(512, 512, OUTER, PAPER, AMBER), PLUM, 232)
    # Adaptive icon layers: 108dp canvas, the mark kept well inside the 66dp safe circle.
    foreground = svg(1080, mark(540, 540, 290, PAPER, AMBER))
    monochrome = svg(1080, mark(540, 540, 290, WHITE, WHITE))
    # Status-bar icon: Android uses only the alpha, so a white silhouette.
    status = svg(240, mark(120, 120, 112, WHITE, WHITE))
    # Pre-Android-12 splash: the mark on the plum launch background.
    splash = svg(1200, mark(600, 600, 560, PAPER, AMBER))

    for name, scale in DENSITIES.items():
        render(icon, f'{RES}/mipmap-{name}/ic_launcher.png', round(48 * scale))
        render(foreground, f'{RES}/mipmap-{name}/ic_launcher_foreground.png', round(108 * scale))
        render(monochrome, f'{RES}/mipmap-{name}/ic_launcher_monochrome.png', round(108 * scale))
        render(status, f'{RES}/drawable-{name}/ic_stat_safeher.png', round(24 * scale))
        render(splash, f'{RES}/drawable-{name}/splash_mark.png', round(120 * scale))

    write(f'{RES}/mipmap-anydpi-v26/ic_launcher.xml', '''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>
</adaptive-icon>
''')
    write(f'{RES}/values/colors.xml', f'''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">{PLUM}</color>
    <color name="splash_background">{PLUM}</color>
</resources>
''')
    print('brand assets written')


if __name__ == '__main__':
    if not shutil.which('magick'):
        raise SystemExit('ImageMagick (magick) is needed to render the PNGs.')
    main()
