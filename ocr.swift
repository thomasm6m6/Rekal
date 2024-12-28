import Foundation
import VisionKit
import AppKit

@available(macOS 13.0, *)
func performOCR(on imagePath: String) async {
    // Validate the image file path
    let imageURL = URL(fileURLWithPath: imagePath)
    guard FileManager.default.fileExists(atPath: imagePath) else {
        print("Error: File not found at \(imagePath)")
        return
    }
    
    // Load the image
    guard let image = NSImage(contentsOf: imageURL) else {
        print("Error: Unable to load the image.")
        return
    }
    
    // Create an ImageAnalyzer object
    let analyzer = ImageAnalyzer()
    let configuration = ImageAnalyzer.Configuration([.text])
    
    // Perform OCR analysis
    let analysis = try? await analyzer.analyze(image, orientation: .right, configuration: configuration)
    print(analysis!.transcript)
}

// Ensure an argument is provided
guard CommandLine.arguments.count > 1 else {
    print("Error: No image path provided.")
    exit(1)
}

let imagePath = CommandLine.arguments[1]
await performOCR(on: imagePath)
