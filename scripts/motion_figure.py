"""Body-part shapes for the animated exercise figure.

The figure that performs an exercise is built from jointed parts: torso, head, upper arm, forearm,
thigh, shin and foot. Each part is drawn here once, lying along the x axis from its first joint at
(0, 0) to its second, with +y toward the front of the body, in the motion scene's units (the figure
is about 175 tall). The app and the mockups place each part on the skeleton frame by frame.

    python3 scripts/motion_figure.py swift > Sources/Tally/Exercises/MotionShapes.swift
    python3 scripts/motion_figure.py js > scripts/mockups/motion-shapes.js

Shapes are point lists run through the same smooth curve as scripts/anatomy.py ("!x,y" is a sharp
corner, "R " a rounded polygon). Each part has an outline that clips its muscles.
"""
import json
import sys

import anatomy
from anatomy import points, rounded, spline

DETAIL = True

# name: (length between the joints, outline, [(muscle or None, points[, DETAIL])], [contour lines])
# WIDTH then thickens each part without redrawing it.
SIDE = {
    # Shoulder (0) to hip (50).
    "torso": (50, "-5,3.6 -1,7.6 5,11.4 11,13.2 17,12.2 22,10 30,9.3 38,9.6 45,9 51,7.2 56,4 !59.5,-1.5 58,-7.5 54,-12 48,-13.2 "
                  "42,-11 37,-8.2 30,-7.6 22,-9.6 14,-11.6 6,-11.2 0,-8.8 -5,-5.2", [
        ("traps", "!-5,-4.6 -1,-8.2 5,-10.6 !11.5,-11.4 10.5,-7 4.5,-4.4 !-2,-2.4"),
        ("upperBack", "!12.5,-11.2 19.5,-10 !21,-5.6 15,-3.6 !10,-5.6"),
        ("lats", "!8,-0.5 14,2.8 22,3.2 30,1 !36.5,-3.4 !36.5,-7.6 29,-7.4 !22,-9 21.5,-4.6 14,-2.6"),
        ("lowerBack", "!37.8,-8 42.5,-10.4 !44,-5.4 !38,-2.6"),
        ("obliques", "!23.5,4.2 30,3.4 38,3.7 !47.5,3.4 !47.5,-1.8 41,-4 !37,-1.6 30.5,2.4"),
        ("chest", "!-1,6.4 5,10.8 11,12.5 17,11.4 !21,8.6 17,4.6 10,3 !3,3.6"),
        ("abs", "R 22.6,4.6 28.6,4.8 28.6,10.4 22.6,10.4"),
        ("abs", "R 29.8,4.8 35.8,4.9 35.8,10.4 29.8,10.4"),
        ("abs", "R 37,4.9 43,4.8 43,10.4 37,10.4"),
        ("abs", "R 44.2,4.8 51,4.4 53.5,7.5 50,10.4 44.2,10.4"),
        ("glutes", "!44.5,-11.4 49,-12.8 54,-11.6 58.5,-7 !57.5,-1.4 52,1.4 46,0.4 !43,-4.6"),
    ], []),
    # Head centre (0) to shoulder (15.5).
    "head": (15.5, "-9.6,-0.5 -8.4,4.6 -5.5,7.8 -2,8.9 !0.8,10.8 2.6,9 5,8.6 !7.6,7.2 8.8,3.4 11.5,3.4 !17.5,5 !17.5,-6 "
                   "11,-6.6 7.5,-7 3.5,-8.8 -1.5,-9.4 -6.5,-7.2", [
        (None, "!4,-1.2 9,0.4 !15.5,4 !15.5,1 9.5,-2.6"),
        (None, "-0.6,-2.4 -2,-0.4 0.4,1.2 2.8,-0.2 2,-2.6"),
    ], []),
    # Shoulder (0) to elbow (30).
    "upperArm": (30, "-6.6,0 -4.6,5.2 2,7.2 9,6.4 16,5.7 24,4.9 31,4.3 !34,0 31,-4.5 23,-5.5 14,-6.1 6,-6.7 -1,-6.7 -5,-4.6", [
        ("frontDelts", "!-4.6,3.3 -2,6.4 4,7.1 9,6 !14.6,0.9 8,2.7 2,3.1"),
        ("sideDelts", "!-6.4,0 -4.8,2.7 2,2.6 8,2.1 !14.9,0 8,-2.2 2,-2.6 -4.6,-2.8"),
        ("rearDelts", "!-4.6,-3.4 2,-3.2 8,-2.8 !14.6,-0.9 9,-5.5 3,-6.5 -2,-6.1"),
        ("biceps", "!11.5,3.4 15,5.5 22,5.2 27.5,3.7 !30.6,1.7 25,0.6 17,0.6 !12.8,1.3"),
        ("triceps", "!11,-3.6 15,-5.9 22,-5.6 27.5,-4.5 !31.2,-2.2 25,-0.8 17,-0.8 !13.2,-1.5"),
    ], []),
    # Elbow (0) to the middle of the grip (30); the wrist is at about 23.
    "forearm": (30, "-4.2,0 -2.6,4.1 3,5 10,4.4 17,3.4 23,2.7 26.5,3.2 31,3.3 34.6,1.8 35.4,-0.9 32.5,-2.9 27,-2.9 23,-2.6 "
                    "17,-3.3 10,-4.4 3,-4.9 -2.6,-3.9", [
        ("forearms", "!0,0.9 3,4.4 9,4 15,3.1 !20.5,1.8 14,0.5 !7,0.4"),
        ("forearms", "!0,-0.7 3,-4.3 9,-4.1 15,-3.1 !20.5,-1.8 14,-0.5 !7,-0.4"),
    ], ["!27.5,-0.2 !33.8,0.4"]),
    # Hip (0) to knee (42).
    "thigh": (42, "-9.4,0 -6.8,6.6 0,9.4 8,9.8 18,9 28,7.5 36,6.3 42,5.9 !46.4,1.2 44,-4.9 38,-5.7 30,-6.9 20,-8.1 10,-9.2 "
                  "2,-9.5 -6.2,-6.6", [
        ("glutes", "!-8.8,-1.6 -6.2,-6.4 0,-9.2 !7,-9.4 !5,-3.2 -1,-0.2"),
        ("quads", "!2,5.7 8,9.2 18,8.5 28,7 !37.5,5.3 30,3.7 19,4.1 !9,4.7"),
        ("quads", "!5,3.7 12,3.5 22,2.9 31,2.5 !38.8,3.9 !37.5,-0.5 29,-2 19,-2.4 10,-1.8 !5,0"),
        ("hamstrings", "!4,-3 10,-3.4 20,-4 30,-3.6 !38.5,-2 !38.5,-5.2 30,-6.5 20,-7.7 10,-8.7 !4,-8.4"),
        (None, "40.4,3 42.6,5.7 45.6,4.2 44.8,1.3 41.4,0.9"),
    ], []),
    # Knee (0) to ankle (40).
    "shin": (40, "-5.2,0 -3,5 2,5.5 8,4.7 18,3.9 28,3.3 36,3.1 41,3.3 !43.4,0 41,-3.3 36,-3.5 30,-4.3 22,-6.9 14,-8.1 "
                 "7,-7.3 1,-5.9 -4,-4.1", [
        ("calves", "!1,-2 6,-6.8 13,-7.6 20,-6.6 !25.5,-3.7 18,-1.6 10,-1.2 !4,-1.3"),
        ("calves", "!21.5,-1.6 26.5,-4.7 31,-4 !36.5,-2.7 30,-1 !25,-0.8"),
        (None, "!3,1.1 6,4.1 14,3.7 22,2.9 !30,2.3 22,0.5 !12,0.5"),
    ], []),
    # Ankle (0) to toe (12); +y is the top of the foot.
    "foot": (12, "!-4.6,-2.6 !14,-2.6 15.4,-0.8 13.4,1.3 8,2.5 3.4,4 -1,4.3 -4.4,2.6 -5.4,-0.6", [], []),
}


