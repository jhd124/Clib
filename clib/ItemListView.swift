import SwiftUI

struct ItemListView: View {
    @StateObject private var viewModel = ClipboardViewModel()
    @EnvironmentObject private var appDelegate: AppDelegate
    @State private var selectedItemID: Item.ID?
    @FocusState private var isListFocused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Spacer()
                    Button {
                        appDelegate.togglePin()
                    } label: {
                        Image(systemName: appDelegate.isPinned ? "pin.fill" : "pin")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(appDelegate.isPinned ? Color.accentColor : .secondary)
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(appDelegate.isPinned ? "取消置顶" : "始终置顶")
                    .onHover { isHovering in
                        if isHovering {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                }
                .padding(.horizontal, 6)
                .frame(height: 22)
                .background(Color.clear)

                Divider()

                List(selectableItems, selection: $selectedItemID) { item in
                    Text(item.content)
                        .lineLimit(3)
                        .padding(.vertical, 8)
                        .tag(item.id)
                        .id(item.id)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            paste(item)
                        }
                        .onTapGesture {
                            selectedItemID = item.id
                        }
                        .listRowBackground(Color.clear)
                }
                .scrollContentBackground(.hidden)
                .focused($isListFocused)
                .onKeyPress(.upArrow) {
                    moveSelection(by: -1, proxy: proxy)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    moveSelection(by: 1, proxy: proxy)
                    return .handled
                }
                .onKeyPress(.return) {
                    pasteSelectedItem()
                    return .handled
                }
                .onKeyPress(.escape) {
                    NSApp.hide(nil)
                    return .handled
                }
                .onAppear {
                    selectFirstItem()
                }
                .onReceive(NotificationCenter.default.publisher(for: .clipboardPickerDidOpen)) { _ in
                    selectFirstItem()
                }
                .onChange(of: viewModel.itemList.list) {
                    guard let firstItem = selectableItems.first else { return }
                    if selectedItemID == nil {
                        selectedItemID = firstItem.id
                    }
                    withAnimation {
                        proxy.scrollTo(firstItem.id, anchor: .top)
                    }
                }
            }
            .background {
                windowBackground
            }
        }
    }

    @ViewBuilder
    private var windowBackground: some View {
        if #available(macOS 26.0, *) {
            Color.clear
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 10))
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
        }
    }

    private var selectableItems: [Item] {
        viewModel.itemList.list.filter { !$0.content.isEmpty }
    }

    private func selectFirstItem() {
        selectedItemID = selectableItems.first?.id
        DispatchQueue.main.async {
            isListFocused = true
        }
    }

    private func moveSelection(by offset: Int, proxy: ScrollViewProxy) {
        guard !selectableItems.isEmpty else { return }
        let currentIndex = selectedItemID.flatMap { id in
            selectableItems.firstIndex { $0.id == id }
        } ?? 0
        let newIndex = min(max(currentIndex + offset, 0), selectableItems.count - 1)
        let item = selectableItems[newIndex]
        selectedItemID = item.id
        withAnimation {
            proxy.scrollTo(item.id, anchor: .center)
        }
    }

    private func pasteSelectedItem() {
        guard let selectedItemID,
              let item = selectableItems.first(where: { $0.id == selectedItemID }) else {
            return
        }
        paste(item)
    }

    private func paste(_ item: Item) {
        appDelegate.pasteIntoPreviouslyActiveApplication(item.content)
    }
}
