//
//  BLE+Extensions.swift
//  BLEKit
//
//  Created by Lincoln on 2019/1/16.
//  Copyright © 2019 SelfStudio. All rights reserved.
//

import Foundation

extension Dictionary {
    public func flyMap<T: Hashable, U>(transform: (Key, Value) -> (T, U)) -> [T: U] {
        var result: [T: U] = [:]
        for (key, value) in self {
            let (transformedKey, transformedValue) = transform(key, value)
            result[transformedKey] = transformedValue
        }
        return result
    }
}

extension Notification.Name {
    /// userInfo 结构为 ["state" : bleState]
    public static let BluetoothStateChanged: Notification.Name = .init("Notification.Name.BluetoothStateChanged")
}
