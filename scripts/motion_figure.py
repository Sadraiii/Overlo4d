"""Body-part shapes for the animated exercise figure.

The figure that performs an exercise is built from pieces: torso, head, upper arm, forearm, thigh,
shin and foot. Each is drawn here lying along the x axis from its first joint at (0, 0) to its
second, with +y toward the front of the body, in the motion scene's units (the figure is about 175
tall). The arm and the leg are each drawn whole and straight, then cut at the elbow and the knee
into two pieces that overlap. The app and the mockups bend every piece around its joints
(MotionFigureView.swift, mockups/motion-figure.js), and because both pieces of a limb come from one
drawing they still meet without a seam.

    python3 scripts/motion_figure.py swift > Sources/Overlo4d/Exercises/MotionShapes.swift
    python3 scripts/motion_figure.py js > scripts/mockups/motion-shapes.js

Shapes are point lists run through the same smooth curve as scripts/anatomy.py ("!x,y" is a sharp
corner, "R " a rounded polygon) and written out as closely spaced points, which is what lets a
straight edge bend.
"""
import json
import math
import sys

import anatomy
from anatomy import points

DETAIL = True
# The longest step between two points of a written shape, in scene units.
SPACING = 0.7

# name: (outline, [(muscle or None, points[, DETAIL])], [contour lines]). WIDTH then thickens each
# drawing without redrawing it. Later muscles are painted over earlier ones.
SIDE = {
    # Shoulder (0) to hip (50). The buttock belongs to the leg, which is painted over the pelvis.
    "torso": ("-5,3.6 -1,7.6 5,11.4 11,13.2 17,12.2 22,10 30,9.3 38,9.6 45,9 51,7.2 56,4 !59.5,-1.5 58,-6 54,-9.6 48,-11.2 "
              "42,-10.6 37,-8.2 30,-7.6 22,-9.6 14,-11.6 6,-11.2 0,-8.8 -5,-5.2", [
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
    ], []),
    # Head centre (0) to shoulder (15.5).
    "head": ("-9.6,-0.5 -8.4,4.6 -5.5,7.8 -2,8.9 !0.8,10.8 2.6,9 5,8.6 !7.6,7.2 8.8,3.4 11.5,3.4 !17.5,5 !17.5,-6 "
             "11,-6.6 7.5,-7 3.5,-8.8 -1.5,-9.4 -6.5,-7.2", [
        (None, "!4,-1.2 9,0.4 !15.5,4 !15.5,1 9.5,-2.6"),
        (None, "-0.6,-2.4 -2,-0.4 0.4,1.2 2.8,-0.2 2,-2.6"),
    ], []),
    # Shoulder (0), elbow (30), the middle of the grip (60); the wrist is at about 53.
    "arm": ("-6.6,0 -4.6,5.2 2,7.2 9,6.4 16,5.7 24,4.9 29.5,4.5 34,4.9 40,4.35 47,3.4 53,2.7 56.5,3.2 61,3.3 64.6,1.8 "
            "65.4,-0.9 62.5,-2.9 57,-2.9 53,-2.6 47,-3.3 40,-4.35 34,-4.9 30,-5 23,-5.6 14,-6.2 6,-6.8 -1,-6.8 -5,-4.7", [
        ("frontDelts", "!-4.6,3.3 -2,6.4 4,7.1 9,6 !14.6,0.9 8,2.7 2,3.1"),
        ("sideDelts", "!-6.4,0 -4.8,2.7 2,2.6 8,2.1 !14.9,0 8,-2.2 2,-2.6 -4.6,-2.8"),
        ("rearDelts", "!-4.6,-3.4 2,-3.2 8,-2.8 !14.6,-0.9 9,-5.5 3,-6.5 -2,-6.1"),
        ("biceps", "!11.5,3.4 15,5.5 22,5.2 27,3.9 !30,1.9 25,0.6 17,0.6 !12.8,1.3"),
        ("triceps", "!11,-3.6 15,-5.9 22,-5.6 27,-4.7 !30.4,-2.4 25,-0.8 17,-0.8 !13.2,-1.5"),
        ("forearms", "!34.4,0.9 36,4.3 40,4 45,3.1 !50.5,1.8 44,0.5 !38,0.4"),
        ("forearms", "!34.4,-0.7 36,-4.3 40,-4.1 45,-3.1 !50.5,-1.8 44,-0.5 !38,-0.4"),
    ], ["!57.5,-0.2 !63.8,0.4"]),
    # Hip (0), knee (42), ankle (82). The top is the buttock and the side of the hip, lying over the pelvis.
    "leg": ("!-4.5,7.4 0,9.4 8,9.8 18,9 28,7.5 36,6.3 41,6 45,5.5 50,4.7 60,3.9 70,3.3 78,3.1 83,3.2 85.3,1.7 85.3,-1.8 "
            "83,-3.3 78,-3.5 72,-4.3 64,-6.8 56,-8 49.5,-7.2 45,-5.9 40,-5.7 30,-7 20,-8.2 13,-9.1 8.5,-10.4 4,-12.1 -2,-13.2 "
            "-7,-11.8 !-12,-8.2 -10.5,-2 -8,3.6", [
        ("hamstrings", "!6,-3.2 12,-3.4 20,-4 30,-3.7 36,-3.5 !39.8,-4.5 36,-5.8 30,-6.6 20,-7.8 12,-8.8 !6,-9.6"),
        ("glutes", "!-10.6,-7.6 -6.5,-11.2 -2,-12.7 4,-11.6 !9.6,-9.4 !8.4,-3.6 3.5,0.6 -3,1.8 !-8.4,0.4"),
        ("quads", "!2,5.7 8,9.2 18,8.5 28,7 !37.5,5.3 30,3.7 19,4.1 !9,4.7"),
        ("quads", "!5,3.7 12,3.5 22,2.9 31,2.6 !38.6,3.3 38,1.2 35.6,-0.9 29,-2 19,-2.4 10,-1.8 !5,0"),
        (None, "38.9,3 40.8,5.6 43.9,4.4 43.4,1.5 39.9,1"),
        ("calves", "!47.6,-2.2 50.5,-6.4 55.5,-7.5 62,-6.5 !67.5,-3.7 60,-1.6 52,-1.2 !48.2,-1.3"),
        ("calves", "!63.5,-1.6 68.5,-4.7 73,-4 !78.5,-2.7 72,-1 !67,-0.8"),
        (None, "!47.6,1.2 50.5,4 56,3.7 64,2.9 !72,2.3 64,0.5 !54,0.5"),
    ], []),
    # Ankle (0) to toe (12); +y is the top of the foot.
    "foot": ("!-4.6,-2.6 !14,-2.6 15.4,-0.8 13.4,1.3 8,2.5 3.4,4 -1,4.3 -4.4,2.6 -5.4,-0.6", [], []),
}

