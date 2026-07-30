//
//  OrderedListMarkerStyle.swift
//  rankbuddy-macos
//

import Foundation

nonisolated enum OrderedListMarkerStyle: Equatable {
    case decimal
    case lowerAlpha
    case upperAlpha
    case lowerRoman
    case upperRoman

    init(htmlType: String?) {
        switch htmlType {
        case "a": self = .lowerAlpha
        case "A": self = .upperAlpha
        case "i": self = .lowerRoman
        case "I": self = .upperRoman
        default: self = .decimal
        }
    }

    func marker(for value: Int) -> String {
        switch self {
        case .decimal:
            String(value)
        case .lowerAlpha:
            Self.alphabetic(value).lowercased()
        case .upperAlpha:
            Self.alphabetic(value)
        case .lowerRoman:
            Self.roman(value).lowercased()
        case .upperRoman:
            Self.roman(value)
        }
    }

    private static func alphabetic(_ value: Int) -> String {
        guard value > 0 else { return String(value) }

        let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        var number = value
        var result = ""
        while number > 0 {
            number -= 1
            result.insert(letters[number % letters.count], at: result.startIndex)
            number /= letters.count
        }
        return result
    }

    private static func roman(_ value: Int) -> String {
        guard value > 0 else { return String(value) }

        let symbols = [
            (1000, "M"), (900, "CM"), (500, "D"), (400, "CD"), (100, "C"), (90, "XC"),
            (50, "L"), (40, "XL"), (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")
        ]
        var number = value
        var result = ""
        for (amount, symbol) in symbols {
            while number >= amount {
                result += symbol
                number -= amount
            }
        }
        return result
    }
}
