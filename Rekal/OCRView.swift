import SwiftUI
import Vision

struct OCRView: View {
    @State private var isSelected = false
    @State private var isHovering = false
    @State private var ocrResults: [OCRResult]? = nil
    var snapshot: Snapshot

    var body: some View {
        if let ocrResults = ocrResults {
            ForEach(ocrResults, id: \.uuid) { result in
                GeometryReader { geometry in
                    let boundingBox = NormalizedRect(normalizedRect: result.normalizedRect)
                    let rect = boundingBox.toImageCoordinates(geometry.size, origin: .upperLeft)
                    Rectangle()
                        .fill(isSelected ? .green : .accentColor)
                        .opacity(0.5)
                        .contentShape(Rectangle())
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                        .onTapGesture(count: 2) {
                            isSelected = true
                        }
                        .onTapGesture(count: 1) {
                            isSelected = false
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
        // Without this, nothing appears until ocrResults != nil,
        // but ocrResults == nil until something appears
        // TODO: there must be a better solution
        Rectangle()
            .frame(width: 0, height: 0)
            .onAppear {
                loadOCRResults(snapshot: snapshot)
            }
    }

    // TODO: save OCR data to daemon memory space
    func loadOCRResults(snapshot: Snapshot) {
        Task {
            do {
                var ocrData: String?

                if snapshot.ocrData == nil {
                    if let image = snapshot.image {
                        ocrData = try await performOCR(on: image)
                    }
                } else {
                    ocrData = snapshot.ocrData
                }

                if let jsonData = ocrData?.data(using: .utf8) {
                    let decoder = JSONDecoder()
                    let results = try decoder.decode([OCRResult].self, from: jsonData)
                    await MainActor.run {
                        ocrResults = results
                    }
                }
            } catch {
                log("OCR failed: \(error)")
            }
        }
    }
}