# How much thicker each drawing is than drawn above: (along it, across it).
WIDTH = {"torso": (1, 1.32), "head": (1.12, 1.12), "arm": (1, 1.32), "leg": (1, 1.32), "foot": (1.1, 1.2)}

# Each limb is cut near its joint into two pieces: (piece, where its first joint is, from, to). The
# upper piece runs a little past the joint and is painted over the lower one, so the lower piece's
# muscles start after that.
LIMBS = {
    "arm": (("upperArm", 0, None, 33.2), ("forearm", 30, 26.5, None)),
    "leg": (("thigh", 0, None, 46), ("shin", 42, 37.5, None)),
}


def along(a, b, t):
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)


def line(a, b, spacing=SPACING):
    """Points on the straight line after a, up to and including b."""
    steps = max(1, math.ceil(math.dist(a, b) / spacing))
    return [along(a, b, step / steps) for step in range(1, steps + 1)]


def cubic(p, c1, c2, q, spacing=SPACING):
    """Points on a cubic Bezier after p, up to and including q."""
    steps = max(1, math.ceil((math.dist(p, c1) + math.dist(c1, c2) + math.dist(c2, q)) / spacing))
    out = []
    for step in range(1, steps + 1):
        t = step / steps
        m = 1 - t
        out.append(tuple(m ** 3 * p[k] + 3 * m * m * t * c1[k] + 3 * m * t * t * c2[k] + t ** 3 * q[k] for k in (0, 1)))
    return out


