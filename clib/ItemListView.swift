//
//  ItemListView.swift
//  clib
//
//  Created by DP on 2024/5/26.
//

import SwiftUI

struct ItemListView: View {
    @StateObject private var viewModel = ClipboardViewModel()

    var body: some View {
        List(viewModel.itemList.list) {item in
            HStack {
                if (item.content == "") {
                    EmptyView()
                } else {
                    Text(item.content)
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(8)
                }
            }
        }
    }
}

#Preview {
    return ItemListView()
}
