import SwiftUI

struct SettingsView: View {
    var body: some View {
        VStack {
            Text("Blocked apps")

            EditList()

            Text("Blocked URLs")

            EditList()

            Button("Unregister launch agent") {
                _ = LaunchManager.unregisterLaunchAgent()
            }
        }
        .padding()
    }
}

struct Element: Identifiable, Hashable {
    var name: String
    var isOn = false
    var id: Int
}

struct EditList: View {
    @State var selectedItem: Element?
    @State var items = [
        Element(name: "foo", id: 0),
        Element(name: "bar", id: 1),
        Element(name: "baz", id: 2),
        Element(name: "a", id: 3),
        Element(name: "b", id: 4),
        Element(name: "c", id: 5),
        Element(name: "d", id: 6),
        Element(name: "e", id: 7),
        Element(name: "f", id: 8),
        Element(name: "g", id: 9),
        Element(name: "h", id: 10),
        Element(name: "i", id: 11),
        Element(name: "j", id: 12),
        Element(name: "k", id: 13),
        Element(name: "l", id: 14),
        Element(name: "m", id: 16),
        Element(name: "n", id: 17),
        Element(name: "o", id: 18),
        Element(name: "p", id: 19),
        Element(name: "q", id: 20)
    ]

    var body: some View {
        VStack {
            List(selection: $selectedItem) {
                ForEach(items) { item in
                    Text(item.name)
                }
            }
            .padding(.bottom, 0)
            .border(SeparatorShapeStyle())
            .frame(maxWidth: 500, maxHeight: 200)
            .overlay {
                VStack {
                    Spacer()

                    Rectangle()
                        .fill(Color(red: 28/256, green: 29/256, blue: 31/256))
                        .opacity(1)
                        .border(Color(red: 50/256, green: 51/256, blue: 54/256))
                        .frame(height: 40)
                        .overlay {
                            VStack {
                                HStack {
                                    Button {
                                        //
                                    } label: {
                                        Image(systemName: "plus")
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        //
                                    } label: {
                                        Image(systemName: "minus")
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(selectedItem == nil)

                                    Spacer()
                                }
                                .padding()
                                .frame(height: 12.5)
                            }
                        }
                }
            }
        }
//        List(
//            $array,
//            editActions: [.delete, .move],
//            selection: $selectedElement
//        ) { $element in
//            HStack {
//                Text(element.name)
//                Toggle("On", isOn: $element.isOn)
//            }
//        }
    }
}
