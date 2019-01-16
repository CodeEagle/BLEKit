import CoreBluetooth

public typealias CBCentralManagerState = CoreBluetooth.CBCentralManagerState

extension BLEKit {
    public typealias ActionResult = PeripheralAction.ActionResult
    public typealias Request = PeripheralAction.Request
    public typealias ServiceID = PeripheralAction.ServiceID
    public typealias CharacteristicID = PeripheralAction.CharacteristicID
    public typealias Action = PeripheralAction.Action
    public typealias NotifyStatus = PeripheralAction.Action.NotifyStatus
    public typealias MockCharacteristic = PeripheralSimulator.MockCharacteristic
    public typealias MockService = PeripheralSimulator.MockService
}

extension BLEKit.PeripheralBox {
    public typealias PeripheralAction = BLEKit.PeripheralAction
    public typealias ActionResult = PeripheralAction.ActionResult
    public typealias Request = PeripheralAction.Request
    public typealias Action = PeripheralAction.Action
    public typealias NotifyStatus = PeripheralAction.Action.NotifyStatus
    public typealias Write = PeripheralAction.Action.Write
    public typealias Result = BLEKit.Result
    public typealias ServiceID = PeripheralAction.ServiceID
    public typealias CharacteristicID = PeripheralAction.CharacteristicID
    public typealias DidWriteCharacteristicValueBox = BLEKit.PeripheralDelegator.DidWriteCharacteristicValueBox
}

extension BLEKit.PeripheralSimulator {
    public typealias PeripheralDelegator = BLEKit.PeripheralDelegator
    public typealias PeripheralAction = BLEKit.PeripheralAction
    public typealias ActionResult = PeripheralAction.ActionResult
    public typealias Request = PeripheralAction.Request
    public typealias Action = PeripheralAction.Action
    public typealias NotifyStatus = PeripheralAction.Action.NotifyStatus

    public typealias ReadStub = (CharacteristicCompatible) -> (CharacteristicCompatible, Swift.Error?)
    public typealias WriteStub = (CharacteristicCompatible, Data, CBCharacteristicWriteType) -> (CharacteristicCompatible, Swift.Error?)
    public typealias NotifyStub = (CharacteristicCompatible, @escaping (CharacteristicCompatible, Swift.Error?) -> Void) -> (CharacteristicCompatible, Swift.Error?)
}
