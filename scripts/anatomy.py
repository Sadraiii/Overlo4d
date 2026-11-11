"""Anatomy figure generator for Tally.

Muscle regions are drawn for the viewer's left half of a 200x400 figure and mirrored. The same data
produces an SVG preview (for review) and the Swift source with the path strings:

    python3 scripts/anatomy.py swift > Sources/Tally/Exercises/AnatomyShapes.swift
    python3 scripts/anatomy.py js > scripts/mockups/anatomy.js
    python3 scripts/anatomy.py svg chest,triceps frontDelts > preview.svg

Paths use only absolute M, L, C and Z so the Swift parser stays tiny.
"""
import json
import re
import sys

W = 200

# (muscle or None for body parts, path, mirrored?[, DETAIL])
# Regions are drawn in order, so a later region can sit on top of an earlier one. Overlaying a
# muscle head on its own muscle (the rectus femoris on the quads, the gastrocnemius heads on the
# calves) draws the line between the heads without changing what is tapped or filled. Those
# overlays are marked DETAIL and drawn with a finer line than the gaps between muscles.
DETAIL = True

FRONT = [
    (None, "M100,6 C112,6 119,16 119,29 C119,42 111,53 100,53 C89,53 81,42 81,29 C81,16 88,6 100,6 Z", False),
    (None, "M90,44 C92,54 91,62 86,72 L82,84 L118,84 L114,72 C109,62 108,54 110,44 Z", False),
    ("traps", "M91,58 C87,64 78,69 64,73 C70,75 78,75 86,73 C89,71 91,69 92,66 Z", True),
    ("sideDelts", "M62,73 C50,74 42,80 38,92 C36,99 36,106 38,112 C41,104 45,96 51,90 C55,85 59,80 64,77 Z", True),
    ("frontDelts", "M64,77 C57,82 50,90 45,99 C42,105 40,110 40,114 C45,116 51,114 54,110 C56,100 60,92 67,86 C69,83 70,80 70,78 C68,77 66,77 64,77 Z", True),
    ("chest", "M71,78 C66,84 60,93 57,103 C56,110 58,117 63,122 C70,128 82,130 92,129 C97,128 99,125 99,120 L99,80 C92,76 80,76 71,78 Z", True),
    ("chest", "M71,78 C66,84 62,90 60,95 C72,93 86,92 99,93 L99,80 C92,76 80,76 71,78 Z", True, DETAIL),
    ("biceps", "M40,116 C36,126 35,138 36,148 C38,157 45,159 50,155 C53,142 55,130 55,116 C51,119 45,119 40,116 Z", True),
    ("triceps", "M56,112 C59,122 60,134 58,146 C56,150 53,152 51,153 C54,140 56,126 56,112 Z", True),
    ("forearms", "M36,152 C32,166 30,184 31,204 C33,210 39,210 42,206 C47,190 52,172 54,154 C49,158 41,158 36,152 Z", True),
    ("forearms", "M36,152 C33,164 32,176 33,190 C38,180 43,168 46,157 C42,157 39,155 36,152 Z", True, DETAIL),
    (None, "M32,208 C27,212 25,222 26,232 C28,240 36,241 39,234 C42,226 42,216 41,209 C38,211 35,211 32,208 Z", True),
    ("abs", "M89,131 C93,130 97,130 99,131 L99,148 L88,149 C87,143 87,136 89,131 Z", True),
    ("abs", "M88,152 L99,151 L99,167 L88,168 C87,163 87,157 88,152 Z", True),
    ("abs", "M88,171 L99,170 L99,186 L88,187 C87,182 87,176 88,171 Z", True),
    ("abs", "M88,190 L99,189 L99,214 C95,218 91,215 89,209 C88,203 88,196 88,190 Z", True),
    ("obliques", "M64,124 C70,128 78,131 85,132 C84,150 84,172 85,194 C85,200 84,204 82,206 C77,200 73,192 71,184 C68,170 66,156 66,142 C65,136 64,130 64,124 Z", True),
    ("obliques", "M64,124 C67,127 70,129 73,130 L72,136 C69,135 66,133 65,131 Z", True, DETAIL),
    ("obliques", "M65,136 C68,138 71,140 74,141 L73,147 C70,146 67,144 66,142 Z", True, DETAIL),
    (None, "M71,186 C74,196 79,204 86,210 C91,215 96,220 99,222 L99,232 L88,228 C80,222 73,212 68,200 Z", True),
    ("quads", "M66,206 C60,226 58,250 60,272 C61,288 66,298 74,302 C82,304 89,298 92,288 C95,272 94,254 90,238 C86,226 79,216 72,208 Z", True),
    ("quads", "M74,216 C81,230 86,248 86,266 C86,280 83,290 79,296 C74,288 70,276 70,262 C70,246 71,230 74,216 Z", True, DETAIL),
    ("quads", "M93,272 C95,282 93,292 88,298 C85,301 81,303 78,302 C81,294 87,282 93,272 Z", True, DETAIL),
    ("adductors", "M90,232 C95,236 99,242 99,252 C99,264 97,276 93,284 C94,268 94,250 90,232 Z", True),
    (None, "M66,300 C63,320 62,344 65,366 C67,378 71,386 74,390 L86,390 C88,382 91,372 92,360 C94,340 93,318 91,300 Z", True),
    (None, "M70,300 C73,307 83,309 90,303 C90,310 88,316 84,319 C77,320 71,314 70,300 Z", True),
    (None, "M76,318 L85,318 C86,340 86,362 84,386 L77,386 C76,362 76,340 76,318 Z", True),
    ("calves", "M65,318 C60,332 60,350 63,364 C66,374 72,376 76,370 L76,320 C72,317 68,317 65,318 Z", True),
    ("calves", "M87,318 C93,330 94,348 92,362 C90,370 87,372 85,368 L85,320 C86,318 86,317 87,318 Z", True),
    (None, "M72,384 C68,388 64,394 67,398 L87,398 C89,394 88,389 86,384 Z", True),
]
BACK = [
    (None, "M100,6 C112,6 119,16 119,29 C119,42 111,53 100,53 C89,53 81,42 81,29 C81,16 88,6 100,6 Z", False),
    (None, "M91,46 L109,46 L111,64 L89,64 Z", False),
    ("sideDelts", "M62,73 C50,74 42,80 38,92 C36,99 36,106 38,112 C41,104 45,96 51,90 C55,85 59,80 64,77 Z", True),
    ("rearDelts", "M64,77 C57,82 50,90 45,99 C42,105 40,110 40,114 C45,116 51,114 54,110 C56,102 61,94 68,88 C70,84 70,80 68,78 Z", True),
    ("upperBack", "M66,79 C61,88 59,98 60,110 C63,116 69,119 76,118 C82,116 87,111 91,104 C86,93 77,84 66,79 Z", True),
    ("triceps", "M40,116 C36,126 35,138 36,148 C38,157 45,159 50,155 C53,142 55,130 55,116 C51,119 45,119 40,116 Z", True),
    ("triceps", "M47,118 C46,128 44,138 42,146 C40,140 39,130 40,118 C42,119 45,119 47,118 Z", True, DETAIL),
    ("forearms", "M36,152 C32,166 30,184 31,204 C33,210 39,210 42,206 C47,190 52,172 54,154 C49,158 41,158 36,152 Z", True),
    (None, "M32,208 C27,212 25,222 26,232 C28,240 36,241 39,234 C42,226 42,216 41,209 C38,211 35,211 32,208 Z", True),
    ("lats", "M58,104 C56,126 60,150 67,168 C72,180 80,190 90,196 C91,182 92,166 93,150 C93,138 93,128 94,120 C88,122 82,121 76,119 C68,116 62,111 58,104 Z", True),
    ("lowerBack", "M95,138 C98,137 99,139 99,141 L99,212 C94,213 89,210 87,204 C86,192 87,178 89,166 C91,156 93,146 95,138 Z", True),
    ("traps", "M100,52 C96,60 86,66 66,72 C76,77 86,86 92,100 C95,112 98,128 100,146 C102,128 105,112 108,100 C114,86 124,77 134,72 C114,66 104,60 100,52 Z", False),
    ("glutes", "M68,202 C61,214 59,232 63,248 C68,262 84,266 99,258 L99,214 C92,208 80,202 68,202 Z", True),
    ("glutes", "M68,202 C64,208 62,214 61,220 C68,216 76,214 84,213 C80,207 74,203 68,202 Z", True, DETAIL),
    ("hamstrings", "M62,252 C59,270 60,288 65,300 C70,307 80,308 86,302 C90,288 93,272 93,260 C84,264 72,263 62,252 Z", True),
    ("hamstrings", "M78,262 C83,263 88,262 92,261 C92,276 90,290 86,302 C83,305 80,306 78,305 C77,290 77,276 78,262 Z", True, DETAIL),
    ("adductors", "M94,262 C97,272 98,284 96,294 C94,297 92,296 91,293 C92,284 93,272 94,262 Z", True),
    (None, "M65,300 C62,320 61,344 64,366 C67,378 71,386 73,390 L85,390 C88,382 91,372 92,360 C94,340 93,318 90,300 Z", True),
    (None, "M66,302 C70,309 82,311 88,305 C89,312 86,318 82,320 C75,321 68,316 66,302 Z", True),
    ("calves", "M66,318 C61,330 60,346 63,358 C66,366 71,370 76,366 L80,366 C85,370 90,366 91,356 C93,344 92,330 88,318 C82,316 72,316 66,318 Z", True),
    ("calves", "M66,320 C60,332 59,348 62,358 C66,356 72,352 76,346 L77,319 C73,319 69,319 66,320 Z", True, DETAIL),
    ("calves", "M78,319 L79,346 C82,352 86,356 90,358 C92,346 92,332 88,320 C85,319 81,319 78,319 Z", True, DETAIL),
    (None, "M72,366 C74,372 75,380 75,386 L83,386 C83,380 84,372 86,366 C82,369 76,369 72,366 Z", True),
    (None, "M70,386 C67,390 65,395 68,398 L86,398 C88,395 87,390 85,386 Z", True),
]


