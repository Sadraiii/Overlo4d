"""Anatomy figure generator for Tally.

The body is drawn for the viewer's left half of a 200x400 figure and mirrored. Every shape is a
list of points; the generator runs a smooth closed curve through them, so a muscle is edited by
moving its points rather than hand-writing Bezier handles. A point written "!x,y" is a sharp corner.

    python3 scripts/anatomy.py swift > Sources/Tally/Exercises/AnatomyShapes.swift
    python3 scripts/anatomy.py js > scripts/mockups/anatomy.js

Each side has an outline (the silhouette, which clips everything else), muscle regions and a few
open contour lines (collarbones, kneecaps, spine) that are only stroked. Muscles may overshoot the
outline; the clip trims them to the body. Output paths use only absolute M, L, C and Z so the Swift
parser stays tiny.
"""
import json
import sys

W = 200
DETAIL = True

# The silhouette's left half, from the top of the head down the outside of the body and back up the
# inside of the leg to the crotch.
OUTLINE = (
    "100,5 91,7.5 84.5,15 82.6,24 80.6,27.5 80.8,33.5 83.4,37.5 86.5,44.5 90.5,50 91,57 89,63.5 81,68.5 71,71.5 60,74 "
    "49,78 41,86 36.5,97 35,110 34,124 32,138 30,151 27,165 24.5,182 24,198 24.5,210 22,220 "
    "20.5,231 22,241 25,247.5 !28.5,249 32,246 36,240.5 39.5,231 41,220 41,211 44.5,198 49,182 "
    "53,167 56,153 58,140 59.5,128 !61.5,119 62.5,132 65,146 67.5,160 68.5,172 66.5,186 62.5,200 "
    "59.5,216 56.5,234 55.5,252 57,270 60.5,286 63.5,298 64,308 60,320 57.5,334 59,349 64,363 69,374 69.5,381 "
    "66,388 63.5,393.5 !66,397.5 !88,397.5 89.5,392 87,384 86,376 89,362 92.5,346 94,330 91.5,316 "
    "90.5,304 92,292 94.5,276 96.5,258 98.5,242 !100,231"
)

