// A stand-in for the parts of SwiftUI the figure drawing uses, which records drawing as SVG.
@_exported import Foundation

public struct Color: Sendable, Equatable {
    public var r, g, b, a: Double
    public init(r: Double, g: Double, b: Double, a: Double = 1) { self.r = r; self.g = g; self.b = b; self.a = a }
    public init(_ hex: UInt32) { self.init(r: Double((hex >> 16) & 255) / 255, g: Double((hex >> 8) & 255) / 255, b: Double(hex & 255) / 255) }
    public static let white = Color(0xFFFFFF)
    public static let black = Color(0x000000)
    public func opacity(_ o: Double) -> Color { Color(r: r, g: g, b: b, a: a * o) }
    public func mix(with o: Color, by t: Double) -> Color { Color(r: r + (o.r - r) * t, g: g + (o.g - g) * t, b: b + (o.b - b) * t, a: a + (o.a - a) * t) }
    var css: String { "rgba(\(Int((r * 255).rounded())),\(Int((g * 255).rounded())),\(Int((b * 255).rounded())),\(a))" }
}
public struct Path: Sendable, Equatable {
    public var d = ""
    var lo = CGPoint(x: Double.infinity, y: Double.infinity), hi = CGPoint(x: -Double.infinity, y: -Double.infinity)
    mutating func see(_ p: CGPoint) { lo = CGPoint(x: min(lo.x, p.x), y: min(lo.y, p.y)); hi = CGPoint(x: max(hi.x, p.x), y: max(hi.y, p.y)) }
    public init() {}
    public init(ellipseIn r: CGRect) {
        let rx = r.width / 2, ry = r.height / 2
        d = "M\(r.minX),\(r.midY) A\(rx),\(ry) 0 1,0 \(r.maxX),\(r.midY) A\(rx),\(ry) 0 1,0 \(r.minX),\(r.midY) Z"
        see(r.origin); see(CGPoint(x: r.maxX, y: r.maxY))
    }
    public init(roundedRect r: CGRect, cornerRadius c: CGFloat) {
        d = "M\(r.minX + c),\(r.minY) H\(r.maxX - c) A\(c),\(c) 0 0,1 \(r.maxX),\(r.minY + c) V\(r.maxY - c) A\(c),\(c) 0 0,1 \(r.maxX - c),\(r.maxY) H\(r.minX + c) A\(c),\(c) 0 0,1 \(r.minX),\(r.maxY - c) V\(r.minY + c) A\(c),\(c) 0 0,1 \(r.minX + c),\(r.minY) Z"
        see(r.origin); see(CGPoint(x: r.maxX, y: r.maxY))
    }
    public mutating func move(to p: CGPoint) { d += "M\(p.x),\(p.y) "; see(p) }
    public mutating func addLine(to p: CGPoint) { d += "L\(p.x),\(p.y) "; see(p) }
    public mutating func addCurve(to p: CGPoint, control1: CGPoint, control2: CGPoint) {
        d += "C\(control1.x),\(control1.y) \(control2.x),\(control2.y) \(p.x),\(p.y) "; see(p); see(control1); see(control2)
    }
    public mutating func closeSubpath() { d += "Z " }
    public var boundingRect: CGRect { CGRect(x: lo.x, y: lo.y, width: hi.x - lo.x, height: hi.y - lo.y) }
}
public enum CGLineCap: String, Sendable { case butt, round, square }
public enum CGLineJoin: String, Sendable { case miter, round, bevel }
public struct StrokeStyle: Sendable {
    var width: CGFloat, cap: CGLineCap, join: CGLineJoin
    public init(lineWidth: CGFloat = 1, lineCap: CGLineCap = .butt, lineJoin: CGLineJoin = .miter, miterLimit: CGFloat = 10, dash: [CGFloat] = [], dashPhase: CGFloat = 0) {
        width = lineWidth; cap = lineCap; join = lineJoin
    }
}
public struct Gradient: Sendable {
    public struct Stop: Sendable { var color: Color, location: CGFloat; public init(color: Color, location: CGFloat) { self.color = color; self.location = location } }
    var stops: [Stop]
    public init(stops: [Stop]) { self.stops = stops }
}
public struct FillStyle { public init() {} }
public struct CGAffineTransform: Sendable {
    var text: String
    public init(a: CGFloat, b: CGFloat, c: CGFloat, d: CGFloat, tx: CGFloat, ty: CGFloat) { text = "matrix(\(a) \(b) \(c) \(d) \(tx) \(ty))" }
}
public final class Recorder: @unchecked Sendable {
    public var out = ""
    nonisolated(unsafe) static var count = 0
    public init() {}
    func id() -> String { Recorder.count += 1; return "r\(Recorder.count)" }
}
public struct GraphicsContext {
    public struct Shading {
        enum Kind { case color(Color), radial(Gradient, CGPoint, CGFloat, CGFloat) }
        let kind: Kind
        public static func color(_ c: Color) -> Shading { Shading(kind: .color(c)) }
        public static func radialGradient(_ g: Gradient, center: CGPoint, startRadius: CGFloat, endRadius: CGFloat) -> Shading { Shading(kind: .radial(g, center, startRadius, endRadius)) }
    }
    let rec: Recorder
    public var opacity: Double = 1
    var transforms: [String] = []
    var clips: [String] = []
    public init(_ rec: Recorder) { self.rec = rec }

