import XCTest
@testable import BLEKit

class GeneralTests: XCTestCase {

    override func setUp() {
        BLEKit.shared.peripheralStubPolicy = .enable([Simulators.generalSimuator])
    }

    override func tearDown() {
        BLEKit.shared.peripheralStubPolicy = .disable
    }

    func testGeneralSimulator() {
        print("--------\(Simulators.General.name) Test Start--------")
        asyncTest { (e) in
            BLEKit.shared.scan(nameFilter: { $0 == Simulators.General.name },
                               didFindOne: {[weak self] (box) in
                                self?.doTest(e: e, box: box)
                                BLEKit.shared.stopScan()
                               },
                               completion: { _, _ in})
        }
    }

}

extension GeneralTests {
    private func doTest(e: XCTestExpectation, box: BLEKit.PeripheralBox) {
        box.connect { (_, _, error) in
            assert(error == nil, error!.localizedDescription)
            print("connect success")

            let group = DispatchGroup()

            group.enter()
            print("group enter read battery")
            box.read(request: Simulators.General.Request.battery, completion: { (result) in
                let d = result.value!
                let data = d!
                assert(data[0] == Simulators.General.battery)
                print("Read 🔋:\(data[0])%")
                print("group leave read battery")
                group.leave()
            })

            group.enter()
            print("group enter write")
            box.write(request: Simulators.General.Request.write, data: Data([1, 2, 3]), action: .withResponse { (result) in
                let d = result.value!
                let data = d!
                let text = String(data: data, encoding: .ascii)!
                assert(text == Simulators.General.writeResponse)
                print("write response: \(text)")
                print("group leave write")
                group.leave()
            })

            box.write(request: Simulators.General.Request.battery, data: Data([1]))

            group.enter()
            print("group enter notify")
            var count = 0
            box.notify(request: Simulators.General.Request.battery, policy: .enable { (result) in
                let d = result.value!
                let data = d!
                assert(data[0] == Simulators.General.battery)
                print("Notify 🔋:\(data[0])%")
                count += 1
                guard count == 3 else { return }
                print("group leave notify")
                group.leave()
            })

            group.notify(queue: DispatchQueue.main, execute: {
                print("--------\(Simulators.General.name) Test Ended--------")
                e.fulfill()
            })
        }
    }
}