# (muscle or None, points, mirrored?[, DETAIL])
# Regions are drawn in order. A DETAIL region sits on its own muscle and only adds the line between
# two heads (upper and lower chest, the serratus on the obliques); it isn't tapped or measured.
FRONT = [
    (None, "!91.8,52.5 90.8,60 93,68 !96,75 !98.7,76.5 98.2,69 96,60", True),
    ("traps", "91.5,56 88.5,62.5 80,67.5 66,71.5 !60,74.5 72,74.6 84,73.8 !92.5,72 93,64", True),
    ("sideDelts", "61,73 49,76 40,84 34,97 33,112 !38.5,121 41.5,108 46,96 52.5,86.5 !61.5,78", True),
    ("frontDelts", "64,79 55.5,87 49,97 44.5,108 !42,120.5 46.5,121.5 52.5,117 56,107 61,97 67,88 !70.5,79.5", True),
    ("chest", "72.5,79.8 86,78.2 !98.6,80.5 98.7,100 !98.4,121 92,126.8 81,128.2 70,125 62.5,118 58.5,109 61,99 66,89", True),
    ("chest", "72.5,79.8 86,78.2 !98.6,80.5 !98.7,94.5 86,94.5 73,97.5 !62,100.5 66,89", True, DETAIL),
    ("biceps", "!42,122.5 38.5,134 37.5,146 39.5,155.5 44,160.5 49.5,158.5 53.5,149 56,137 57,126 !56.5,118.5 50.5,122.5", True),
    ("triceps", "!39,123 35.5,133 34,144 33.5,153 !35.5,158 36,146 37,134", True),
    ("triceps", "!58.5,121 60.5,131 59.5,143 57,153 !54.5,157.5 57.5,146 58.5,133", True),
    ("forearms", "!35.5,160.5 30,170 26,184 24.5,198 !25.5,209 !32,210 36,198 39.5,184 41.5,172 !41.5,162.5", True),
    ("forearms", "!44,163.5 44.5,174 42,188 38,200 !34.5,210 !40.5,211 45,198 49.5,183 53.5,168 !55,158 50,162.5", True),
    ("abs", "R 88.2,131.2 98.7,129.8 98.7,144.6 87,145.8", True),
    ("abs", "R 86.8,148.6 98.7,147.4 98.7,162.2 86.2,163.2", True),
    ("abs", "R 86,166 98.7,165 98.7,179.8 86.4,180.6", True),
    ("abs", "!86.6,183.4 !98.7,182.6 !98.7,215 96.5,220.5 92,214 88.5,203 87,193", True),
    ("obliques", "!61,121 70,127.5 !84.5,131.5 83.6,150 83.2,170 84,188 !87,206 80.5,202 73.5,194 69,184 70,172 68.5,160 66,146 63,133", True),
    ("obliques", "62,125 69.5,129.5 75.5,133 !77,136 71,136.5 !63.5,134", True, DETAIL),
    ("obliques", "64.5,138.5 71.5,140.5 76.5,144 !77.5,147.5 72,148 !66.5,146.5", True, DETAIL),
    ("obliques", "67,151 73,153 77,156.5 !77.5,160 72.5,160.5 !68.2,159", True, DETAIL),
    ("quads", "!65,208 59.5,222 56,240 55,258 57,274 61.5,288 !66.5,297.5 71,286 70.5,270 69,252 69,234 70.5,220", True),
    ("quads", "!72.5,212 70.5,226 69.5,244 70.5,262 73.5,278 77.5,290 !80.5,295 83.5,284 86,268 87,250 85,234 81,222", True),
    ("quads", "!89.5,266.5 87.5,277 85,287 82.5,295 85,302 90.5,301 93.5,293 95,281 93.5,271", True),
    ("adductors", "!82,217 90,225 !98.8,234 98.6,246 97,256 !94.5,264.5 91.5,254 88.5,242 85.5,228", True),
    (None, "77,296.5 73,299.5 72.6,305 77,309.5 81.4,305 81,299.5", True),
    ("calves", "!65,311 59.5,321 57,334 58.5,348 63,360 !68.5,371 72,358 73.5,342 73,326 !71,312", True),
    ("calves", "!88.5,311 93,321 94.5,334 93,347 89,357 !84.5,366 82.5,352 82.5,336 83.5,322 !85.5,311", True),
]
FRONT_LINES = [
    ("!70,76.2 82,75.8 92,77.4 !98,81", True),          # collarbone
    ("!26.5,236 !28,246.5", True),                      # fingers
    ("!30.5,238 !31.5,247.5", True),
    ("!34.5,236.5 !34.8,244", True),
    ("!77.5,314 78,340 !77,372", True),                 # shin
    ("!69.5,186 76,200 !90,217", True),                 # hip crease
]
BACK = [
    ("traps", "!100,49.5 95,57 88.5,63.5 78,69 !62,74 74,79.5 84,89 90.5,102 95.5,120 !100,141 "
              "104.5,120 109.5,102 116,89 126,79.5 !138,74 122,69 111.5,63.5 105,57", False),
    ("traps", "!100,49.5 95,57 88.5,63.5 78,69 !62,74 74,79.5 !84,89 !100,84 !116,89 126,79.5 !138,74 122,69 111.5,63.5 105,57", False, DETAIL),
    ("traps", "!100,141 95.5,120 !90.5,102 !100,106 !109.5,102 104.5,120", False, DETAIL),
    ("sideDelts", "61,73 49,76 40,84 34,97 33,112 !38.5,121 41.5,108 46,96 52.5,86.5 !61.5,78", True),
    ("rearDelts", "!63.5,78 55,86.5 48.5,97 44,108 !42,120.5 47,121.5 53.5,116 58.5,107 64.5,98.5 !71,91 68.5,83", True),
    ("upperBack", "!72.5,83 66.5,94 62,104 61.5,113 67,119.5 76,120.5 84.5,115.5 !90,107.5 86.5,97.5 81,89.5", True),
    ("lats", "!60.5,116.5 61,132 63.5,148 68,164 75.5,178 84.5,189 !92,195 93.8,176 95.2,156 !95.8,128 92,113 86,119.5 76,124 67.5,122.5", True),
    ("lowerBack", "!96.2,146 !98.8,143.5 !98.8,207 !91.5,206.5 90.2,192 91.6,176 93.8,160", True),
    ("obliques", "!67,168 71,180 77.5,190 !88,199.5 !88.5,204.5 78,201 !66.5,197 66,188 67.5,178", True),
    ("triceps", "!41,123 36,133 34,145 34.5,155 !38.5,160 43.5,156 46,145 47,133 !46.5,122.5", True),
    ("triceps", "!49.5,121.5 50,134 48.5,147 !47.5,158.5 52.5,159.5 56.5,150 59,137 60,126 !57.5,117.5 53.5,120.5", True),
    ("forearms", "!35.5,162.5 30,172 26,186 24.5,198 !25.5,209 !32,210 36,198 39.5,184 41.5,172 !41.5,163.5", True),
    ("forearms", "!44.5,163.5 44.5,174 42,188 38,200 !34.5,210 !40.5,211 45,198 49.5,183 53.5,168 !55,160 50,163", True),
    ("glutes", "!66,200 62,209 !59.5,221.5 68.5,216 78,212.5 !89,211 !89.5,207.5 79,204", True),
    ("glutes", "!59.5,224.5 57.5,234 59,244 67,252 78,256.5 90,255.5 !98.8,250 !98.8,222 95.5,215 89,213 78,214.5 68.5,218", True),
    ("hamstrings", "!59.5,254 56.5,268 57.5,282 61,294 !66,303 74,300 77.5,288 78.5,274 !78,260.5 68.5,258.5", True),
    ("hamstrings", "!79.5,261.5 80,276 78.5,290 !77,301 83,305.5 88.5,298 91.5,284 !92.5,260 86.5,262", True),
    ("adductors", "!95.5,258 98.6,254 98.4,266 96.5,280 !93.5,292 94.5,276", True),
    ("calves", "!65.5,314 59.5,324 57,337 59,349 64.5,357 71.5,359.5 !76,354 77,340 76.5,326 !73.5,313.5", True),
    ("calves", "!79.5,314 79,328 79,342 !80,354.5 85,358.5 91,352 94,340 93.5,326 !89.5,313.5", True),
    ("calves", "!66.5,361.5 72,363.5 78,360 84.5,362.5 !88.5,360.5 86.5,370 !85,378 !71.5,378 69,370", True),
]
BACK_LINES = [
    ("!100,143 !100,206", False),                       # spine
    ("!26.5,236 !28,246.5", True),                      # fingers
    ("!30.5,238 !31.5,247.5", True),
    ("!34.5,236.5 !34.8,244", True),
    ("!71.5,379 !72.5,390", True),                      # heel cord
    ("!85,379 !84.5,390", True),
    ("!68,302.5 77,307.5 !87,304", True),               # back of the knee
    ("!100,212 !100,254", False),                       # between the glutes
]


