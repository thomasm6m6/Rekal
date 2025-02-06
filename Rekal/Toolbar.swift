import SwiftUI

struct Toolbar: View {
    @StateObject var imageModel: ImageModel
    @State var isInfoShowing = false

    @FocusState var isSearchFocused: Bool

    var body: some View {
        NavView(imageModel: imageModel)

        Spacer()

        SearchBar(imageModel: imageModel)

        Spacer()

        Button("Delete", systemImage: "trash") {
        }
        .disabled(imageModel.snapshots.isEmpty)

        InfoButton(imageModel: imageModel)
    }
}

struct NavView: View {
    @StateObject var imageModel: ImageModel
    @State var textIndex = "0"
    @State var isEnabled = false

    var body: some View {
        Button("Previous", systemImage: "chevron.left", action: imageModel.previousImage)
            .disabled(imageModel.snapshots.isEmpty || imageModel.atFirstImage)

        Button("Next", systemImage: "chevron.right", action: imageModel.nextImage)
            .disabled(imageModel.snapshots.isEmpty || imageModel.atLastImage)

//        let count = imageModel.snapshots.count
        let count = imageModel.snapshotCount
        let updateTextIndex = {
            textIndex = String(count == 0 ? 0 : imageModel.totalIndex + 1)
        }

        // TODO: alignment is wacky. Need to fix:
        // - width of textfield
        // - maybe leading padding of hstack
        // - maybe space between each element inside hstack
        // - truncation of last text element
        // - maybe vertical alignment of text relative to arrows
        HStack {
            TextField("", text: $textIndex)
//                .disabled(count == 0)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.plain)
                .lineLimit(1)
                .allowsHitTesting(isEnabled)
                .onAppear(perform: updateTextIndex)
                .onChange(of: imageModel.index, updateTextIndex)
                .onChange(of: count) {
                    updateTextIndex()
                    isEnabled = count > 0
                }
                .onSubmit {
                    if let number = Int(textIndex), number > 0 && number <= count {
                        imageModel.index = number - 1
//                        imageModel.setIndex(number - 1)
                    }
                    updateTextIndex()
                }
                .onKeyPress(.upArrow) {
                    if let number = Int(textIndex), number + 1 <= count {
                        imageModel.nextImage()
//                        imageModel.setIndex(number)
                        updateTextIndex()
                    }
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    if let number = Int(textIndex), number - 1 > 0 {
                        imageModel.previousImage()
//                        imageModel.setIndex(number - 2)
                        updateTextIndex()
                    }
                    return .handled
                }

            Text("/")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            Text(String(count))
                .font(.system(.body, design: .monospaced))
                .multilineTextAlignment(.leading)
                .lineLimit(1)
                .foregroundColor(.secondary)
                .frame(width: 40)

            Spacer()
        }
    }
}

struct SearchBar: View {
    @State var isShowingPopover = false
    @AppStorage("fullText") var fullText = false
    @State var searchText = ""
    @StateObject var imageModel: ImageModel

    var body: some View {
        // FIXME: doesn't appear in overflow menu
        // FIXME: not centered
        // FIXME: styling is hacky
        // TODO: make search box stand out somehow (rgb(30,30,30) background)
        TextField("Search...", text: $searchText)
            .textFieldStyle(.roundedBorder)
            .frame(width: 300)
            .onSubmit {
                let query = Query(
                    text: searchText,
                    options: QueryOptions(fullText: fullText)
                )
                imageModel.loadImages(query: query)
            }

        Button("Search options", systemImage: "slider.horizontal.3") {
            isShowingPopover = true
        }
        .popover(isPresented: $isShowingPopover, arrowEdge: .bottom) {
            Toggle(isOn: $fullText) {
                Text("Full-text search")
            }
            .padding()
        }
    }
}

// TODO: include info about e.g. the video file containing the image, if applicable
struct InfoButton: View {
    @StateObject var imageModel: ImageModel
    @State private var isInfoShowing = false

    var body: some View {
        Button("Info", systemImage: "info.circle") {
            isInfoShowing = true
        }
        .disabled(imageModel.snapshots.isEmpty)
        .popover(isPresented: $isInfoShowing, arrowEdge: .bottom) {
            let snapshot = imageModel.snapshots[imageModel.index]
            let info = snapshot.info

            // TODO: multiline text where needed (e.g. window name)
            Grid(alignment: .leading) {
                GridRow {
                    Text("Time")

                    let date = Date(timeIntervalSince1970: TimeInterval(snapshot.timestamp))
                    let format = Date.FormatStyle(date: .abbreviated, time: .shortened)
                        .attributedStyle
                    Text(date, format: format)
                        .textSelection(.enabled)
                }

                if let windowName = info.windowName {
                    GridRow {
                        Text("Window name")

                        Text(windowName)
                            .textSelection(.enabled)
//                                .lineLimit(3)
                    }
                }

                if let appName = info.appName {
                    GridRow {
                        Text("App name")

                        Text(appName)
                            .textSelection(.enabled)
                    }
                }

                if let appId = info.appId {
                    GridRow {
                        Text("App ID")

                        Text(appId)
                            .textSelection(.enabled)
                    }
                }

                if let url = info.url {
                    GridRow {
                        Text("URL")

                        Text(url)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding()
            .frame(maxWidth: 400)
        }
    }
}
