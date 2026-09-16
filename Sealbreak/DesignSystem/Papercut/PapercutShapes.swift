import SwiftUI

struct HeaderWaveShape: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 393
        let sy = rect.height / 165
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 393 * sx, y: 0))
        path.addLine(to: CGPoint(x: 393 * sx, y: 130 * sy))
        path.addCurve(
            to: CGPoint(x: 240 * sx, y: 124 * sy),
            control1: CGPoint(x: 339 * sx, y: 152 * sy),
            control2: CGPoint(x: 290 * sx, y: 141 * sy)
        )
        path.addCurve(
            to: CGPoint(x: 0, y: 127 * sy),
            control1: CGPoint(x: 167 * sx, y: 99 * sy),
            control2: CGPoint(x: 105 * sx, y: 155 * sy)
        )
        path.closeSubpath()
        return path
    }
}

struct MountainBackShape: Shape {
    func path(in rect: CGRect) -> Path {
        polygon(
            points: [
                (0, 110), (55, 60), (97, 90), (152, 36), (198, 82),
                (243, 45), (307, 106), (353, 76), (393, 110),
                (393, 170), (0, 170)
            ],
            source: CGSize(width: 393, height: 170),
            rect: rect
        )
    }
}

struct MountainMidShape: Shape {
    func path(in rect: CGRect) -> Path {
        polygon(
            points: [
                (0, 90), (52, 59), (91, 80), (143, 38), (187, 80),
                (230, 49), (294, 95), (338, 75), (393, 105),
                (393, 145), (0, 145)
            ],
            source: CGSize(width: 393, height: 145),
            rect: rect
        )
    }
}

struct WaterShape: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 393
        let sy = rect.height / 92
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 18 * sy))
        path.addCurve(
            to: CGPoint(x: 190 * sx, y: 20 * sy),
            control1: CGPoint(x: 62 * sx, y: 30 * sy),
            control2: CGPoint(x: 119 * sx, y: 10 * sy)
        )
        path.addCurve(
            to: CGPoint(x: 393 * sx, y: 30 * sy),
            control1: CGPoint(x: 263 * sx, y: 31 * sy),
            control2: CGPoint(x: 319 * sx, y: 19 * sy)
        )
        path.addLine(to: CGPoint(x: 393 * sx, y: 92 * sy))
        path.addLine(to: CGPoint(x: 0, y: 92 * sy))
        path.closeSubpath()
        return path
    }
}

struct SunReflectionShape: Shape {
    func path(in rect: CGRect) -> Path {
        let source = CGSize(width: 128, height: 38)
        var result = Path()
        for points in [
            [(0.0, 0.0), (128.0, 0.0), (108.0, 9.0), (17.0, 9.0)],
            [(28.0, 18.0), (108.0, 18.0), (94.0, 25.0), (38.0, 25.0)],
            [(48.0, 33.0), (91.0, 33.0), (81.0, 38.0), (56.0, 38.0)]
        ] {
            result.addPath(polygon(points: points, source: source, rect: rect))
        }
        return result
    }
}

struct TreeShape: Shape {
    let points: [(Double, Double)]
    let sourceWidth: Double

    func path(in rect: CGRect) -> Path {
        polygon(points: points, source: CGSize(width: sourceWidth, height: 150), rect: rect)
    }
}

private func polygon(
    points: [(Double, Double)],
    source: CGSize,
    rect: CGRect
) -> Path {
    var path = Path()
    guard let first = points.first else { return path }
    let sx = rect.width / source.width
    let sy = rect.height / source.height
    path.move(to: CGPoint(x: first.0 * sx, y: first.1 * sy))
    for point in points.dropFirst() {
        path.addLine(to: CGPoint(x: point.0 * sx, y: point.1 * sy))
    }
    path.closeSubpath()
    return path
}
