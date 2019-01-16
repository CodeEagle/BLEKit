import CoreBluetooth
extension BLEKit {
    public final class PeripheralDelegator: NSObject {
        public private(set) lazy var eventPipeline = Delegated<Event, Void>()
        public override init() { super.init() }
    }
}

// MARK: - Event

extension BLEKit.PeripheralDelegator {
    public typealias DidModifyServicesBox = (peripheral: PeripheralCompatible, invalidatedServices: [ServiceCompatible])
    public typealias DidUpdateRSSIBox = (peripheral: PeripheralCompatible, error: Error?)
    public typealias DidReadRSSIBox = (peripheral: PeripheralCompatible, RSSI: NSNumber, error: Error?)
    public typealias DidDiscoverServicesBox = DidUpdateRSSIBox
    public typealias DidDiscoverIncludedServicesBox = (peripheral: PeripheralCompatible, service: ServiceCompatible, error: Error?)
    public typealias DidDiscoverCharacteristicsBox = DidDiscoverIncludedServicesBox
    public typealias DidUpdateCharacteristicValueBox = (peripheral: PeripheralCompatible, characteristic: CharacteristicCompatible, error: Error?)
    public typealias DidWriteCharacteristicValueBox = DidUpdateCharacteristicValueBox
    public typealias DidUpdateCharacteristicNotificationStateBox = DidUpdateCharacteristicValueBox
    public typealias DidDiscoverCharacteristicDescriptorsBox = DidUpdateCharacteristicValueBox
    public typealias DidUpdateDescriptorValueBox = (peripheral: PeripheralCompatible, descriptor: CBDescriptor, error: Error?)
    public typealias DidWriteDescriptorValueBox = DidUpdateDescriptorValueBox
    @available(iOS 11.0, *)
    public typealias DidOpenChannelBox = (peripheral: PeripheralCompatible, channel: CBL2CAPChannel?, error: Error?)

    public enum Event {
        case didUpdateName(PeripheralCompatible)
        case didModifyServices(DidModifyServicesBox)
        case didUpdateRSSI(DidUpdateRSSIBox)
        case didReadRSSI(DidReadRSSIBox)
        case didDiscoverServices(DidDiscoverServicesBox)
        case didDiscoverIncludedServices(DidDiscoverIncludedServicesBox)
        case didDiscoverCharacteristics(DidDiscoverCharacteristicsBox)
        case didUpdateCharacteristicValue(DidUpdateCharacteristicValueBox)
        case didWriteCharacteristicValue(DidWriteCharacteristicValueBox)
        case didUpdateCharacteristicNotificationState(DidUpdateCharacteristicNotificationStateBox)
        case didDiscoverCharacteristicDescriptors(DidDiscoverCharacteristicDescriptorsBox)
        case didUpdateDescriptorValue(DidUpdateDescriptorValueBox)
        case didWriteDescriptorValue(DidWriteDescriptorValueBox)
        case isReadyToSendWriteWithoutResponse(PeripheralCompatible)
        @available(iOS 11.0, *)
        case didOpenChannel(DidOpenChannelBox)
    }
}

// MARK: - CBPeripheralDelegate

extension BLEKit.PeripheralDelegator: CBPeripheralDelegate {
    public func peripheralDidUpdateName(_ peripheral: CBPeripheral) { eventPipeline.call(.didUpdateName(peripheral)) }

    public func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) { eventPipeline.call(.didModifyServices((peripheral, invalidatedServices))) }

    public func peripheralDidUpdateRSSI(_ peripheral: CBPeripheral, error: Error?) { eventPipeline.call(.didUpdateRSSI((peripheral, error))) }

    public func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) { eventPipeline.call(.didReadRSSI((peripheral, RSSI, error))) }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) { eventPipeline.call(.didDiscoverServices((peripheral, error))) }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverIncludedServicesFor service: CBService, error: Error?) { eventPipeline.call(.didDiscoverIncludedServices((peripheral, service, error))) }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) { eventPipeline.call(.didDiscoverCharacteristics((peripheral, service, error))) }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) { eventPipeline.call(.didUpdateCharacteristicValue((peripheral, characteristic, error))) }

    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) { eventPipeline.call(.didWriteCharacteristicValue((peripheral, characteristic, error))) }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) { eventPipeline.call(.didUpdateCharacteristicNotificationState((peripheral, characteristic, error))) }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: Error?) { eventPipeline.call(.didDiscoverCharacteristicDescriptors((peripheral, characteristic, error))) }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor descriptor: CBDescriptor, error: Error?) { eventPipeline.call(.didUpdateDescriptorValue((peripheral, descriptor, error))) }

    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor descriptor: CBDescriptor, error: Error?) { eventPipeline.call(.didWriteDescriptorValue((peripheral, descriptor, error))) }

    public func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) { eventPipeline.call(.isReadyToSendWriteWithoutResponse(peripheral)) }

    @available(iOS 11.0, *)
    public func peripheral(_ peripheral: CBPeripheral, didOpen channel: CBL2CAPChannel?, error: Error?) { eventPipeline.call(.didOpenChannel((peripheral, channel, error))) }
}