# How much thicker each part is than drawn above: (along the part, across it).
WIDTH = {"torso": (1, 1.32), "head": (1.12, 1.12), "upperArm": (1, 1.34), "forearm": (1, 1.3), "thigh": (1, 1.34),
         "shin": (1, 1.3), "foot": (1.1, 1.2)}


def path(text, scale, closed=True):
    is_rounded = text.startswith("R ")
    pts = [(x * scale[0], y * scale[1], corner) for x, y, corner in points(text[2:] if is_rounded else text)]
    return rounded(pts, radius=1.5) if is_rounded else spline(pts, closed)


def build(parts):
    out = {}
    for name, (length, outline, regions, contours) in parts.items():
        out[name] = {
            "length": length,
            "outline": path(outline, WIDTH[name]),
            "regions": [[muscle, path(text, WIDTH[name]), bool(rest and rest[0])] for muscle, text, *rest in regions],
            "lines": [path(text, WIDTH[name], closed=False) for text in contours],
        }
    return out


# MARK: Front view
#
# The front-view parts are cut from the muscle figure in scripts/anatomy.py, so an exercise seen from
# the front shows the same body as the muscle map. Joints are in that figure's 200 x 400 space, for
# its left half; each part is turned to lie along the x axis with +y pointing away from the midline.

