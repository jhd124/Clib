//
//  Item.swift
//  clib
//
//  Created by DP on 2024/5/19.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
