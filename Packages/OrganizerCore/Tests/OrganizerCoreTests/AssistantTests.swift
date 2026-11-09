import Foundation
import Testing
@testable import OrganizerCore

@Suite("Claude-Stream")
struct AssistantTests {
    func events(_ lines: [String]) throws -> [JSONValue] {
        try lines.map { try JSONValue.parse($0) }
    }

    @Test func accumulatesTextThinkingAndToolUse() throws {
        var accumulator = MessageAccumulator()
        for event in try events([
            #"{"type":"message_start","message":{"id":"msg_1","model":"claude-opus-5-5"}}"#,
            #"{"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"sig123"}}"#,
            #"{"type":"content_block_stop","index":0}"#,
            #"{"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}"#,
            #"{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Ich lege "}}"#,
            #"{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"das an."}}"#,
            #"{"type":"content_block_stop","index":1}"#,
            #"{"type":"content_block_start","index":2,"content_block":{"type":"tool_use","id":"toolu_1","name":"create_task","input":{}}}"#,
            #"{"type":"content_block_delta","index":2,"delta":{"type":"input_json_delta","partial_json":"{\"title\": \"Les"}}"#,
            #"{"type":"content_block_delta","index":2,"delta":{"type":"input_json_delta","partial_json":"en\", \"due\": \"2026-11-13\"}"}}"#,
            #"{"type":"content_block_stop","index":2}"#,
            #"{"type":"message_delta","delta":{"stop_reason":"tool_use"},"usage":{"output_tokens":42}}"#,
            #"{"type":"message_stop"}"#,
        ]) {
            try accumulator.apply(event)
        }
        #expect(accumulator.model == "claude-opus-5-5")
        #expect(accumulator.stopReason == "tool_use")
        #expect(accumulator.text == "Ich lege das an.")
        #expect(accumulator.blocks[0] == ["type": "thinking", "thinking": "", "signature": "sig123"])
        let tool = try #require(accumulator.toolUses.first)
        #expect(tool.name == "create_task")
        #expect(tool.input == ["title": "Lesen", "due": "2026-11-13"])
        #expect(accumulator.invalidToolInputs.isEmpty)
        #expect(accumulator.assistantMessage["content"]?.arrayValue?.count == 3)
    }

    @Test func keepsUnknownBlocksAndFlagsBrokenToolInput() throws {
        var accumulator = MessageAccumulator()
        for event in try events([
            #"{"type":"content_block_start","index":0,"content_block":{"type":"fallback","from":{"model":"a"},"to":{"model":"b"}}}"#,
            #"{"type":"content_block_stop","index":0}"#,
            #"{"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_2","name":"x","input":{}}}"#,
            #"{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"title\": \"abgeschnit"}}"#,
            #"{"type":"content_block_stop","index":1}"#,
        ]) {
            try accumulator.apply(event)
        }
        #expect(accumulator.blocks[0]["type"] == "fallback")
        #expect(accumulator.invalidToolInputs["toolu_2"] == #"{"title": "abgeschnit"#)
    }

    @Test func streamErrorThrows() throws {
        var accumulator = MessageAccumulator()
        let event = try JSONValue.parse(#"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#)
        #expect(throws: MessageAccumulator.StreamError.self) { try accumulator.apply(event) }
    }

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
