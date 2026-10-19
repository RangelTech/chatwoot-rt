#!/usr/bin/env python3
"""Gera os ativos de marca LUAR (SVG + PNG + ICO) a partir de uma unica geometria.

Uso:  python branding/build_assets.py [--svg-only]
Requer: playwright (pip install playwright) e Google Chrome instalado (canal 'chrome').
Os arquivos gerados sao versionados; rode de novo somente se a geometria mudar.

Geometria do simbolo: disco de diametro 100 (centro 50,50) com UM recorte curvo vazado
(transparencia real, via fill-rule evenodd), formado por dois arcos que partem do topo e
terminam no lado direito. Mesma geometria no claro e no escuro. Sem gradiente, estrela
ou crescente isolado. Wordmark em paths proprios (sem fonte).
"""
import math
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PUBLIC = ROOT / 'public'
ASSETS = PUBLIC / 'brand-assets'

BLUE = '#75C8F2'
NIGHT = '#0A1733'
WHITE = '#FFFFFF'
RED = '#FF3B30'

# --- simbolo -----------------------------------------------------------------
R_OUT = 43.5           # raio do arco externo do recorte (concentrico ao disco; sobra aro de 5.5)
A1, A2 = -105.0, 30.0  # angulos (graus) onde o recorte comeca (topo) e termina (direita)
THICK = 12.0           # espessura maxima do recorte, em unidades do disco (100)


def _pt(angle):
    a = math.radians(angle)
    return 50 + R_OUT * math.cos(a), 50 + R_OUT * math.sin(a)


def _f(v):
    return f'{v:.2f}'.rstrip('0').rstrip('.')


def moon_path():
    p1, p2 = _pt(A1), _pt(A2)
    half = math.dist(p1, p2) / 2
    sag_out = R_OUT - math.sqrt(R_OUT**2 - half**2)
    sag_in = sag_out - THICK
    r_in = (half**2 + sag_in**2) / (2 * sag_in)
    return (
        'M50 0A50 50 0 1 1 50 100A50 50 0 1 1 50 0Z'
        f'M{_f(p1[0])} {_f(p1[1])}A{_f(R_OUT)} {_f(R_OUT)} 0 0 1 {_f(p2[0])} {_f(p2[1])}'
        f'A{_f(r_in)} {_f(r_in)} 0 0 0 {_f(p1[0])} {_f(p1[1])}Z'
    )


MOON = moon_path()

# Letras L U A R (coordenadas locais, altura 52); copiadas do kit aprovado.
WORD_PATHS = [
    (0, 'M0 0H8.5V43.5H30V52H0Z'),
    (41, 'M0 0V32.0A20 20 0 0 0 40 32.0V0H31.5V32.0A11.5 11.5 0 0 1 8.5 32.0V0Z'),
    (92, 'M0 52L18 0H28L10.5 52ZM18 0H28L46 52H35.5ZM11 36H35V43.5H11Z'),
    (149, 'M0 0H19A15 15 0 0 1 19 30H8.5V52H0ZM8.5 8.5V21.5H19A6.5 6.5 0 0 0 19 8.5ZM16 22.5H27L38 52H27.5Z'),
]


def symbol_svg(color=BLUE, size=100):
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 100 100" '
        f'role="img" aria-label="Luar"><title>LUAR</title>'
        f'<path fill="{color}" fill-rule="evenodd" d="{MOON}"/></svg>\n'
    )


def lockup_svg(moon_color, word_color):
    word = ''.join(f'<path fill="{word_color}" transform="translate({x} 0)" d="{d}"/>' for x, d in WORD_PATHS)
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" width="352.04" height="150" viewBox="0 0 352.04 150" '
        'role="img" aria-label="Luar"><title>LUAR</title>'
        f'<g transform="translate(25 25)"><path fill="{moon_color}" fill-rule="evenodd" d="{MOON}"/></g>'
        f'<g transform="translate(155 51.08) scale(0.92)">{word}</g></svg>\n'
    )


def write_svgs():
    ASSETS.mkdir(parents=True, exist_ok=True)
    files = {
        'logo.svg': lockup_svg(BLUE, NIGHT),
        'logo_dark.svg': lockup_svg(BLUE, WHITE),
        'logo_thumbnail.svg': symbol_svg(BLUE),
        # versoes monocromaticas (uma cor so: impressao, carimbo, fundo colorido)
        'logo_mono.svg': lockup_svg(NIGHT, NIGHT),
        'logo_mono_white.svg': lockup_svg(WHITE, WHITE),
        'logo_thumbnail_mono.svg': symbol_svg(NIGHT),
        'logo_thumbnail_mono_white.svg': symbol_svg(WHITE),
    }
    for name, content in files.items():
        (ASSETS / name).write_text(content, encoding='utf-8', newline='\n')


