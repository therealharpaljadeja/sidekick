import SwiftUI

/// Monochrome tokens: ink-on-black, hairline borders, 4px corners, whisper-weight type.
enum Theme {
    static let canvas = Color(white: 0.039)
    static let surface = Color(white: 0.071)
    static let raised = Color(white: 0.11)
    static let hairline = Color(white: 0.16)
    static let text = Color(white: 0.96)
    static let secondary = Color(white: 0.56)
    static let tertiary = Color(white: 0.36)

    static let radius: CGFloat = 4

    enum Weight {
        case regular, medium, semibold

        var postScript: String {
            switch self {
            case .regular: return "Intern-Regular"
            case .medium: return "Intern-Medium"
            case .semibold: return "Intern-SemiBold"
            }
        }
    }

    static func intern(_ size: CGFloat, _ weight: Weight = .regular) -> Font {
        .custom(weight.postScript, size: size)
    }

    static func display(_ size: CGFloat, medium: Bool = false) -> Font {
        .custom(medium ? "InternDisplay-Medium" : "InternDisplay-Regular", size: size)
    }

    static func mono(_ size: CGFloat) -> Font {
        .system(size: size, design: .monospaced)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.intern(13, .medium))
            .foregroundColor(.black)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: Theme.radius)
                    .fill(Theme.text.opacity(configuration.isPressed ? 0.75 : 1))
            )
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.intern(13))
            .foregroundColor(Theme.text)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: Theme.radius)
                    .fill(configuration.isPressed ? Theme.hairline : Theme.raised)
            )
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.hairline, lineWidth: 1))
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.intern(13))
            .foregroundColor(configuration.isPressed ? Theme.text : Theme.secondary)
            .contentShape(Rectangle())
    }
}

struct MonoSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(configuration.isOn ? Theme.text : Theme.raised)
                    .overlay(Capsule().stroke(Theme.hairline, lineWidth: configuration.isOn ? 0 : 1))
                Circle()
                    .fill(configuration.isOn ? Color.black : Theme.secondary)
                    .padding(3)
            }
            .frame(width: 30, height: 18)
            .animation(.spring(response: 0.25, dampingFraction: 0.85), value: configuration.isOn)
        }
        .buttonStyle(.plain)
    }
}
