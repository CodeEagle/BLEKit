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
    /// userInfo 结构为 ["event" : FlyBLEKit.CentralManagerDelegator.Event]
    public static let centralManagerDelegatorEvent: Notification.Name = .init("Notification.Name.CentralManagerDelegatorEvent")
    /// userInfo 结构为 ["event" : FlyBLEKit.PeripheralDelegator.Event]
    public static let peripheralDelegatorEvent: Notification.Name = .init("Notification.Name.PeripheralDelegatorEvent")
}
