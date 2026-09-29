#!/usr/bin/env python3
"""
aura-accent: extrae el color de acento dominante de un frame de video/imagen.

Lee pixeles RGB24 crudos por stdin (salida de ffmpeg) y escribe en stdout
un bloque de variables de shell lista para eval:

    accent=#RRGGBB   color principal (acento)
    dim=#RRGGBB      variante oscura (bordes inactivos, fondos)
    bright=#RRGGBB   variante clara (texto sobre oscuro, hover)
    on=#RRGGBB       color de texto legible sobre 'accent'
    text=#RRGGBB     color de texto legible sobre 'dim'

Elige el cluster de pixeles mas saturado y luminoso (no el promedio, que
sale sucio), y protege el contraste: el acento siempre queda dentro de una
banda de luminosidad donde se lee bien sobre fondos oscuros de rice.
"""
import colorsys
import sys


def clamp(v, lo=0.0, hi=1.0):
    return lo if v < lo else hi if v > hi else v


def rgb_to_hsv(r, g, b):
    return colorsys.rgb_to_hsv(r / 255.0, g / 255.0, b / 255.0)


def hsv_to_rgb(h, s, v):
    r, g, b = colorsys.hsv_to_rgb(h, s, v)
    return r * 255.0, g * 255.0, b * 255.0


def hexcolor(r, g, b):
    return "#%02X%02X%02X" % (int(round(clamp(r, 0, 255))), int(round(clamp(g, 0, 255))), int(round(clamp(b, 0, 255))))


def parse_hex(text):
    text = text.strip().lstrip("#")
    if len(text) == 3:
        text = "".join(c * 2 for c in text)
    if len(text) != 6:
        raise ValueError(text)
    return (int(text[0:2], 16), int(text[2:4], 16), int(text[4:6], 16))


def luminance(r, g, b):
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def main():
    argv = sys.argv[1:]
    prev, smooth, min_sat, min_val, target_lum = None, 0.0, 0.45, 0.42, None
    i = 0
    while i < len(argv):
        opt = argv[i]
        if opt == "--prev" and i + 1 < len(argv):
            prev = argv[i + 1]
            i += 2
        elif opt == "--smooth" and i + 1 < len(argv):
            smooth = clamp(float(argv[i + 1]) / 100.0)
            i += 2
        elif opt == "--min-sat" and i + 1 < len(argv):
            min_sat = clamp(float(argv[i + 1]))
            i += 2
        elif opt == "--min-val" and i + 1 < len(argv):
            min_val = clamp(float(argv[i + 1]))
            i += 2
        elif opt == "--target-lum" and i + 1 < len(argv):
            target_lum = float(argv[i + 1])
            i += 2
        else:
            i += 1

    data = sys.stdin.buffer.read()
    if len(data) < 9:
        print("accent=#7C6CFF dim=#232640 bright=#A79BFF on=#0E1113 text=#D7DAF0")
        return

    # 1) Recolectar candidatos con peso por saturacion x luminosidad
    cand = []
    for off in range(0, len(data) - 2, 3):
        r, g, b = data[off], data[off + 1], data[off + 2]
        h, s, v = rgb_to_hsv(r, g, b)
        if v < 0.08 or s < 0.06:
            continue
        weight = (s ** 1.4) * (v ** 0.7) * (0.5 + 0.5 * v)
        cand.append((weight, h, s, v, r, g, b))

    if not cand:
        # Todo el frame es casi gris: usa el promedio ponderado por luminosidad
        tot = 0.0
        ar = ag = ab = 0.0
        for off in range(0, len(data) - 2, 3):
            w = max(data[off], data[off + 1], data[off + 2]) / 255.0
            tot += w
            ar += data[off] * w
            ag += data[off + 1] * w
            ab += data[off + 2] * w
        if tot == 0:
            print("accent=#7C6CFF dim=#232640 bright=#A79BFF on=#0E1113 text=#D7DAF0")
            return
        h, s, v = rgb_to_hsv(ar / tot, ag / tot, ab / tot)
    else:
        best = max(c[0] for c in cand)
        # 2) Clusterizar: quedarnos con el nucleo de pixeles maspeso
        thr = best * 0.55
        top = [c for c in cand if c[0] >= thr]
        if len(top) < 3:  # cluster demasiado pequeno -> ampliar
            top = sorted(cand, key=lambda c: -c[0])[:max(3, len(cand) // 12)]
        # 3) Promedio ponderado en espacio HSV (promedia el tono, no el lodo)
        ws = sum(c[0] for c in top)
        # el tono se promedia en coordenadas circulares
        sx = sum(c[0] * colorsys.hsv_to_rgb(c[1], 1.0, 1.0)[0] for c in top)
        sy = sum(c[0] * colorsys.hsv_to_rgb(c[1], 1.0, 1.0)[1] for c in top)
        h = (colorsys.rgb_to_hsv(sx / ws, sy / ws, 1.0)[0]) % 1.0
        s = sum(c[0] * c[2] for c in top) / ws
        v = sum(c[0] * c[3] for c in top) / ws

    # 4) Proteccion de contraste: banda de luminosidad segura
    if s < min_sat:
        s = min_sat
    if v < min_val:
        v = min_val
    if v > 0.95:
        v = 0.95
    if target_lum is not None:
        l = 0.2126 * colorsys.hsv_to_rgb(h, s, v)[0] + \
            0.7152 * colorsys.hsv_to_rgb(h, s, v)[1] + \
            0.0722 * colorsys.hsv_to_rgb(h, s, v)[2]
        v = clamp(v * (target_lum / max(l, 1e-3)), min_val, 0.97)

    r, g, b = hsv_to_rgb(h, s, v)

    # 5) Suavizado exponencial con el acento anterior (evita parpadeos)
    if prev:
        try:
            pr, pg, pb = parse_hex(prev)
            ph, ps, pv = rgb_to_hsv(pr, pg, pb)
            # el tono se mueve poco: promedia en RGB para no rotar el color
            r = pr + (r - pr) * smooth
            g = pg + (g - pg) * smooth
            b = pb + (b - pb) * smooth
        except ValueError:
            pass

    r, g, b = clamp(r, 0, 255), clamp(g, 0, 255), clamp(b, 0, 255)
    accent = hexcolor(r, g, b)

    # 6) Variantes derivadas
    h, s, v = rgb_to_hsv(r, g, b)
    dim = hexcolor(*hsv_to_rgb(h, s * 0.85, clamp(v * 0.42, 0.06, 1.0)))
    bright = hexcolor(*hsv_to_rgb(h, clamp(s * 1.05, 0, 1), clamp(v * 1.25 + 0.08, 0, 1)))
    on = "#0E1113" if luminance(r, g, b) > 140 else "#F2F3F7"
    dr, dg, db = parse_hex(dim)
    text = "#E6E9F2" if luminance(dr, dg, db) < 150 else "#0E1113"

    print("accent=%s dim=%s bright=%s on=%s text=%s" % (accent, dim, bright, on, text))


if __name__ == "__main__":
    main()
