import SwiftUI

/// A whole-tile toggle: tapping anywhere on it flips the answer.
struct HealthTile: View {
    let icon: String
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(DS.Motion.quick) { isOn.toggle() }
        } label: {
            HStack(spacing: DS.spacingMD) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(.white.opacity(isOn ? 1 : DS.opacitySecondary))
                    .frame(width: DS.iconLG)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(DS.opacitySecondary))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: DS.spacingSM)

                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(isOn ? 1 : DS.opacityQuaternary))
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(DS.spacingLG)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                // Material keeps the copy readable over bright photo backgrounds.
                RoundedRectangle(cornerRadius: DS.cornerRadius)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: DS.cornerRadius)
                            .fill(isOn ? .white.opacity(0.2) : .black.opacity(0.25))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: DS.cornerRadius)
                    .strokeBorder(.white.opacity(isOn ? 0.6 : 0.15), lineWidth: isOn ? 1.5 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: DS.cornerRadius))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isOn)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityHint(detail)
        .accessibilityValue(isOn ? "Selected" : "Not selected")
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}
