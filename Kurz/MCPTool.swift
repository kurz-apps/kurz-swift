import FoundationModels
import SwiftUI

/// Exposes one MCP tool to the on-device model. The schema comes from the server's `inputSchema` at runtime.
struct MCPTool: Tool {
    let name: String
    let description: String
    let parameters: GenerationSchema
    let mcp: MCP

    func call(arguments: GeneratedContent) async throws -> String {
        try await mcp.callTool(name, arguments: arguments.jsonString)
    }
}

extension DynamicGenerationSchema {
    /// Maps the subset of JSON Schema that MCP tools use in practice.
    /// ponytail: no $ref/anyOf/oneOf; unknown types degrade to string. Extend when a real tool needs it.
    init(json s: [String: Any], name: String) {
        let type = (s["type"] as? String) ?? (s["type"] as? [String])?.first { $0 != "null" }
        switch type {
        case "object":
            let required = s["required"] as? [String] ?? []
            let props = (s["properties"] as? [String: [String: Any]] ?? [:]).map { key, value in
                Property(
                    name: key, description: value["description"] as? String,
                    schema: DynamicGenerationSchema(json: value, name: "\(name)_\(key)"), isOptional: !required.contains(key))
            }
            self.init(name: name, description: s["description"] as? String, properties: props)
        case "array":
            self.init(arrayOf: DynamicGenerationSchema(json: s["items"] as? [String: Any] ?? [:], name: "\(name)_item"))
        case "integer": self.init(type: Int.self)
        case "number": self.init(type: Double.self)
        case "boolean": self.init(type: Bool.self)
        default:
            if let choices = s["enum"] as? [String] {
                self.init(name: name, description: s["description"] as? String, anyOf: choices)
            } else {
                self.init(type: String.self)
            }
        }
    }
}

