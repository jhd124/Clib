//
//  File.swift
//  clib
//
//  Created by DP on 2024/5/28.
//

import Foundation

struct ItemList {
    var list: [Item] = [Item(content: "", type: ItemType.text)]
    
    init(list: [Item] = []){
        self.list.append(contentsOf: list)
    }
    
    mutating func push(content: String, type: ItemType){
        self.list.insert(Item(content: content, type: type), at: 0)
    }
    
    func peek() -> Item {
        return self.list[0]
    }
}
