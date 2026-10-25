"""Anatomy figure generator for Tally.

Muscle regions are drawn for the viewer's left half of a 200x400 figure and mirrored. The same data
produces an SVG preview (for review) and the Swift source with the path strings:

    python3 scripts/anatomy.py swift > Sources/Tally/Exercises/AnatomyShapes.swift
    python3 scripts/anatomy.py svg chest,triceps frontDelts > preview.svg

Paths use only absolute M, L, C and Z so the Swift parser stays tiny.
"""
import re
import sys

W = 200

# (muscle or None for body parts, path, mirrored?)
# Regions are drawn in order, so a later region can sit on top of an earlier one. Overlaying a
# muscle head on its own muscle (the rectus femoris on the quads, the gastrocnemius heads on the
# calves) draws the gap line between the heads without changing what is tapped or filled.
FRONT = [
    (None, "M100,8 C113,8 121,19 121,33 C121,47 112,57 100,57 C88,57 79,47 79,33 C79,19 87,8 100,8 Z", False),  # head
    (None, "M90,55 L110,55 L112,71 L88,71 Z", False),  # neck
    ("traps", "M88,63 C80,68 69,72 57,75 C64,78 70,80 75,80 C81,76 86,73 90,71 Z", True),
    ("sideDelts", "M56,75 C45,76 37,84 33,97 C34,101 36,103 39,103 C42,92 48,84 58,79 Z", True),
    ("frontDelts", "M58,79 C49,85 42,93 39,103 C45,109 52,108 56,104 C59,95 66,87 74,82 C69,80 63,79 58,79 Z", True),
    ("chest", "M75,81 C66,86 59,95 57,105 C59,121 72,131 90,131 C96,131 99,127 99,121 L99,85 C92,81 83,80 75,81 Z", True),
    ("chest", "M75,81 C67,86 61,93 59,99 C72,98 86,97 99,98 L99,85 C92,81 83,80 75,81 Z", True),  # upper chest
    ("biceps", "M38,106 C33,119 32,136 34,150 C39,156 47,154 50,148 C53,134 54,119 55,106 C50,111 43,111 38,106 Z", True),
    ("forearms", "M34,154 C30,172 28,196 29,221 C33,226 39,226 42,221 C46,199 50,176 51,152 C45,158 38,158 34,154 Z", True),
    ("forearms", "M34,154 C31,168 30,182 31,196 C35,186 40,172 43,157 C40,157 37,156 34,154 Z", True),  # brachioradialis
    (None, "M35,225 C28,228 25,238 27,249 C30,257 38,257 41,250 C43,241 42,231 41,226 Z", True),  # hand
    ("abs", "M88,134 C93,133 99,133 99,135 L99,155 L87,156 C86,148 86,141 88,134 Z", True),
    ("abs", "M87,159 L99,158 L99,179 L87,180 C86,173 86,166 87,159 Z", True),
    ("abs", "M87,183 L99,182 L99,224 C94,228 89,224 88,219 C87,207 87,195 87,183 Z", True),
    ("obliques", "M73,133 C77,135 82,135 85,136 C84,158 84,184 86,206 C82,208 77,206 74,199 C69,178 69,155 73,133 Z", True),
    (None, "M74,203 C77,212 83,218 88,222 C92,228 96,232 99,233 L99,246 L89,244 C83,236 77,226 73,214 Z", True),  # hip
    ("quads", "M73,218 C64,240 61,268 63,296 C65,318 71,330 80,332 C87,330 91,318 92,300 C94,280 92,262 88,246 C83,236 78,228 73,218 Z", True),
    ("quads", "M76,226 C83,238 89,254 89,274 C89,292 86,306 82,316 C76,304 72,288 72,270 C72,254 73,238 76,226 Z", True),  # rectus femoris
    ("quads", "M91,288 C95,302 93,318 87,327 C84,331 80,332 77,330 C78,320 83,308 91,288 Z", True),  # vastus medialis
    ("adductors", "M89,247 C95,250 99,256 99,266 C99,282 96,296 92,304 C93,284 93,264 89,247 Z", True),
    (None, "M70,333 C74,338 82,340 88,334 C88,341 86,346 82,348 C76,349 71,345 70,333 Z", True),  # knee
    ("calves", "M70,350 C66,362 65,376 68,388 C72,393 79,392 82,388 C85,376 86,362 84,350 C80,353 74,353 70,350 Z", True),
    (None, "M70,350 C66,362 65,376 68,388 C70,390 73,391 76,390 C76,376 77,362 79,352 C76,352 73,351 70,350 Z", True),  # shin
    (None, "M67,391 C64,394 62,398 66,399 L84,399 C86,397 84,393 82,391 C77,393 72,393 67,391 Z", True),  # foot
]