def mirror(path: str) -> str:
    """Mirror x around the figure's centre line."""
    def flip(match):
        x, y = float(match.group(1)), float(match.group(2))
        return f"{W - x:g},{y:g}"
    return re.sub(r"(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)", flip, path)


def expand(shapes):
    out = []
    for muscle, path, mirrored, *rest in shapes:
        detail = bool(rest and rest[0])
        out.append((muscle, path, detail))
        if mirrored:
            out.append((muscle, mirror(path), detail))
    return out


def svg(primary, secondary):
    """Preview in the app's light colours: body parts lighter than untrained muscles."""
    def fill(muscle):
        if muscle is None:
            return "#E7E9E3"
        if muscle in primary:
            return "#5A3E8A"
        if muscle in secondary:
            return "#B7A6D6"
        return "#D5D9D0"

    parts = []
    for offset, shapes in ((0, FRONT), (W + 20, BACK)):
        group = "".join(
            f'<path d="{p}" fill="{fill(m)}" stroke="#FAFBF8" stroke-width="{0.7 if d else 1.2}" stroke-linejoin="round"/>'
            for m, p, d in expand(shapes)
        )
        parts.append(f'<g transform="translate({offset} 0)">{group}</g>')
    width = W * 2 + 40
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{width * 2}" height="840" viewBox="-10 -10 {width} 420">'
            f'<rect x="-10" y="-10" width="{width}" height="420" fill="#FAFBF8"/>{"".join(parts)}</svg>')