def curve(pts, closed=True, spacing=SPACING):
    """Points along the curve anatomy.spline draws through pts."""
    n = len(pts)

    def tangent(i):
        if pts[i][2]:
            return (0.0, 0.0)
        if closed:
            a, b = pts[(i - 1) % n], pts[(i + 1) % n]
        else:
            a, b = pts[max(i - 1, 0)], pts[min(i + 1, n - 1)]
        return ((b[0] - a[0]) / 6, (b[1] - a[1]) / 6)

    out = [] if closed else [pts[0][:2]]
    for i in range(n if closed else n - 1):
        p, q = pts[i], pts[(i + 1) % n]
        tp, tq = tangent(i), tangent((i + 1) % n)
        out += cubic(p[:2], (p[0] + tp[0], p[1] + tp[1]), (q[0] - tq[0], q[1] - tq[1]), q[:2], spacing)
    return out


def block(pts, radius):
    """Points along the rounded polygon anatomy.rounded draws."""
    n = len(pts)

    def toward(a, b, distance):
        return along(a, b, min(distance / math.dist(a[:2], b[:2]), 0.5))

    out = []
    for i in range(n):
        corner, before, after = pts[i], pts[i - 1], pts[(i + 1) % n]
        start, end = toward(corner, before, radius), toward(corner, after, radius)
        if out:
            out += line(out[-1], start)
        else:
            out.append(start)
        out += cubic(start, along(start, corner, 0.6), along(end, corner, 0.6), end)
    return out + line(out[-1], out[0])[:-1]


def shape(text, scale=(1, 1), closed=True, radius=1.5):
    is_block = text.startswith("R ")
    pts = [(x * scale[0], y * scale[1], corner) for x, y, corner in points(text[2:] if is_block else text)]
    return block(pts, radius) if is_block else curve(pts, closed)


def clip(polygon, a, b, c):
    """The part of a polygon where a*x + b*y + c >= 0."""
    out = []
    for i, p in enumerate(polygon):
        q = polygon[(i + 1) % len(polygon)]
        fp, fq = a * p[0] + b * p[1] + c, a * q[0] + b * q[1] + c
        if fp >= 0:
            out.append(p)
        if (fp >= 0) != (fq >= 0):
            out.append(along(p, q, fp / (fp - fq)))
    return out


