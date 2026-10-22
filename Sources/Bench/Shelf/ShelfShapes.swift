// ShelfShapes.swift — the two marks the boards draw for the shelf, as shapes
// so they take whatever colour and weight they are given: the check (the
// toast's clay one, the "On your shelf" chip's) and the shelf glyph (the
// toolbar's pill, Results' Add to Shelf).
import SwiftUI

/// The check the board draws: `M5 12l5 5 9-10` in a 24-point square.
struct ShelfCheck: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x / 24, y: rect.minY + rect.height * y / 24)
        }
        var path = Path()
        path.move(to: point(5, 12))
        path.addLine(to: point(10, 17))
        path.addLine(to: point(19, 7))
        return path
    }
}

/// The glyph the board draws: a shelf with three upright books,
/// `M3 20h18M5 20V9h4v11M10 20V5h4v15M15 20v-8h4v8` in a 24-point square.
struct ShelfGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x / 24, y: rect.minY + rect.height * y / 24)
        }
        var path = Path()
        path.move(to: point(3, 20))
        path.addLine(to: point(21, 20))
        path.move(to: point(5, 20))
        path.addLine(to: point(5, 9))
        path.addLine(to: point(9, 9))
        path.addLine(to: point(9, 20))
        path.move(to: point(10, 20))
        path.addLine(to: point(10, 5))
        path.addLine(to: point(14, 5))
        path.addLine(to: point(14, 20))
        path.move(to: point(15, 20))
        path.addLine(to: point(15, 12))
        path.addLine(to: point(19, 12))
        path.addLine(to: point(19, 20))
        return path
    }
}
