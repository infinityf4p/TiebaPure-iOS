import XCTest
@testable import TiebaPure

final class TiebaFormSignerTests: XCTestCase {
    func testFormSignerMatchesTiebaLiteSortAndSignRule() {
        let signature = TiebaFormSigner.sign(
            fields: [
                "b": "2",
                "a": "1"
            ],
            secret: "tiebaclient!!!"
        )

        XCTAssertEqual(signature, "42961B9881C2D7CB297E9498F9767789")
    }
}
