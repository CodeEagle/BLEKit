import BLEKit
import Foundation
final class Simulators {
    struct General {
        static let name = "📱 BLESimulator"
        static let writeResponse = "hey there, I'm here"
        static let battery: UInt8 = 42
        struct Request {
            static let firmware = BLEKit.Request(characteristicID: "2A26", serviceID: "180A")
            static let battery = BLEKit.Request(characteristicID: "2A19", serviceID: "180F")
            static let battery2 = BLEKit.Request(characteristicID: "2A19", serviceID: "180E")
            static let write = BLEKit.Request(characteristicID: "2A20", serviceID: "190F")
            static let writeRequest = BLEKit.Request(characteristicID: "2A20", serviceID: "191F")
            static let writeResponse = BLEKit.Request(characteristicID: "2A20", serviceID: "192F")
        }
    }
}

extension Simulators {
    static let generalSimuator: BLEKit.PeripheralSimulator = {
        let simulator = BLEKit.PeripheralSimulator(identifier: UUID())
        simulator.name = Simulators.General.name
        simulator.mockAdvertisementData = ["kCBAdvDataIsConnectable": 1]
        simulator.mockRSSI = -43

        simulator.registerNotify(stub: { (char, trigger) -> (CharacteristicCompatible, Error?) in
            let cc = BLEKit.MockCharacteristic(characteristic: char)
            cc.value = Data([Simulators.General.battery])

            func looper(block: @escaping () -> Void) {
                block()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    looper(block: block)
                }
            }
            looper(block: { trigger(cc, nil) })
            return (cc, nil)
        }, for: General.Request.battery, properties: .notify)

        simulator.registerRead(stub: { (char) -> (CharacteristicCompatible, Error?) in
            let mockChar = BLEKit.MockCharacteristic(characteristic: char)
            mockChar.value = "1.3".data(using: .ascii)
            return (mockChar, nil)
        }, for: General.Request.firmware, properties: .read)

        simulator.registerRead(stub: { (char) -> (CharacteristicCompatible, Error?) in
            let mockChar = BLEKit.MockCharacteristic(characteristic: char)
            mockChar.value = Data([Simulators.General.battery])
            return (mockChar, nil)
        }, for: General.Request.battery, properties: .read)
        
        simulator.registerRead(stub: { (char) -> (CharacteristicCompatible, Error?) in
            let mockChar = BLEKit.MockCharacteristic(characteristic: char)
            mockChar.value = Data([Simulators.General.battery])
            return (mockChar, nil)
        }, for: General.Request.battery2, properties: .read)

        simulator.registerWrite(stub: { (char, data, type) -> (CharacteristicCompatible, Error?) in
            let mockChar = BLEKit.MockCharacteristic(characteristic: char)
            print("\(Simulators.General.name): writeWithoutResponse receive write data: \(data as NSData), write with response: \(type == .withResponse)")
            return (mockChar, nil)
        }, for: General.Request.battery, properties: .writeWithoutResponse)

        simulator.registerWrite(stub: { (char, data, type) -> (CharacteristicCompatible, Error?) in
            let mockChar = BLEKit.MockCharacteristic(characteristic: char)
            print("\(Simulators.General.name): receive write data: \(data as NSData), write with response: \(type == .withResponse)")
            mockChar.value = Simulators.General.writeResponse.data(using: .ascii)!
            return (mockChar, nil)
        }, for: General.Request.writeRequest, response: General.Request.writeResponse, properties: .write)

        simulator.registerWrite(stub: { (char, data, type) -> (CharacteristicCompatible, Error?) in
            let mockChar = BLEKit.MockCharacteristic(characteristic: char)
            print("\(Simulators.General.name): receive write data: \(data as NSData), write with response: \(type == .withResponse)")
            mockChar.value = Simulators.General.writeResponse.data(using: .ascii)!
            return (mockChar, nil)
        }, for: General.Request.write, properties: .write)

        return simulator
    }()
}