def points(text):
    """[(x, y, corner)] from "x,y !x,y ..."."""
    out = []
    for token in text.split():
        corner = token.startswith("!")
        x, y = token.lstrip("!").split(",")
        out.append((float(x), float(y), corner))
    return out


def fmt(value):
    return f"{round(value, 1):g}"


def spline(pts, closed=True):
    """A Catmull-Rom curve through the points as cubic Beziers; corners get no tangent."""
    n = len(pts)

    def tangent(i):
        if pts[i][2]:
            return (0.0, 0.0)
        if closed:
            a, b = pts[(i - 1) % n], pts[(i + 1) % n]
        else:
            a, b = pts[max(i - 1, 0)], pts[min(i + 1, n - 1)]
        return ((b[0] - a[0]) / 6, (b[1] - a[1]) / 6)

    d = [f"M{fmt(pts[0][0])},{fmt(pts[0][1])}"]
    for i in range(n if closed else n - 1):
        p, q = pts[i], pts[(i + 1) % n]
        tp, tq = tangent(i), tangent((i + 1) % n)
        d.append(f"C{fmt(p[0] + tp[0])},{fmt(p[1] + tp[1])} {fmt(q[0] - tq[0])},{fmt(q[1] - tq[1])} {fmt(q[0])},{fmt(q[1])}")
    if closed:
        d.append("Z")
    return " ".join(d)


