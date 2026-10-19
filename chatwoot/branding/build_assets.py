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
# Geometria extraida (ajuste por minimos quadrados) da arte aprovada pelo dono
# (specs/anexos/10/luar-referencia-aprovada.png): disco com UM recorte em crescente, de pontas
# no topo-esquerda e na direita, dois arcos do mesmo lado (externo mais curvo, interno mais plano).
P1 = (40.60, 10.99)    # ponta superior do recorte
P2 = (84.85, 67.99)    # ponta direita do recorte
SAG_OUT = 23.28        # flecha do arco externo (unidades do disco = 100)
SAG_IN = 15.00         # flecha do arco interno


def _f(v):
    return f'{v:.2f}'.rstrip('0').rstrip('.')


def _radius(sag):
    half = math.dist(P1, P2) / 2
    return (half**2 + sag**2) / (2 * sag)


def moon_path():
    r_out, r_in = _radius(SAG_OUT), _radius(SAG_IN)
    return (
        'M50 0A50 50 0 1 1 50 100A50 50 0 1 1 50 0Z'
        f'M{_f(P1[0])} {_f(P1[1])}A{_f(r_out)} {_f(r_out)} 0 0 1 {_f(P2[0])} {_f(P2[1])}'
        f'A{_f(r_in)} {_f(r_in)} 0 0 0 {_f(P1[0])} {_f(P1[1])}Z'
    )


MOON = moon_path()

# Wordmark LUAR: fios finos e espacados, medidos da arte aprovada (disco = 100 de diametro; a
# altura das letras e ~45% do disco e o conjunto fica ~6 abaixo do centro do disco).
STROKE = 5.5
TOP, BOT = 33.9, 78.6
_t, _b = TOP + STROKE / 2, BOT - STROKE / 2
_ax, _ay, _bx = 246.9, 41.5, 287.1   # perna esquerda, vertice e perna direita do A


def _leg_x(y):
    return _ax + (BOT - y) / (BOT - _ay) * (267 - _ax)


WORD_FILL = ['M132.1 33.9H137.6V73.1H160.7V78.6H132.1Z']          # L
WORD_STROKE = [
    f'M186.75 {TOP}V59.9A15.95 15.95 0 0 0 218.65 59.9V{TOP}',     # U
    f'M{_ax} {BOT}L267 {_ay}L{_bx} {BOT}',                          # A (pernas)
    f'M{_f(_leg_x(63))} 63H{_f(534 - _leg_x(63))}',                 # A (travessa)
    f'M317.05 {TOP}V{BOT}',                                         # R (haste)
    f'M317.05 {_t}H334A11.1 11.1 0 0 1 334 58.85H317.05',          # R (barriga)
    'M331 58.85L347.8 78.6',                                        # R (perna)
]


def word_svg(color):
    fill = ''.join(f'<path d="{d}"/>' for d in WORD_FILL)
    stroke = ''.join(f'<path d="{d}"/>' for d in WORD_STROKE)
    return (f'<g fill="{color}">{fill}</g><g fill="none" stroke="{color}" stroke-width="{STROKE}" '
            f'stroke-linejoin="miter" stroke-miterlimit="6">{stroke}</g>')


def symbol_svg(color=BLUE, size=100):
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 100 100" '
        f'role="img" aria-label="Luar"><title>LUAR</title>'
        f'<path fill="{color}" fill-rule="evenodd" d="{MOON}"/></svg>\n'
    )


def lockup_svg(moon_color, word_color):
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" width="400" height="150" viewBox="0 0 400 150" '
        'role="img" aria-label="Luar"><title>LUAR</title>'
        f'<g transform="translate(25 25)"><path fill="{moon_color}" fill-rule="evenodd" d="{MOON}"/>'
        f'{word_svg(word_color)}</g></svg>' + chr(10)
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
    out.append((ASSETS / 'logo-email.png', 704, 264, lockup_svg(BLUE, NIGHT), WHITE))
    out.append((ASSETS / 'logo-email-dark.png', 704, 264, lockup_svg(BLUE, WHITE), NIGHT))
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
