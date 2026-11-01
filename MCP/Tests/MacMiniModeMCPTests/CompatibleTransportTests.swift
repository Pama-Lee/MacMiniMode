import Foundation
import XCTest
@testable import MacMiniModeMCP

final class CompatibleTransportTests: XCTestCase {
    func testOnlyUnusedExperimentalCapabilitiesAreRemoved() throws {
        let request: [String: Any] = [
            "jsonrpc": "2.0", "id": "test-id", "method": "initialize",
            "params": ["protocolVersion": "2025-11-25",
                       "clientInfo": ["name": "Codex", "version": "test"],
                       "capabilities": ["roots": ["listChanged": true],
                                        "experimental": ["objects": ["enabled": true], "array": [1, 2]]]]
        ]
        let input = try JSONSerialization.data(withJSONObject: request)
        let output = CompatibleTransport.normalize(input)
        var expected = request
        var params = request["params"] as! [String: Any]
        params["capabilities"] = ["roots": ["listChanged": true]]
        expected["params"] = params
        let decoded = try JSONSerialization.jsonObject(with: output) as! NSDictionary
        XCTAssertEqual(decoded, expected as NSDictionary)
    }

    func testOtherMessagesAndInvalidInputsRemainUnchanged() {
        for text in [
            #"{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"capabilities":{"experimental":{"x":true}}}}"#,
            #"{"method":"initialize","params":{"capabilities":{}}}"#,
            #"{"method":"initialize","params":{"capabilities":{"experimental":42}}}"#,
            "not json", "[]"
        ] {
            let data = Data(text.utf8)
            XCTAssertEqual(CompatibleTransport.normalize(data), data)
        }
    }
}
