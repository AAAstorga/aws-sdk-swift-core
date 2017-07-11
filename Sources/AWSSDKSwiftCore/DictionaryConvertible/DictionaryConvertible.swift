//
//  DictionaryConvertible.swift
//  AWSSDKSwift
//
//  Created by Yuki Takei on 2017/03/29.
//
//

import Foundation

func unwrap(any: Any) -> Any? {
    let mi = Mirror(reflecting: any)
    if mi.displayStyle != .optional {
        return any
    }
    if mi.children.count == 0 { return nil }
    let (_, some) = mi.children.first!
    return some
}

public enum InitializableError: Error {
    case missingRequiredParam(String)
    case convertingError
}

public protocol ParsingHintProvidable {
    static var parsingHints: [AWSShapeProperty] { get }
}

extension ParsingHintProvidable {
    public static var parsingHints: [AWSShapeProperty] { return [] }
}

public protocol DictionaryInitializable: ParsingHintProvidable {
    init(dictionary: [String: Any]) throws
}

public protocol DictionarySerializable: ParsingHintProvidable {}

extension Collection where Iterator.Element == DictionarySerializable {
    public func serialize() throws -> [[String: Any]] {
        return try self.map({ try $0.serializeToDictionary() })
    }
}

extension DictionarySerializable {
    public func serializeToDictionary() throws -> [String: Any] {
        let mirror = Mirror.init(reflecting: self)
        var serialized: [String: Any] = [:]
        
        let hints = type(of: self).parsingHints
        
        for el in mirror.children {
            guard let hint = hints.filter({ $0.label.lowercased() == el.label?.lowercased() }).first else {
                continue
            }
            
            let key: String
            if let location = hint.location {
                key = location.name
            } else {
                key = hint.label
            }
            
            guard let value = unwrap(any: el.value) else {
                continue
            }
            
            switch value {
            case let v as DictionarySerializable:
                serialized[key] = try v.serializeToDictionary()
                
            case let v as [DictionarySerializable]:
                serialized[key] = try v.serialize()
                
            case let v as [AnyHashable: DictionarySerializable]:
                var dict: [String: Any] = [:]
                for (key, value) in v {
                    dict["\(key)"] = try value.serializeToDictionary()
                }
                serialized[key] = dict
                
            case _ as NSNull:
                break
                
            default:
                serialized[key] = value
            }
        }
        return serialized
    }
    
    func serializeToFlatDictionary() throws -> [String: Any] {
        func flatten(dictionary: [String: Any]) -> [String: Any] {
            var flatted: [String: Any] = [:]
            
            func destructiveFlatten(dictionary: [String: Any]) {
                for (key, value) in dictionary {
                    switch value {
                    case let value as [String: Any]:
                        for (key2, value2) in flatten(dictionary: value) {
                            switch value2 {
                            case let value2 as [String: Any]:
                                destructiveFlatten(dictionary: value2)
                                
                            case let values as [Any]: // TODO: values<Element> might be dictionary...
                                for iterator in values.enumerated() {
                                    flatted["\(key).member.\(iterator.offset+1)"] = iterator.element
                                }
                                
                            default:
                                flatted["\(key).\(key2)"] = value2
                            }
                        }
                        
                    case let values as [Any]: // TODO: values<Element> might be dictionary...
                        for iterator in values.enumerated() {
                            flatted["\(key).member.\(iterator.offset+1)"] = iterator.element
                        }
                        
                    default:
                        flatted[key] = value
                    }
                }
            }
            
            destructiveFlatten(dictionary: dictionary)
            
            return flatted
        }
        
        return flatten(dictionary: try self.serializeToDictionary())
    }
}

public typealias DictionaryConvertible = DictionarySerializable & DictionaryInitializable
