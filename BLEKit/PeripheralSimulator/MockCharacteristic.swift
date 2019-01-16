import CoreBluetooth

extension BLEKit.PeripheralSimulator {
    public final class MockCharacteristic: NSObject, CharacteristicCompatible {
        public private(set) unowned var mockService: ServiceCompatible

        public private(set) var uuid: CBUUID = CBUUID(nsuuid: UUID())

        public unowned var service: CBService { fatalError(BLEKit.forbidden) }

        public private(set) var properties: CBCharacteristicProperties

        public var value: Data?

        public private(set) var descriptors: [CBDescriptor]?

        public private(set) var isBroadcasted: Bool = false

        public private(set) var isNotifying: Bool = false

        public init(id: String, service: ServiceCompatible, properties value: CBCharacteristicProperties) {
            mockService = service
            properties = value
            uuid = CBUUID(string: id)
            super.init()
        }

        public func addMockProperties(_ value: CBCharacteristicProperties) {
            properties.insert(value)
        }

        public init(characteristic: CharacteristicCompatible) {
            mockService = characteristic.mockService
            properties = characteristic.properties
            super.init()
            uuid = characteristic.uuid
        }
    }
}
