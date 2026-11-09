import SwiftUI

/// Small label above a group of related values.
struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
    }
}

struct InfoRow<Value: View>: View {
    let label: String
    @ViewBuilder let value: Value

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            value.multilineTextAlignment(.trailing)
        }
        .font(.callout)
        .padding(.vertical, 3.5)
    }
}

extension InfoRow where Value == Text {
    init(_ label: String, _ value: String) {
        self.label = label
        self.value = Text(value)
    }
}

struct InfoGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: title)
            VStack(spacing: 0) { content }
        }
    }
}

/// A slim used-of-total meter.
struct UsageBar: View {
    let fraction: Double
    var height: CGFloat = 5
    var color: Color = Theme.accent
    @State private var shown = 0.0

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.subtleFill)
                Capsule().fill(color)
                    .frame(width: max(height, proxy.size.width * min(max(shown, 0), 1)))
            }
        }
        .frame(height: height)
        .onAppear { withAnimation(Motion.entrance(after: 0.08)) { shown = fraction } }
        .onChange(of: fraction) { _, new in withAnimation(Motion.snappy) { shown = new } }
    }
}

/// A used bar with the amount about to be added shown on top of it.
struct ProjectedUsageBar: View {
    let used: Double
    let adding: Double
    let overflow: Bool

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.subtleFill)
                Capsule().fill((overflow ? Color.red : Theme.accent).opacity(0.55))
                    .frame(width: min(width, width * (used + adding)))
                Capsule().fill(Theme.accent)
                    .frame(width: max(6, width * used))
            }
            .animation(Motion.gentle, value: adding)
            .animation(Motion.fade, value: overflow)
        }
        .frame(height: 6)
    }
}

/// A small neutral label, used for platform, region and format.
struct Tag: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Theme.subtleFill, in: Capsule())
    }
}

struct FilterChip: View {
    let title: String
    let count: Int?
    let selected: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                if let count { Text(count, format: .number).foregroundStyle(.tertiary) }
            }
            .font(.callout.weight(selected ? .medium : .regular))
            .foregroundStyle(selected ? .primary : .secondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 4.5)
            .background(selected ? Theme.selectedFill : (hovered ? Theme.hoverFill : Color.clear), in: Capsule())
            .animation(Motion.fade, value: selected)
            .animation(Motion.fade, value: hovered)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

/// A row of mutually exclusive text tabs with a sliding highlight.
struct PillTabs<Option: Hashable & Identifiable>: View {
    let options: [Option]
    let label: (Option) -> String
    @Binding var selection: Option
    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                Button {
                    withAnimation(Motion.snappy) { selection = option }
                } label: {
                    Text(label(option))
                        .font(.callout.weight(option == selection ? .medium : .regular))
                        .foregroundStyle(option == selection ? .primary : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                        .background {
                            if option == selection {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Theme.selectedFill)
                                    .matchedGeometryEffect(id: "tab", in: highlight)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Theme.subtleFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// A selectable card for choices that need a sentence of explanation.
struct OptionCard<Leading: View>: View {
    let title: String
    let detail: String
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let leading: Leading

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 11) {
                leading
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.medium)).lineLimit(1)
                    Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.tertiary))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Theme.accent.opacity(0.1) : Theme.subtleFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(selected ? Theme.accent.opacity(0.6) : Theme.hairline))
            .animation(Motion.snappy, value: selected)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Fixed layout for every sheet: heading, body, then right-aligned actions.
struct SheetScaffold<Content: View, Actions: View>: View {
    let title: String
    var subtitle: String?
    var width: CGFloat = 480
    @ViewBuilder let content: Content
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.title3.weight(.semibold))
                if let subtitle {
                    Text(subtitle).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            content
            HStack(spacing: 8) { actions }
        }
        .padding(22)
        .frame(width: width)
    }
}

/// A borderless field. The system focus ring would otherwise bring in the user's accent colour.
struct QuietField: View {
    let placeholder: String
    @Binding var text: String
    var monospaced = false

    var body: some View {
        TextField(placeholder, text: $text, prompt: Text(placeholder))
            .textFieldStyle(.plain)
            .labelsHidden()
            .font(monospaced ? .body.monospaced() : .body)
            .autocorrectionDisabled()
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Theme.subtleFill, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.hairline))
    }
}

struct FieldLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
    }
}


/// The accent-coloured ring around a selected cover.
struct SelectionRing: View {
    let corner: CGFloat
    let inset: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .strokeBorder(Theme.accent, lineWidth: 2.5)
            .padding(-inset)
            .transition(Motion.reduced ? .opacity : .scale(scale: 1.06).combined(with: .opacity))
    }
}

extension View {
    /// The one filled button in a sheet or banner.
    func primaryAction() -> some View {
        buttonStyle(.borderedProminent).tint(Theme.accent)
    }
}
