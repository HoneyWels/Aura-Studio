#!/usr/bin/env python3
import sys
import colorsys
import os
import tempfile

def clamp(v, lo=0.0, hi=1.0): return max(lo, min(v, hi))

def hexcolor(r, g, b):
    return f"#{int(r):02x}{int(g):02x}{int(b):02x}"

def luminance(r, g, b):
    return 0.2126 * r + 0.7152 * g + 0.0722 * b

def main():
    data = sys.stdin.buffer.read()
    if not data: return

    # Write raw rgb to a temp file, use ImageMagick to convert to jpg, then run ColorThief
    # Because ColorThief needs an image file, not raw RGB pixels.
    # Wait, in aura_accent_sample, it pipes raw pixels from ffmpeg.
    # But we can just calculate it directly here since we have the RGB pixels!
    
    cand = []
    tot_w = 0.0
    tot_s = 0.0
    
    # We can sample every Nth pixel to save time
    stride = 3 * 16
    for off in range(0, len(data) - 2, stride):
        r, g, b = data[off], data[off+1], data[off+2]
        h, l, s = colorsys.rgb_to_hls(r/255.0, g/255.0, b/255.0)
        tot_s += s
        tot_w += 1.0
        
        if l < 0.15 or l > 0.92: continue
        score = (s * 0.65) + (l * 1.35)
        cand.append((score, r, g, b))
        
    avg_s = (tot_s / tot_w) if tot_w > 0 else 0
    
    if avg_s < 0.05 or not cand:
        # B&W
        ar = ag = ab = tot = 0.0
        for off in range(0, len(data) - 2, stride):
            r, g, b = data[off], data[off+1], data[off+2]
            w = max(r, g, b) / 255.0
            tot += w
            ar += r * w
            ag += g * w
            ab += b * w
        if tot > 0:
            r, g, b = ar/tot, ag/tot, ab/tot
            h, l, s = colorsys.rgb_to_hls(r/255.0, g/255.0, b/255.0)
            # Force grey
            r, g, b = [c*255.0 for c in colorsys.hls_to_rgb(h, l, 0.0)]
        else:
            r, g, b = 128, 128, 128
    else:
        best = max(cand, key=lambda x: x[0])
        r, g, b = best[1], best[2], best[3]
        
    accent = hexcolor(r, g, b)
    
    h, s, v = colorsys.rgb_to_hsv(r/255.0, g/255.0, b/255.0)
    dim = hexcolor(*[c*255.0 for c in colorsys.hsv_to_rgb(h, s * 0.85, clamp(v * 0.42, 0.06, 1.0))])
    bright = hexcolor(*[c*255.0 for c in colorsys.hsv_to_rgb(h, clamp(s * 1.05, 0, 1), clamp(v * 1.25 + 0.08, 0, 1))])
    on = "#0E1113" if luminance(r, g, b) > 140 else "#F2F3F7"
    
    print(f"accent={accent} dim={dim} bright={bright} on={on} text={on}")

if __name__ == "__main__":
    main()
