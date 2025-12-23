//
//  Item.swift
//  MacMultipeerIOS
//
//  Created by Lawrence Degoma on 10/2/25.
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
