//
//  File.swift
//  clib
//
//  Created by DP on 2024/5/28.
//

import Foundation

struct ItemList {
    var list: [Item]
    
    init(list: [Item] = []) {
        self.list = list
    }
    
    @discardableResult
    mutating func push(content: String, type: ItemType) -> Item {
        let item = Item(content: content, type: type)
        list.insert(item, at: 0)
        return item
    }
    
    func peek() -> Item? {
        list.first
    }
}