BACK = [
    (None, "M100,8 C113,8 121,19 121,33 C121,47 112,57 100,57 C88,57 79,47 79,33 C79,19 87,8 100,8 Z", False),  # head
    (None, "M90,55 L110,55 L112,66 L88,66 Z", False),  # neck
    ("traps", "M100,58 C93,64 82,70 62,76 C72,80 83,88 90,100 C94,108 97,116 100,124 C103,116 106,108 110,100 C117,88 128,80 138,76 C118,70 107,64 100,58 Z", False),
    ("sideDelts", "M60,76 C47,77 38,85 33,98 C35,102 37,104 40,104 C43,93 49,85 60,80 Z", True),
    ("rearDelts", "M60,80 C50,85 43,94 40,104 C46,109 53,108 57,104 C60,96 66,89 74,85 C69,82 64,80 60,80 Z", True),
    ("upperBack", "M75,86 C69,93 65,102 64,111 C73,114 83,113 92,108 C88,99 82,91 75,86 Z", True),
    ("triceps", "M38,107 C33,120 32,137 34,151 C40,156 47,154 50,147 C53,133 54,119 56,107 C50,112 43,112 38,107 Z", True),
    ("triceps", "M38,107 C35,116 34,126 35,134 C40,129 43,120 45,110 C42,110 40,109 38,107 Z", True),  # long head
    ("forearms", "M34,154 C30,172 28,196 29,221 C33,226 39,226 42,221 C46,199 50,176 51,152 C45,158 38,158 34,154 Z", True),
    (None, "M35,225 C28,228 25,238 27,249 C30,257 38,257 41,250 C43,241 42,231 41,226 Z", True),  # hand
    ("lats", "M64,114 C61,132 62,152 67,169 C72,184 81,196 92,203 C93,184 93,166 94,150 C93,136 93,123 94,111 C84,116 74,117 64,114 Z", True),
    ("lowerBack", "M96,128 C98,127 99,128 99,130 L99,222 C93,223 86,220 84,213 C83,198 85,180 88,164 C91,150 93,138 96,128 Z", True),
    ("glutes", "M73,212 C65,224 63,241 67,256 C74,268 88,270 99,262 L99,224 C93,217 83,211 73,212 Z", True),
    ("glutes", "M73,212 C69,217 67,222 66,228 C73,224 80,222 87,221 C83,215 78,212 73,212 Z", True),  # glute medius
    ("hamstrings", "M67,262 C63,283 64,305 69,324 C74,332 83,333 88,327 C92,307 94,286 94,268 C86,272 75,271 67,262 Z", True),
    ("hamstrings", "M82,271 C86,271 90,270 93,269 C93,288 91,308 87,326 C84,330 82,330 80,328 C79,310 79,290 82,271 Z", True),  # semitendinosus
    ("adductors", "M95,268 C98,281 99,295 97,309 C95,313 92,312 91,308 C93,294 94,281 95,268 Z", True),
    (None, "M70,333 C74,338 82,340 88,334 C88,341 86,346 82,348 C76,349 71,345 70,333 Z", True),  # knee
    ("calves", "M69,349 C63,359 62,372 66,384 C71,391 79,391 83,384 C86,373 86,360 83,349 C79,345 73,345 69,349 Z", True),
    ("calves", "M69,349 C64,357 63,366 65,375 C69,374 73,371 75,366 L75,347 C73,347 71,347 69,349 Z", True),  # lateral gastrocnemius
    ("calves", "M77,347 L77,366 C79,372 82,375 85,375 C86,366 86,357 83,349 C81,347 79,347 77,347 Z", True),  # medial gastrocnemius
    (None, "M67,391 C64,394 62,398 66,399 L84,399 C86,397 84,393 82,391 C77,393 72,393 67,391 Z", True),  # foot
]


def legs(path: str) -> str:
    """Stretch the lower legs and shorten the thighs, so the shins aren't stubby."""
    def stretch(y):
        if 250 < y <= 348:
            return 250 + (y - 250) * 72 / 98
        if 348 < y <= 391:
            return 322 + (y - 348) * 69 / 43
        return y

    def move(match):
        return f"{match.group(1)},{stretch(float(match.group(2))):.4g}"
    return re.sub(r"(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)", move, path)


def mirror(path: str) -> str:
    """Mirror x around the figure's centre line."""
    def flip(match):
        x, y = float(match.group(1)), float(match.group(2))
        return f"{W - x:g},{y:g}"
    return re.sub(r"(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)", flip, path)


def expand(shapes):
    out = []
    for muscle, path, mirrored in shapes:
        path = legs(path)
        out.append((muscle, path))
        if mirrored:
            out.append((muscle, mirror(path)))
    return out


def svg(primary, secondary):
    def fill(muscle):
        if muscle is None:
            return "#C5CBC2"
        if muscle in primary:
            return "#5A3E8A"
        if muscle in secondary:
            return "#B7A6D6"
        return "#DADED6"

    parts = []
    for offset, shapes in ((0, FRONT), (W + 20, BACK)):
        group = "".join(
            f'<path d="{p}" fill="{fill(m)}" stroke="#EEF0EB" stroke-width="1.6" stroke-linejoin="round"/>'
            for m, p in expand(shapes)
        )
        parts.append(f'<g transform="translate({offset} 0)">{group}</g>')
    width = W * 2 + 40
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{width * 2}" height="840" viewBox="-10 -10 {width} 420">'
            f'<rect x="-10" y="-10" width="{width}" height="420" fill="#EEF0EB"/>{"".join(parts)}</svg>')


def swift():
    def literal(shapes):
        lines = []
        for muscle, path in expand(shapes):
            name = f".{muscle}" if muscle else "nil"
            lines.append(f'        (muscle: {name}, path: "{path}"),')
        return "\n".join(lines)

    return f'''// Generated by scripts/anatomy.py. Edit the generator, not this file.

/// Muscle regions for the front and back body figures, in a 200 × 400 coordinate space.
enum AnatomyShapes {{
    static let width = 200.0
    static let height = 400.0

    static let front: [(muscle: Muscle?, path: String)] = [
{literal(FRONT)}
    ]

    static let back: [(muscle: Muscle?, path: String)] = [
{literal(BACK)}
    ]
}}
'''


if __name__ == "__main__":
    if sys.argv[1] == "svg":
        primary = set(filter(None, (sys.argv[2] if len(sys.argv) > 2 else "").split(",")))
        secondary = set(filter(None, (sys.argv[3] if len(sys.argv) > 3 else "").split(",")))
        sys.stdout.write(svg(primary, secondary))
    else:
        sys.stdout.write(swift())
