// Draws every move with the app's MotionFrame, start, middle, end and the still, as a page of SVGs.
import SwiftUI
import TallyCore

let roles: [Muscle: MuscleRole] = [
    .quads: .primary, .glutes: .primary, .chest: .primary, .lats: .primary, .sideDelts: .primary,
    .hamstrings: .secondary, .triceps: .secondary, .frontDelts: .secondary, .biceps: .secondary,
    .abs: .tertiary, .calves: .tertiary, .forearms: .tertiary,
]

func svg(_ move: MotionMove, _ load: MotionLoad, phases: [Double], size: CGSize) -> String {
    let recorder = Recorder()
    let frame = MotionFrame(
        pattern: move.pattern, load: load, roles: roles, size: size,
        skin: AnatomyFigure.skin, tissue: AnatomyFigure.tissue, untrained: AnatomyFigure.untrained
    )
    frame.draw(phases: phases, in: GraphicsContext(recorder))
    return "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(size.width)\" height=\"\(size.height)\" style=\"background:#fff;border-radius:12px\">\(recorder.out)</svg>"
}

// The load of the first built-in exercise that uses each move.
var loads: [MotionMove: MotionLoad] = [:]
for (_, entry) in MotionLibrary.exercises.sorted(by: { $0.key < $1.key }) where loads[entry.0] == nil || loads[entry.0] == MotionLoad.none {
    loads[entry.0] = entry.1
}
var html = "<html><body style=\"margin:0;padding:12px;background:#F3F4F1;font:600 13px sans-serif\">"
for move in MotionMove.allCases {
    let load = loads[move] ?? .none
    html += "<div style=\"margin:10px 0 4px\">\(move.rawValue)</div><div style=\"display:flex;gap:8px;align-items:flex-start\">"
    for phase in [0.0, 0.5, 1.0] { html += svg(move, load, phases: [phase], size: CGSize(width: 250, height: 210)) }
    html += svg(move, load, phases: [0, 1], size: CGSize(width: 250, height: 210))
    html += svg(move, load, phases: [0, 1], size: CGSize(width: 56, height: 56)) + "</div>"
}
print(html + "</body></html>")
