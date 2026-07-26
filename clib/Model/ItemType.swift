//
//  ItemType.swift
//  clib
//
//  Created by DP on 2024/5/26.
//

import Foundation

enum ItemType: String, Identifiable, Codable {
    case text
    case url
    case image
    case video
    case audio
    case code
    
    var id: String {
        switch self {
            case .text:
                "text"
            case .url:
                "url"
            case .image:
                "image"
            case .video:
                "url"
            case .audio:
                "audio"
            case .code:
                "code"
        }
    }
    
}
