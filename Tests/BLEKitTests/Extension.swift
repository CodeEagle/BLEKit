import XCTest

extension XCTestCase {
    func asyncTest(timeout: TimeInterval = 30, block: (XCTestExpectation) -> Void) {
        let expectation: XCTestExpectation = self.expectation(description: "❌:Timeout")
        block(expectation)
        waitForExpectations(timeout: timeout) { error in
            if let err = error {
                XCTFail("time out: \(err)")
            } else {
                XCTAssert(true, "success")
            }
        }
    }
}
