import SwiftUI

/// A visual appearance picker (#76): three swatches — System, Light, Dark — each a miniature
/// window preview with a selection ring and radio, replacing the plain segmented control.
/// Mirrors PadBuddy's `AppearancePicker`, reusing the existing `AppAppearance` values.
struct AppearancePicker: View {
    @Binding var selection: AppAppearance

    var body: some View {
        HStack(spacing: 18) {
            ForEach(AppAppearance.allCases) { option in
                Button {
                    selection = option
                } label: {
                    AppearanceSwatch(option: option, isSelected: option == selection)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.label)
                .accessibilityAddTraits(option == selection ? [.isButton, .isSelected] : .isButton)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

/// One appearance option: a window thumbnail above a radio + label.
private struct AppearanceSwatch: View {
    let option: AppAppearance
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            thumbnail
                .frame(width: 76, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay {
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(
                            isSelected ? Color.accentColor : Color.secondary.opacity(0.35),
                            lineWidth: isSelected ? 2.5 : 1
                        )
                }

            Label {
                Text(option.label)
            } icon: {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            .labelStyle(.titleAndIcon)
            .font(.caption)
        }
    }

    /// The swatch's window preview: a concrete light/dark mini-window, or — for System — the
    /// light window with the dark one revealed through the bottom-trailing triangle.
    @ViewBuilder private var thumbnail: some View {
        switch option {
        case .light:
            WindowThumbnail(scheme: .light)
        case .dark:
            WindowThumbnail(scheme: .dark)
        case .system:
            ZStack {
                WindowThumbnail(scheme: .light)
                WindowThumbnail(scheme: .dark).clipShape(DiagonalSplit())
            }
        }
    }
}

/// A miniature macOS window for an appearance swatch: a traffic-light title bar over a few
/// content lines, coloured for a concrete colour scheme.
private struct WindowThumbnail: View {
    let scheme: ColorScheme

    private var isDark: Bool {
        scheme == .dark
    }

    private var background: Color {
        isDark ? Color(white: 0.16) : Color(white: 0.99)
    }

    private var titleBar: Color {
        isDark ? Color(white: 0.26) : Color(white: 0.90)
    }

    private var line: Color {
        isDark ? Color(white: 0.42) : Color(white: 0.72)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 3) {
                ForEach([Color.red, .yellow, .green], id: \.self) { dot in
                    Circle().fill(dot.opacity(0.9)).frame(width: 4, height: 4)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 5)
            .frame(height: 12)
            .frame(maxWidth: .infinity)
            .background(titleBar)

            VStack(alignment: .leading, spacing: 3) {
                ForEach(0 ..< 3) { _ in
                    Capsule().fill(line).frame(height: 3)
                }
                Spacer(minLength: 0)
            }
            .padding(5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(background)
        }
    }
}

/// The bottom-trailing triangle that reveals the dark half of the System swatch over the
/// light one, so it reads as a split light/dark preview.
private struct DiagonalSplit: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

#Preview("Appearance picker") {
    @Previewable @State var appearance: AppAppearance = .system
    return Form {
        Section("Appearance") {
            AppearancePicker(selection: $appearance)
                .padding(.vertical, 4)
        }
    }
    .formStyle(.grouped)
    .frame(width: 420)
    .padding()
}