def js():
    """The same shapes for the README mockups: [muscle, path, detail]."""
    data = {view: [[m, p, d] for m, p, d in expand(shapes)] for view, shapes in (("front", FRONT), ("back", BACK))}
    return ("// Generated by scripts/anatomy.py from the same shapes as AnatomyShapes.swift (200 x 400).\n"
            f"const ANATOMY = {json.dumps(data)};\n")


def swift():
    def literal(shapes):
        lines = []
        for muscle, path, detail in expand(shapes):
            name = f".{muscle}" if muscle else "nil"
            lines.append(f'        (muscle: {name}, path: "{path}", detail: {"true" if detail else "false"}),')
        return "\n".join(lines)

    return f'''// Generated by scripts/anatomy.py. Edit the generator, not this file.

/// Muscle regions for the front and back body figures, in a 200 × 400 coordinate space.
enum AnatomyShapes {{
    static let width = 200.0
    static let height = 400.0

    static let front: [(muscle: Muscle?, path: String, detail: Bool)] = [
{literal(FRONT)}
    ]

    static let back: [(muscle: Muscle?, path: String, detail: Bool)] = [
{literal(BACK)}
    ]
}}
'''


if __name__ == "__main__":
    if sys.argv[1] == "svg":
        primary = set(filter(None, (sys.argv[2] if len(sys.argv) > 2 else "").split(",")))
        secondary = set(filter(None, (sys.argv[3] if len(sys.argv) > 3 else "").split(",")))
        sys.stdout.write(svg(primary, secondary))
    elif sys.argv[1] == "js":
        sys.stdout.write(js())
    else:
        sys.stdout.write(swift())
