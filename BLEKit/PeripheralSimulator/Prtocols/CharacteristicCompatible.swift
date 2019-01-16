import CoreBluetooth

public protocol CharacteristicCompatible: NSObjectProtocol {
    var mockService: ServiceCompatible { get }
    func addMockProperties(_ value: CBCharacteristicProperties)

    var uuid: CBUUID { get }
    var service: CBService { get }
    var properties: CBCharacteristicProperties { get }
    var value: Data? { get }
    var descriptors: [CBDescriptor]? { get }
    @available(iOS, introduced: 5.0, deprecated: 8.0)
    var isBroadcasted: Bool { get }
    var isNotifying: Bool { get }
}

extension CBCharacteristic: CharacteristicCompatible {
    public var mockService: ServiceCompatible { fatalError(BLEKit.forbidden) }
    public func addMockProperties(_ value: CBCharacteristicProperties) { }
}