# --- PNG ---------------------------------------------------------------------
def icon_svg(size, bg=None, fill=0.94, badge=False, color=BLUE):
    """Simbolo centralizado em `size` px. fill = fracao do lado ocupada pelo disco."""
    d = size * fill
    off = (size - d) / 2
    s = d / 100
    parts = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 {size} {size}">']
    if bg:
        parts.append(f'<rect width="{size}" height="{size}" fill="{bg}"/>')
    moon = f'<g transform="translate({off} {off}) scale({s})"><path fill="{color}" fill-rule="evenodd" d="{MOON}"/></g>'
    if badge:
        # anel transparente ao redor do ponto, para o aviso nao "colar" na lua
        cx, cy, rr = size * 0.76, size * 0.24, size * 0.22
        parts.append(
            f'<defs><mask id="m"><rect width="{size}" height="{size}" fill="#fff"/>'
            f'<circle cx="{cx}" cy="{cy}" r="{rr + size * 0.06}" fill="#000"/></mask></defs>'
            f'<g mask="url(#m)">{moon}</g><circle cx="{cx}" cy="{cy}" r="{rr}" fill="{RED}"/>'
        )
    else:
        parts.append(moon)
    parts.append('</svg>')
    return ''.join(parts)


def jobs():
    """(arquivo, largura, altura, svg, fundo CSS ou None para transparente)"""
    out = []
    for n in (16, 32, 96, 512):
        out.append((PUBLIC / f'favicon-{n}x{n}.png', n, n, icon_svg(n, fill=1.0 if n <= 32 else 0.94), None))
    for n in (16, 32, 96):
        out.append((PUBLIC / f'favicon-badge-{n}x{n}.png', n, n, icon_svg(n, fill=1.0 if n <= 32 else 0.94, badge=True), None))
    for n in (36, 48, 72, 96, 144, 192):
        out.append((PUBLIC / f'android-icon-{n}x{n}.png', n, n, icon_svg(n, fill=0.9), None))
    for n in (57, 60, 72, 76, 114, 120, 144, 152, 180):
        out.append((PUBLIC / f'apple-icon-{n}x{n}.png', n, n, icon_svg(n, bg=NIGHT, fill=0.62), NIGHT))
    for name in ('apple-icon.png', 'apple-icon-precomposed.png', 'apple-touch-icon.png', 'apple-touch-icon-precomposed.png'):
        out.append((PUBLIC / name, 180, 180, icon_svg(180, bg=NIGHT, fill=0.62), NIGHT))
    for n in (70, 144, 150, 310):
        out.append((PUBLIC / f'ms-icon-{n}x{n}.png', n, n, icon_svg(n, fill=0.7), None))
    # PWA maskable: fundo noite sangrando ate a borda; simbolo dentro da zona segura (raio 40%)
    for n in (192, 512):
        out.append((PUBLIC / f'maskable-icon-{n}x{n}.png', n, n, icon_svg(n, bg=NIGHT, fill=0.56), NIGHT))
    # logo horizontal em PNG para e-mail (clientes de e-mail nao renderizam SVG)
    out.append((ASSETS / 'logo-email.png', 704, 300, lockup_svg(BLUE, NIGHT), WHITE))
    out.append((ASSETS / 'logo-email-dark.png', 704, 300, lockup_svg(BLUE, WHITE), NIGHT))
    return out


def _shot(browser, svg, w, h, bg):
    page = browser.new_page(viewport={'width': w, 'height': h})
    page.set_content(
        f'<html><body style="margin:0;background:{bg or "transparent"}">'
        f'<style>svg{{display:block;width:{w}px;height:{h}px}}</style>{svg}</body></html>'
    )
    data = page.screenshot(omit_background=bg is None, clip={'x': 0, 'y': 0, 'width': w, 'height': h})
    page.close()
    return data


def write_pngs_and_ico():
    from playwright.sync_api import sync_playwright

    with sync_playwright() as p:
        browser = p.chromium.launch(channel='chrome')
        for path, w, h, svg, bg in jobs():
            Path(path).write_bytes(_shot(browser, svg, w, h, bg))
        sizes = (16, 32, 48)
        frames = [_shot(browser, icon_svg(n, fill=1.0), n, n, None) for n in sizes]
        browser.close()
    header = struct.pack('<HHH', 0, 1, len(frames))
    offset = 6 + 16 * len(frames)
    entries, blobs = b'', b''
    for n, data in zip(sizes, frames):
        entries += struct.pack('<BBBBHHII', n, n, 0, 0, 1, 32, len(data), offset)
        blobs += data
        offset += len(data)
    (PUBLIC / 'favicon.ico').write_bytes(header + entries + blobs)


if __name__ == '__main__':
    write_svgs()
    if '--svg-only' not in sys.argv:
        write_pngs_and_ico()
    print('ativos LUAR gerados')