def side():
    drawn = {}
    for name, (outline, regions, contours) in SIDE.items():
        drawn[name] = {
            "outline": shape(outline, WIDTH[name]),
            "regions": [[muscle, shape(text, WIDTH[name]), bool(rest and rest[0])] for muscle, text, *rest in regions],
            "lines": [shape(text, WIDTH[name], closed=False) for text in contours],
        }
    out = {}
    for name, whole in drawn.items():
        if name not in LIMBS:
            out[name] = whole
            continue
        (upper, _, _, cut), (lower, joint, start, _) = LIMBS[name]

        def moved(pts):
            return [(x - joint, y) for x, y in pts]

        def is_upper(pts):
            return max(x for x, _ in pts) <= cut

        out[upper] = {
            "outline": clip(whole["outline"], -1, 0, cut),
            "regions": [r for r in whole["regions"] if is_upper(r[1])],
            "lines": [pts for pts in whole["lines"] if is_upper(pts)],
        }
        out[lower] = {
            "outline": moved(clip(whole["outline"], 1, 0, -start)),
            "regions": [[m, moved(pts), detail] for m, pts, detail in whole["regions"] if not is_upper(pts)],
            "lines": [moved(pts) for pts in whole["lines"] if not is_upper(pts)],
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


def front():
    half = points(anatomy.OUTLINE)
    body = curve(half + [p for p in anatomy.flip(half) if p[0] != anatomy.W / 2], spacing=SPACING / FRONT_WIDTH)

    def frame(name):
        (ax, ay), (bx, by), length = FRONT_JOINTS[name]
        size = math.dist((ax, ay), (bx, by))
        ux, uy = (bx - ax) / size, (by - ay) / size
        return ax, ay, ux, uy, size, length

    def beyond(name, offset):
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
        "upperArm": [arm_side, negate(beyond("upperArm", frame("upperArm")[4] + overlap))],
        "forearm": [beyond("forearm", -overlap), (-1, 0, 48), (0, -1, 262)],
        "thigh": left_leg + [(0, 1, -206), negate(beyond("thigh", frame("thigh")[4] + overlap))],
        "shin": left_leg + [beyond("shin", -overlap)],
    }
    parts = {}
    for name, planes in cuts.items():
        polygon = body
        for plane in planes:
            polygon = clip(polygon, *plane)
        placed = place(name, polygon)
        # The straight cuts are long edges; give them points too, so they bend with the rest.
        outline = [p for i, q in enumerate(placed) for p in line(placed[i - 1], q)]
        parts[name] = {"outline": outline, "regions": [], "lines": []}

    for muscle, text, mirrored, *rest in anatomy.FRONT:
        is_block = text.startswith("R ")
        pts = points(text[2:] if is_block else text)
        name = FRONT_MUSCLES.get(muscle) or ("torso" if pts[0][1] < 100 else "shin")
        sides = [pts, anatomy.flip(pts)] if name == "torso" and mirrored else [pts]
        for each in sides:
            placed = place(name, each)
            parts[name]["regions"].append([muscle, block(placed, 1.1) if is_block else curve(placed), bool(rest and rest[0])])
    for text, mirrored in anatomy.FRONT_LINES:
        pts = points(text)
        x, y = pts[0][0], pts[0][1]
        name = "forearm" if x < 45 else "shin" if y > 290 else "torso"
        for each in ([pts, anatomy.flip(pts)] if name == "torso" else [pts]):
            parts[name]["lines"].append(curve(place(name, each), closed=False))
    return parts


def number(value):
    return f"{round(value, 2):g}"


def flat(pts):
    return [round(v, 2) for p in pts for v in p]


def js():
    def part(data):
        return {
            "outline": flat(data["outline"]),
            "regions": [[m, flat(pts), detail] for m, pts, detail in data["regions"]],
            "lines": [flat(pts) for pts in data["lines"]],
        }

    shapes = {view: {name: part(data) for name, data in parts.items()} for view, parts in (("side", side()), ("front", front()))}
    return ("// Generated by scripts/motion_figure.py from the same shapes as MotionShapes.swift.\n"
            "// Each shape is a list of x, y pairs along the part, from its first joint at 0, 0.\n"
            f"const MOTION_SHAPES = {json.dumps(shapes, separators=(',', ':'))};\n")


def swift():
    def text(pts):
        return " ".join(f"{number(x)},{number(y)}" for x, y in pts)

    def part(name, data):
        regions = "\n".join(
            f'            ({"." + m if m else "nil"}, "{text(pts)}", {"true" if d else "false"}),' for m, pts, d in data["regions"]
        )
        contours = ", ".join(f'"{text(pts)}"' for pts in data["lines"])
        return f'''        .{name}: MotionPartShape(
            outline: "{text(data["outline"])}",
            regions: [
{regions}
            ],
            lines: [{contours}]
        ),'''

    def parts(shapes):
        return "\n".join(part(name, data) for name, data in shapes.items())

    return f'''// Generated by scripts/motion_figure.py. Edit the generator, not this file.

/// The pieces of the animated exercise figure. Each shape is a run of points ("x,y x,y …") along
/// the piece, which lies on the x axis from its first joint at (0, 0) toward its second, in motion
/// scene units. +y is the front of the body in the side view and away from the midline in the front
/// view. The points are close together so that a piece can bend around a joint.
enum MotionShapes {{
    static let side: [MotionBodyPart: MotionPartShape] = [
{parts(side())}
    ]

    static let front: [MotionBodyPart: MotionPartShape] = [
{parts(front())}
    ]
}}
'''


if __name__ == "__main__":
    sys.stdout.write(js() if sys.argv[1] == "js" else swift())
