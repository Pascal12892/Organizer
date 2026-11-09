import Foundation
import Testing
@testable import OrganizerCore

@Suite("JSON und Eingaben")
struct JSONTests {
    @Test func validatesToolInput() {
        let schema: JSONValue = [
            "type": "object",
            "properties": [
                "title": ["type": "string"],
                "priority": ["type": "string", "enum": ["high", "low"]],
                "all_day": ["type": "boolean"],
            ],
            "required": ["title"],
        ]
        #expect(ToolInputValidator.validate(["title": "A", "priority": "high"], schema: schema) == nil)
        #expect(ToolInputValidator.validate(["priority": "high"], schema: schema) != nil)
        #expect(ToolInputValidator.validate(["title": "  "], schema: schema) != nil)
        #expect(ToolInputValidator.validate(["title": "A", "priority": "mittel"], schema: schema) != nil)
        #expect(ToolInputValidator.validate(["title": "A", "all_day": "ja"], schema: schema) != nil)
        #expect(ToolInputValidator.validate(["title": "A", "extra": 1], schema: schema) != nil)
    }

    @Test func encodesDeterministically() throws {
        let value: JSONValue = ["b": 1, "a": ["x": true, "c": .number(2.5)], "max_tokens": 64000]
        #expect(value.jsonString == #"{"a":{"c":2.5,"x":true},"b":1,"max_tokens":64000}"#)
        #expect(try JSONValue.parse(value.jsonString) == value)
    }
}
