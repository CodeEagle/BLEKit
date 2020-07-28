import XCTest
@testable import BLEKit

class BLEKitTests: XCTestCase {
    static var allTests = [
        ("testGeneralSimulator", testGeneralSimulator),
        ("testTimeout", testTimeout)
    ]
    
    private var box: BLEKit.PeripheralBox?
    override func setUp() {
        BLEKit.shared.peripheralStubPolicy = .enable([Simulators.generalSimuator])
    }

    override func tearDown() {
        BLEKit.shared.peripheralStubPolicy = .disable
    }

    func testGeneralSimulator() {
        _test(timeout: false)
    }

    func testTimeout() {
        _test(timeout: true)
    }
    
    private func _test(timeout: Bool) {
        print("--------\(Simulators.General.name) \(timeout ? "Timeout" : "") Test Start--------")
        asyncTest { e in
            Simulators.generalSimuator.delay = timeout ? 6 : 1
            BLEKit.shared.timeoutPolicy = .enable(DispatchTimeInterval.seconds(timeout ? 3 : 2))
            let filter: (BLEKit.PeripheralBox) -> Bool = { $0.peripheral.name == Simulators.General.name }
            let didFindOneHandler: (BLEKit.PeripheralBox) -> Void = { [weak self] box in
                timeout ? self?.doTimeoutTest(e: e, box: box) : self?.doTest(e: e, box: box)
                BLEKit.shared.stopScan()
            }
            BLEKit.shared.scan(filter: filter, didFindOne: didFindOneHandler)
        }
    }
}

extension BLEKitTests {
    private func doTimeoutTest(e: XCTestExpectation, box: BLEKit.PeripheralBox) {
        self.box = box
        box.connect { result in
            let group = DispatchGroup()

            group.enter()
            print("🚥 read battery")
            box.read(request: Simulators.General.Request.battery2, completion: { result in
                assert(result.util.error != nil)
                switch result {
                case let .failure(err):
                    switch err {
                    case let .timeout(policy, req):
                        assert(policy.timeout == BLEKit.shared.timeoutPolicy.timeout)
                        assert(req == Simulators.General.Request.battery2)
                        print("🚥 test read battery timeout success")

                    default: assertionFailure()
                    }
                default: assertionFailure()
                }
                group.leave()
            })

            group.enter()
            print("⏰ enter write")
            box.write(request: Simulators.General.Request.write, data: Data([1, 2, 3]), action: .withResponse { result in
                assert(result.util.error != nil)
                switch result {
                case let .failure(err):
                    switch err {
                    case let .timeout(policy, req):
                        assert(policy.timeout == BLEKit.shared.timeoutPolicy.timeout)
                        assert(req == Simulators.General.Request.write)
                        print("⏰ test write timeout success")

                    default: assertionFailure()
                    }
                default: assertionFailure()
                }
                group.leave()
            })
            group.notify(queue: DispatchQueue.main, execute: {
                box.disconnect()
                print("--------\(Simulators.General.name) Timeout Test Ended--------")
                e.fulfill()
            })
        }
    }

    private func doTest(e: XCTestExpectation, box: BLEKit.PeripheralBox) {
        self.box = box
        box.connect { result in
            assert(result.util.isSuccess, result.util.error!.localizedDescription)

            let group = DispatchGroup()

            group.enter()
            print("🍉 enter")
            box.read(request: Simulators.General.Request.battery, completion: { result in
                let d = result.util.value!
                let data = d!
                assert(data[0] == Simulators.General.battery)
                print("🍉 read 🔋:\(data[0])%")
                print("🍉 leave")
                group.leave()
            })

            group.enter()
            print("🍎 enter")
            box.write(request: Simulators.General.Request.write, data: Data([1, 2, 3]), action: .withResponse { result in
                let d = result.util.value!
                let data = d!
                let text = String(data: data, encoding: .ascii)!
                assert(text == Simulators.General.writeResponse)
                print("🍎 response: \(text)")
                print("🍎 leave")
                group.leave()
            })

            group.enter()
            print("🍐 enter")
            box.write(request: Simulators.General.Request.writeRequest, reponse: Simulators.General.Request.writeResponse, data: Data([4, 5, 6]), action: .withResponse { result in
                let d = result.util.value!
                let data = d!
                let text = String(data: data, encoding: .ascii)!
                assert(text == Simulators.General.writeResponse)
                print("🍐 write and reponse with another request: \(text)")
                print("🍐 leave")
                group.leave()
            })

            box.write(request: Simulators.General.Request.battery, data: Data([1]))

            group.enter()
            print("🚥 enter")
            var count = 1
            box.notify(request: Simulators.General.Request.battery, policy: .enable { result in
                let d = result.util.value!
                let data = d!
                assert(data[0] == Simulators.General.battery)
                print("🚥 receive 🔋:\(data[0])% notify \(count)")
                count += 1
                guard count == 4 else { return }
                print("🚥 leave")
                group.leave()
            })

            group.notify(queue: DispatchQueue.main, execute: {
                box.disconnect()
                print("--------\(Simulators.General.name) Test Ended--------")
                e.fulfill()
            })
        }
    }
}