FRONT_JOINTS = {
    "head": ((100, 29), (100, 74), 15.5),     # head centre to the base of the neck
    "torso": ((100, 74), (100, 216), 50),     # base of the neck to the pelvis
    "upperArm": ((53, 90), (43, 158), 30),
    "forearm": ((43, 158), (31, 228), 30),    # elbow to the middle of the grip
    "thigh": ((80, 218), (77, 302), 42),
    "shin": ((77, 302), (78, 380), 40),       # the foot comes with it
}
# Scene units per figure unit across a part; along it each part is fitted to its own length.
FRONT_WIDTH = 0.43
FRONT_MUSCLES = {"traps": "torso", "chest": "torso", "abs": "torso", "obliques": "torso", "sideDelts": "upperArm",
                 "frontDelts": "upperArm", "biceps": "upperArm", "triceps": "upperArm", "forearms": "forearm",
                 "quads": "thigh", "adductors": "thigh", "calves": "shin"}


def sample(pts, steps=5):
    """Points along the closed curve `spline` draws through pts."""
    n = len(pts)

    def tangent(i):
        if pts[i][2]:
            return (0.0, 0.0)
        a, b = pts[(i - 1) % n], pts[(i + 1) % n]
        return ((b[0] - a[0]) / 6, (b[1] - a[1]) / 6)

    out = []
    for i in range(n):
        p, q = pts[i], pts[(i + 1) % n]
        tp, tq = tangent(i), tangent((i + 1) % n)
        c1, c2 = (p[0] + tp[0], p[1] + tp[1]), (q[0] - tq[0], q[1] - tq[1])
        for step in range(steps):
            t = step / steps
            m = 1 - t
            out.append(tuple(m ** 3 * p[k] + 3 * m * m * t * c1[k] + 3 * m * t * t * c2[k] + t ** 3 * q[k] for k in (0, 1)))
    return out


def clip(polygon, a, b, c):
    """The part of a polygon where a*x + b*y + c >= 0."""
    out = []
    for i, p in enumerate(polygon):
        q = polygon[(i + 1) % len(polygon)]
        fp, fq = a * p[0] + b * p[1] + c, a * q[0] + b * q[1] + c
        if fp >= 0:
            out.append(p)
        if (fp >= 0) != (fq >= 0):
            t = fp / (fp - fq)
            out.append((p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t))
    return out


