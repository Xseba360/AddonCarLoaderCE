"""Writes ../docs/media/logo.svg: the name set in the app's two fonts, as outlines (an SVG on GitHub cannot
load a font). Run from manager/: python tool/make_logo.py
Reads simple TrueType glyphs only (no composites), which is all the capitals and digits need."""
import struct

ORANGE, WHITE, BLACK, GREY = '#F7A01B', '#FFFFFF', '#0A0A0A', '#8C8C8C'


class Font:
    def __init__(self, path):
        d = self.d = open(path, 'rb').read()
        n = struct.unpack('>H', d[4:6])[0]
        self.t = {d[12 + 16 * i:16 + 16 * i].decode(): struct.unpack('>II', d[20 + 16 * i:28 + 16 * i]) for i in range(n)}
        head = self.t['head'][0]
        self.upm = struct.unpack('>H', d[head + 18:head + 20])[0]
        self.long_loca = struct.unpack('>h', d[head + 50:head + 52])[0]
        self.n_hmetrics = struct.unpack('>H', d[self.t['hhea'][0] + 34:self.t['hhea'][0] + 36])[0]
        self.cmap = self._cmap()

    def _cmap(self):
        d, base = self.d, self.t['cmap'][0]
        for i in range(struct.unpack('>H', d[base + 2:base + 4])[0]):
            plat, enc, off = struct.unpack('>HHI', d[base + 4 + 8 * i:base + 12 + 8 * i])
            sub = base + off
            if plat == 3 and enc == 1 and struct.unpack('>H', d[sub:sub + 2])[0] == 4:
                seg = struct.unpack('>H', d[sub + 6:sub + 8])[0] // 2
                def arr(o, fmt='H'): return struct.unpack('>%d%s' % (seg, fmt), d[o:o + 2 * seg])
                ends, starts = arr(sub + 14), arr(sub + 16 + 2 * seg)
                deltas, ro = arr(sub + 16 + 4 * seg, 'h'), sub + 16 + 6 * seg
                offsets, out = arr(ro), {}
                for s in range(seg):
                    for c in range(starts[s], ends[s] + 1):
                        if c == 0xFFFF:
                            continue
                        if offsets[s] == 0:
                            g = (c + deltas[s]) & 0xFFFF
                        else:
                            at = ro + 2 * s + offsets[s] + 2 * (c - starts[s])
                            g = struct.unpack('>H', d[at:at + 2])[0]
                            g = (g + deltas[s]) & 0xFFFF if g else 0
                        out[c] = g
                return out
        raise ValueError('no Unicode cmap')

    def advance(self, g):
        at = self.t['hmtx'][0] + 4 * min(g, self.n_hmetrics - 1)
        return struct.unpack('>H', self.d[at:at + 2])[0]

    def contours(self, g):
        d, loca, glyf = self.d, self.t['loca'][0], self.t['glyf'][0]
        if self.long_loca:
            a, b = struct.unpack('>II', d[loca + 4 * g:loca + 4 * g + 8])
        else:
            a, b = (2 * v for v in struct.unpack('>HH', d[loca + 2 * g:loca + 2 * g + 4]))
        if a == b:
            return []
        p = glyf + a
        n = struct.unpack('>h', d[p:p + 2])[0]
        assert n >= 0, 'composite glyph'
        ends = struct.unpack('>%dH' % n, d[p + 10:p + 10 + 2 * n])
        p += 10 + 2 * n
        p += 2 + struct.unpack('>H', d[p:p + 2])[0]  # instructions
        count, flags = ends[-1] + 1, []
        while len(flags) < count:
            f = d[p]; p += 1
            flags.append(f)
            if f & 8:
                flags += [f] * d[p]; p += 1
        def coords(short, same):
            nonlocal p
            v, out = 0, []
            for f in flags:
                if f & short:
                    v += d[p] if f & same else -d[p]; p += 1
                elif not f & same:
                    v += struct.unpack('>h', d[p:p + 2])[0]; p += 2
                out.append(v)
            return out
        xs, ys = coords(2, 16), coords(4, 32)
        out, start = [], 0
        for e in ends:
            out.append([(xs[i], ys[i], flags[i] & 1) for i in range(start, e + 1)])
            start = e + 1
        return out


def text_path(font, text, x, baseline, size, tracking=0.0):
    """SVG path data for [text] with its left edge at x; returns (data, width)."""
    k, parts, pen = size / font.upm, [], x
    def pt(px, py): return '%.1f %.1f' % (pen + px * k, baseline - py * k)
    for ch in text:
        g = font.cmap[ord(ch)]
        for c in font.contours(g):
            # start on an on-curve point; between two off-curve points lies an implied on-curve one
            first = next((i for i, q in enumerate(c) if q[2]), None)
            if first is None:
                c = [((c[0][0] + c[-1][0]) / 2, (c[0][1] + c[-1][1]) / 2, 1)] + c
                first = 0
            c = c[first:] + c[:first]
            parts.append('M' + pt(c[0][0], c[0][1]))
            i, m = 1, len(c)
            while i <= m:
                q = c[i % m]
                if q[2]:
                    parts.append('L' + pt(q[0], q[1])); i += 1
                else:
                    nxt = c[(i + 1) % m]
                    end = (nxt[0], nxt[1]) if nxt[2] else ((q[0] + nxt[0]) / 2, (q[1] + nxt[1]) / 2)
                    parts.append('Q' + pt(q[0], q[1]) + ' ' + pt(*end))
                    i += 2 if nxt[2] else 1
            parts.append('Z')
        pen += font.advance(g) * k + tracking
    return ''.join(parts), pen - tracking - x


def main():
    bold, din = Font('fonts/Switzer-Extrabold.ttf'), Font('fonts/din1451alt.ttf')
    W, H, left = 1200, 250, 60
    # one line, sized to span the width between the margins
    name, ce_text, gap = 'Add-on Car Loader', 'CE', 0.26
    _, w1 = text_path(bold, name, 0, 0, 100, -2)
    _, w2 = text_path(bold, ce_text, 0, 0, 100, -2)
    size = 100 * (W - 2 * left) / (w1 + w2 + gap * 100)
    k = size / 100
    main_path, main_w = text_path(bold, name, left, 138, size, -2 * k)
    ce, _ = text_path(bold, ce_text, left + main_w + gap * size, 138, size, -2 * k)
    tag, _ = text_path(din, 'ADD-ON VEHICLES FOR GTA IV COMPLETE EDITION', left, 206, 26, 3.2)
    svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}" role="img" aria-label="Add-on Car Loader CE">
<rect width="{W}" height="{H}" fill="{BLACK}"/>
<path d="{main_path}" fill="{WHITE}"/>
<path d="{ce}" fill="{ORANGE}"/>
<rect x="{left}" y="166" width="{W - 2 * left}" height="3" fill="{ORANGE}"/>
<path d="{tag}" fill="{GREY}"/>
</svg>
'''
    open('../docs/media/logo.svg', 'w', encoding='utf-8', newline='\n').write(svg)


if __name__ == '__main__':
    main()