    private var transform: String { transforms.isEmpty ? "" : " transform=\"\(transforms.joined(separator: " "))\"" }
    private func paint(_ shading: Shading) -> String {
        switch shading.kind {
        case .color(let c): return c.css
        case .radial(let g, let center, _, let end):
            let id = rec.id()
            let stops = g.stops.map { "<stop offset=\"\($0.location)\" stop-color=\"\($0.color.css)\"/>" }.joined()
            rec.out += "<radialGradient id=\"\(id)\" gradientUnits=\"userSpaceOnUse\" cx=\"\(center.x)\" cy=\"\(center.y)\" r=\"\(end)\">\(stops)</radialGradient>\n"
            return "url(#\(id))"
        }
    }
    private func emit(_ element: String) {
        var s = element
        for id in clips.reversed() { s = "<g clip-path=\"url(#\(id))\">\(s)</g>" }
        if opacity < 1 { s = "<g opacity=\"\(opacity)\">\(s)</g>" }
        rec.out += s + "\n"
    }
    public func fill(_ path: Path, with shading: Shading, style: FillStyle = FillStyle()) {
        emit("<path d=\"\(path.d)\"\(transform) fill=\"\(paint(shading))\"/>")
    }
    public func stroke(_ path: Path, with shading: Shading, lineWidth: CGFloat = 1) {
        stroke(path, with: shading, style: StrokeStyle(lineWidth: lineWidth))
    }
    public func stroke(_ path: Path, with shading: Shading, style: StrokeStyle) {
        emit("<path d=\"\(path.d)\"\(transform) fill=\"none\" stroke=\"\(paint(shading))\" stroke-width=\"\(style.width)\" stroke-linecap=\"\(style.cap.rawValue)\" stroke-linejoin=\"\(style.join.rawValue)\"/>")
    }
    public mutating func clip(to path: Path) {
        let id = rec.id()
        rec.out += "<clipPath id=\"\(id)\"><path d=\"\(path.d)\"\(transform)/></clipPath>\n"
        clips.append(id)
    }
    public mutating func concatenate(_ m: CGAffineTransform) { transforms.append(m.text) }
    public func drawLayer(content: (inout GraphicsContext) throws -> Void) rethrows {
        var inner = self
        inner.opacity = 1
        rec.out += "<g opacity=\"\(opacity)\">\n"
        try content(&inner)
        rec.out += "</g>\n"
    }
}
@MainActor @preconcurrency public protocol View {
    associatedtype Body: View
    @ViewBuilder @MainActor @preconcurrency var body: Body { get }
}
extension Never: View { public var body: Never { fatalError() } }
@resultBuilder public struct ViewBuilder {
    public static func buildBlock<V: View>(_ v: V) -> V { v }
    public static func buildExpression<V: View>(_ v: V) -> V { v }
    public static func buildEither<T: View, F: View>(first: T) -> _Cond<T, F> { _Cond() }
    public static func buildEither<T: View, F: View>(second: F) -> _Cond<T, F> { _Cond() }
}
public struct _Cond<T: View, F: View>: View { nonisolated public init() {}; public var body: Never { fatalError() } }
public struct Canvas: View {
    public init(renderer: @escaping (inout GraphicsContext, CGSize) -> Void) {}
    public var body: Never { fatalError() }
}
public struct AnimationTimelineSchedule {
    public static var animation: AnimationTimelineSchedule { AnimationTimelineSchedule() }
    public static func animation(minimumInterval: Double? = nil, paused: Bool = false) -> AnimationTimelineSchedule { AnimationTimelineSchedule() }
}
public struct TimelineViewDefaultContext { public var date: Date }
public struct TimelineView<Content: View>: View {
    public init(_ schedule: AnimationTimelineSchedule, @ViewBuilder content: @escaping (TimelineViewDefaultContext) -> Content) {}
    public var body: Never { fatalError() }
}
extension View { public func accessibilityHidden(_ hidden: Bool) -> some View { self } }
public struct EnvironmentValues { public var accessibilityReduceMotion: Bool { false } }
@propertyWrapper public struct Environment<Value> {
    public init(_ keyPath: KeyPath<EnvironmentValues, Value>) {}
    public var wrappedValue: Value { fatalError() }
}
