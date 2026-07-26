

import SwiftUI
struct A: View {
    @StateObject private var viewModel = ClipboardViewModel()
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Button("Scroll to Bottom") {
                    withAnimation {
                        proxy.scrollTo("1")
                    }
                }
                .id("0")
                
                List(viewModel.itemList.list) {item in
                    HStack {
                        if (item.content == "") {
                            EmptyView()
                        } else {
                            Text(item.content)
                                .id(item.id)
                                .padding()
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(8)
                            Button(action: {
                                writeToClipboard(item.content)
                            }) {
                                Text("Copy").padding(10)
                            }
                        }
                    }
                }.onChange(of: viewModel.itemList.list[0]) {
                    withAnimation {
                        proxy.scrollTo(viewModel.itemList.list.first?.id)
                    }
                }
                
                
                VStack(spacing: 0) {
                    ForEach(0..<100) { i in
                        color(fraction: Double(i) / 100)
                            .frame(height: 32)
                    }
                }
                
                
                Button("Top") {
                    withAnimation {
                        proxy.scrollTo("0")
                    }
                }
                .id("1")
            }
        }
    }
    
    func writeToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}


func color(fraction: Double) -> Color {
    Color(red: fraction, green: 1 - fraction, blue: 0.5)
}

#Preview {
    return A()
}