def front():
    half = points(anatomy.OUTLINE)
    body = sample(half + [p for p in anatomy.flip(half) if p[0] != anatomy.W / 2])

    def frame(name):
        (ax, ay), (bx, by), length = FRONT_JOINTS[name]
        size = ((bx - ax) ** 2 + (by - ay) ** 2) ** 0.5
        ux, uy = (bx - ax) / size, (by - ay) / size
        return ax, ay, ux, uy, size, length

    def along(name, offset):
        """Half-plane coefficients for "at least `offset` figure units along the part from its first joint"."""
        ax, ay, ux, uy, _, _ = frame(name)
        return ux, uy, -(ux * ax + uy * ay) - offset

    def place(name, pts):
        ax, ay, ux, uy, size, length = frame(name)
        return [(((x - ax) * ux + (y - ay) * uy) * length / size, (-(x - ax) * uy + (y - ay) * ux) * FRONT_WIDTH, *rest)
                for x, y, *rest in pts]

    def negate(plane):
        return tuple(-v for v in plane)

    arm_side = (-49, 4, 49 * 58 - 4 * 70)          # left of the line from the shoulder top to the armpit
    other_arm_side = (49, 4, -49 * 142 - 4 * 70)
    left_leg = [(-1, 0, 100), (1, 0, -48)]
    overlap = 5
    cuts = {
        "head": [(0, -1, 66)],
        "torso": [negate(arm_side), negate(other_arm_side), (0, 1, -60), (0, -1, 232)],
        "upperArm": [arm_side, negate(along("upperArm", frame("upperArm")[4] + overlap))],
        "forearm": [along("forearm", -overlap), (-1, 0, 48), (0, -1, 262)],
        "thigh": left_leg + [(0, 1, -206), negate(along("thigh", frame("thigh")[4] + overlap))],
        "shin": left_leg + [along("shin", -overlap)],
    }
    parts = {}
    for name, planes in cuts.items():
        polygon = body
        for plane in planes:
            polygon = clip(polygon, *plane)
        d = " ".join(f"{'M' if i == 0 else 'L'}{anatomy.fmt(x)},{anatomy.fmt(y)}" for i, (x, y) in enumerate(place(name, polygon)))
        parts[name] = {"length": FRONT_JOINTS[name][2], "outline": d + " Z", "regions": [], "lines": []}

    def draw(name, text, pts, closed=True):
        if text.startswith("R "):
            return rounded(place(name, pts), radius=1.1)
        return spline(place(name, pts), closed)

    for muscle, text, mirrored, *rest in anatomy.FRONT:
        pts = points(text[2:] if text.startswith("R ") else text)
        name = FRONT_MUSCLES.get(muscle) or ("torso" if pts[0][1] < 100 else "shin")
        sides = [pts, anatomy.flip(pts)] if name == "torso" and mirrored else [pts]
        for side in sides:
            parts[name]["regions"].append([muscle, draw(name, text, side), bool(rest and rest[0])])
    for text, mirrored in anatomy.FRONT_LINES:
        pts = points(text)
        x, y = pts[0][0], pts[0][1]
        name = "forearm" if x < 45 else "shin" if y > 290 else "torso"
        for side in ([pts, anatomy.flip(pts)] if name == "torso" else [pts]):
            parts[name]["lines"].append(spline(place(name, side), closed=False))
    return parts


def js():
    return ("// Generated by scripts/motion_figure.py from the same shapes as MotionShapes.swift.\n"
            f"const MOTION_SHAPES = {json.dumps({'side': build(SIDE), 'front': front()})};\n")


def swift():
    def part(name, data):
        regions = "\n".join(
            f'            ({"." + m if m else "nil"}, "{p}", {"true" if d else "false"}),' for m, p, d in data["regions"]
        )
        contours = ", ".join(f'"{p}"' for p in data["lines"])
        return f'''        .{name}: MotionPartShape(
            length: {data["length"]},
            outline: "{data["outline"]}",
            regions: [
{regions}
            ],
            lines: [{contours}]
        ),'''

    def parts(shapes):
        return "\n".join(part(name, data) for name, data in shapes.items())

    return f'''// Generated by scripts/motion_figure.py. Edit the generator, not this file.

/// The body parts of the animated exercise figure, each lying along the x axis from its first joint
/// at (0, 0) to its second, in motion scene units. +y is the front of the body in the side view and
/// away from the midline in the front view.
enum MotionShapes {{
    static let side: [MotionBodyPart: MotionPartShape] = [
{parts(build(SIDE))}
    ]

    static let front: [MotionBodyPart: MotionPartShape] = [
{parts(front())}
    ]
}}
'''


if __name__ == "__main__":
    sys.stdout.write(js() if sys.argv[1] == "js" else swift())