def rounded(pts, radius=2.6):
    """A polygon with rounded corners, for the blocks of the abs."""
    n = len(pts)

    def toward(a, b, distance):
        dx, dy = b[0] - a[0], b[1] - a[1]
        length = (dx * dx + dy * dy) ** 0.5
        t = min(distance / length, 0.5)
        return (a[0] + dx * t, a[1] + dy * t)

    d = []
    for i in range(n):
        corner, before, after = pts[i], pts[i - 1], pts[(i + 1) % n]
        start, end = toward(corner, before, radius), toward(corner, after, radius)
        d.append(f"{'M' if i == 0 else 'L'}{fmt(start[0])},{fmt(start[1])}")
        c1 = (start[0] + (corner[0] - start[0]) * 0.6, start[1] + (corner[1] - start[1]) * 0.6)
        c2 = (end[0] + (corner[0] - end[0]) * 0.6, end[1] + (corner[1] - end[1]) * 0.6)
        d.append(f"C{fmt(c1[0])},{fmt(c1[1])} {fmt(c2[0])},{fmt(c2[1])} {fmt(end[0])},{fmt(end[1])}")
    d.append("Z")
    return " ".join(d)


def flip(pts):
    return [(W - x, y, corner) for x, y, corner in reversed(pts)]


def shape(text, mirrored=False, closed=True):
    is_rounded = text.startswith("R ")
    pts = points(text[2:] if is_rounded else text)
    if mirrored:
        pts = flip(pts)
    return rounded(pts) if is_rounded else spline(pts, closed)


def outline():
    half = points(OUTLINE)
    # The centre-line points belong to both halves, so the mirrored half skips them.
    return spline(half + [p for p in flip(half) if p[0] != W / 2])


def expand(shapes):
    out = []
    for muscle, text, mirrored, *rest in shapes:
        detail = bool(rest and rest[0])
        out.append((muscle, shape(text), detail))
        if mirrored:
            out.append((muscle, shape(text, mirrored=True), detail))
    return out


def lines(shapes):
    out = []
    for text, mirrored in shapes:
        out.append(shape(text, closed=False))
        if mirrored:
            out.append(shape(text, mirrored=True, closed=False))
    return out


def js():
    """The same shapes for the README mockups: [muscle, path, detail]."""
    data = {
        "outline": outline(),
        "front": [[m, p, d] for m, p, d in expand(FRONT)],
        "back": [[m, p, d] for m, p, d in expand(BACK)],
        "frontLines": lines(FRONT_LINES),
        "backLines": lines(BACK_LINES),
    }
    return ("// Generated by scripts/anatomy.py from the same shapes as AnatomyShapes.swift (200 x 400).\n"
            f"const ANATOMY = {json.dumps(data)};\n")


def swift():
    def regions(shapes):
        rows = []
        for muscle, path, detail in expand(shapes):
            name = f".{muscle}" if muscle else "nil"
            rows.append(f'        (muscle: {name}, path: "{path}", detail: {"true" if detail else "false"}),')
        return "\n".join(rows)

    def strings(paths):
        return "\n".join(f'        "{path}",' for path in paths)

    return f'''// Generated by scripts/anatomy.py. Edit the generator, not this file.

/// The body outline, muscle regions and contour lines for the front and back figures, in a
/// 200 × 400 coordinate space.
enum AnatomyShapes {{
    static let width = 200.0
    static let height = 400.0

    /// The silhouette, the same from the front and the back. Muscles are clipped to it.
    static let outline = "{outline()}"

    static let front: [(muscle: Muscle?, path: String, detail: Bool)] = [
{regions(FRONT)}
    ]

    static let back: [(muscle: Muscle?, path: String, detail: Bool)] = [
{regions(BACK)}
    ]

    /// Open lines drawn over the skin: collarbones, kneecaps, hip creases.
    static let frontLines = [
{strings(lines(FRONT_LINES))}
    ]

    /// The spine and the backs of the knees.
    static let backLines = [
{strings(lines(BACK_LINES))}
    ]
}}
'''


if __name__ == "__main__":
    sys.stdout.write(js() if sys.argv[1] == "js" else swift())
