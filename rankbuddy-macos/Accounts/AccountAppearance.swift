//
//  AccountAppearance.swift
//  rankbuddy-macos
//

import Flow
import SwiftUI

/// Per-account icon + tint (#64): view-layer helpers that turn an account's stored `iconSymbol`
/// / `tintHex` into a usable SF Symbol and `Color`, plus the presets offered in the editor.
extension Account {
    /// A generic person icon used when an account hasn't picked one.
    static let defaultIconSymbol = "person.crop.circle"

    /// The SF Symbol shown for this account, defaulting to a generic person icon.
    var displayIcon: String {
        guard let iconSymbol,
              AccountAppearance.icons.contains(where: { $0.symbol == iconSymbol })
        else { return Self.defaultIconSymbol }

        return iconSymbol
    }

    /// The account's tint parsed from `tintHex`, or `nil` to use the app accent colour.
    var tintColor: Color? {
        tintHex.flatMap(Color.init(accountHex:))
    }
}

/// The icon + tint choices shown in the account editor (#64).
enum AccountAppearance {
    struct Icon: Identifiable, Hashable {
        let symbol: String
        let name: String
        var id: String {
            symbol
        }
    }

    /// SF Symbols a user can pick from to distinguish an account.
    static let icons: [Icon] = [
        Icon(symbol: "person.crop.circle", name: "Person"),
        Icon(symbol: "briefcase", name: "Briefcase"),
        Icon(symbol: "building.2", name: "Building"),
        Icon(symbol: "globe", name: "Globe"),
        Icon(symbol: "star", name: "Star"),
        Icon(symbol: "flag", name: "Flag"),
        Icon(symbol: "graduationcap", name: "Education"),
        Icon(symbol: "person.3", name: "Team"),
        Icon(symbol: "bolt", name: "Bolt"),
        Icon(symbol: "leaf", name: "Leaf")
    ]

    /// A named tint with its stored hex; the first ("Default") stores `nil` to follow the
    /// app accent.
    struct Tint: Identifiable, Hashable {
        let name: String
        /// The "#RRGGBB" value, or `nil` for the default (app accent).
        let hex: String?
        var id: String {
            hex ?? "default"
        }
    }

    static let tints: [Tint] = [
        Tint(name: "Default", hex: nil),
        Tint(name: "Blue", hex: "#3B82F6"),
        Tint(name: "Purple", hex: "#8B5CF6"),
        Tint(name: "Pink", hex: "#EC4899"),
        Tint(name: "Red", hex: "#EF4444"),
        Tint(name: "Orange", hex: "#F97316"),
        Tint(name: "Yellow", hex: "#EAB308"),
        Tint(name: "Green", hex: "#22C55E"),
        Tint(name: "Teal", hex: "#14B8A6")
    ]
}

extension Color {
    /// Parses a "#RRGGBB" (or "RRGGBB") hex string into a `Color`. Returns `nil` for any
    /// malformed input, so a bad stored value simply falls back to the default tint.
    nonisolated init?(accountHex hex: String) {
        var string = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if string.hasPrefix("#") { string.removeFirst() }
        guard string.count == 6, let value = Int(string, radix: 16) else { return nil }

        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

/// The icon + tint controls shown as an "Appearance" section in the account editor (#64).
struct AccountAppearancePicker: View {
    @Binding var selectedIcon: String
    @Binding var selectedTintHex: String?

    private var tint: Color {
        selectedTintHex.flatMap(Color.init(accountHex:)) ?? .accentColor
    }

    var body: some View {
        Section {
            AccountIconPicker(selectedIcon: $selectedIcon, tint: tint)

            HStack(spacing: 10) {
                ForEach(AccountAppearance.tints) { option in
                    let color = option.hex.flatMap(Color.init(accountHex:)) ?? Color.accentColor
                    Button {
                        selectedTintHex = option.hex
                    } label: {
                        Circle()
                            .fill(color)
                            .frame(width: 22, height: 22)
                            .overlay {
                                if selectedTintHex == option.hex {
                                    Circle().strokeBorder(.primary, lineWidth: 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .help(option.name)
                    .accessibilityLabel(option.name)
                    .accessibilityAddTraits(selectedTintHex == option.hex ? [.isButton, .isSelected] : .isButton)
                }
                Spacer(minLength: 0)
            }
        } header: {
            Text("Appearance")
        } footer: {
            Text("An icon and tint to tell this account apart in the switcher and sidebar.")
        }
    }
}

struct AccountIconPicker: View {
    @Binding var selectedIcon: String
    let tint: Color

    var body: some View {
        HFlow(spacing: 6) {
            ForEach(AccountAppearance.icons) { option in
                Button {
                    selectedIcon = option.symbol
                } label: {
                    Image(systemName: option.symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(selectedIcon == option.symbol ? .white : tint)
                        .frame(width: 28, height: 28)
                        .background {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(selectedIcon == option.symbol ? tint : Color.clear)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(selectedIcon == option.symbol ? tint : Color.secondary.opacity(0.25))
                        }
                }
                .buttonStyle(.plain)
                .help(option.name)
                .accessibilityLabel(option.name)
                .accessibilityAddTraits(selectedIcon == option.symbol ? [.isButton, .isSelected] : .isButton)
            }
        }
    }
}

#Preview("Appearance picker") {
    @Previewable @State var icon = "briefcase"
    @Previewable @State var tint: String? = "#8B5CF6"
    return Form {
        AccountAppearancePicker(selectedIcon: $icon, selectedTintHex: $tint)
    }
    .formStyle(.grouped)
    .frame(width: 440)
    .padding()
}
