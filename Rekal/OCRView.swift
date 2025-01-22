import Foundation
import SwiftUI
import Vision

struct OCRView: View {
    @State private var isSelected = false
    @State private var isHovering = false
    @State private var text: String
    @State private var normalizedRect: CGRect

    init(_ text: String, normalizedRect: CGRect) {
        self.text = text
        self.normalizedRect = normalizedRect
    }

    // TODO finish
    var body: some View {
        GeometryReader { geometry in
            let boundingBox = NormalizedRect(normalizedRect: normalizedRect)
            let rect = boundingBox.toImageCoordinates(geometry.size, origin: .upperLeft)
            Rectangle()
                .fill(isHovering ? .green : .blue)
                // .fill(isSelected ? .blue : .clear)
                .contentShape(Rectangle())
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
                .onTapGesture(count: 2) {
                    isSelected = true
                    print("double click")
                }
                .onTapGesture(count: 1) {
                    isSelected = false
                    print("single click")
                }
                .onHover { hovering in
                    isHovering = hovering
                    if hovering {
                        NSCursor.iBeam.push()
                    } else {
                        NSCursor.pop()
                    }
                }
        }
    }
}
