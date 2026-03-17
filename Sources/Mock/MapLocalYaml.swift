import Foundation
import Yams

/// Schema for importing a group of Map Local rules from a YAML file.
struct MapLocalYamlTemplate: Codable {
    let group: String
    let rules: [YamlRule]
    
    struct YamlRule: Codable {
        let name: String
        let method: String?
        let url: String
        let status: Int?
        let contentType: String?
        let body: String?
        let requestMatch: String?
        let file: String?
    }
    
    /// Parses a YAML string and converts it into native MapLocalRule objects
    static func parse(yamlString: String) throws -> [MapLocalRule] {
        // First try to parse generically to check for OpenAPI/Swagger
        if let genericDict = try Yams.load(yaml: yamlString) as? [String: Any],
           genericDict["openapi"] != nil || genericDict["swagger"] != nil {
            return parseOpenAPI(dict: genericDict)
        }
        
        // Fallback to ProxyMock's simple custom template
        let decoder = YAMLDecoder()
        let template = try decoder.decode(MapLocalYamlTemplate.self, from: yamlString)
        
        return template.rules.map { rule in
            var newRule = MapLocalRule()
            newRule.group = template.group
            newRule.name = rule.name
            newRule.httpMethod = rule.method ?? "*"
            newRule.urlPattern = rule.url
            newRule.statusCode = rule.status ?? 200
            newRule.contentType = rule.contentType ?? "application/json"
            
            if let f = rule.file, !f.isEmpty {
                newRule.source = .file
                newRule.localFilePath = f
            } else {
                newRule.source = .inline
                newRule.inlineBody = rule.body ?? ""
            }
            newRule.inlineRequestMatch = rule.requestMatch ?? ""
            return newRule
        }
    }
    
    private static func parseOpenAPI(dict: [String: Any]) -> [MapLocalRule] {
        var rules: [MapLocalRule] = []
        
        let info = dict["info"] as? [String: Any]
        let groupName = info?["title"] as? String ?? "OpenAPI Mocks"
        
        var serverUrl = ""
        if let servers = dict["servers"] as? [[String: Any]], let firstServer = servers.first, let url = firstServer["url"] as? String {
            serverUrl = url == "/" ? "" : url
        }
        
        guard let paths = dict["paths"] as? [String: Any] else {
            return []
        }
        
        for (path, pathItem) in paths {
            guard let methodsDict = pathItem as? [String: Any] else { continue }
            
            for (method, operation) in methodsDict {
                // Ignore standard OpenAPI keys under path item that aren't HTTP methods
                let validMethods = ["get", "post", "put", "delete", "patch", "options", "head", "trace"]
                let lowerMethod = method.lowercased()
                if !validMethods.contains(lowerMethod) { continue }
                
                guard let opDict = operation as? [String: Any] else { continue }
                
                var newRule = MapLocalRule()
                newRule.group = groupName
                newRule.httpMethod = method.uppercased()
                
                let summary = opDict["summary"] as? String
                let opId = opDict["operationId"] as? String
                newRule.name = summary ?? opId ?? "\(method.uppercased()) \(path)"
                
                // Construct URL pattern (e.g. */client-api/v1/something*)
                newRule.urlPattern = "*" + serverUrl + path + "*"
                
                // Try to find a successful response code
                var statusCode = 200
                if let responses = opDict["responses"] as? [String: Any] {
                    for (code, _) in responses {
                        if code.hasPrefix("2"), let intCode = Int(code) {
                            statusCode = intCode
                            break
                        }
                    }
                }
                newRule.statusCode = statusCode
                newRule.contentType = "application/json"
                newRule.source = .inline
                
                // We default to empty JSON object if we can't extract a mock body from the OpenAPI schema
                newRule.inlineBody = "{\n  \n}"
                
                rules.append(newRule)
            }
        }
        
        return rules
    }
}
