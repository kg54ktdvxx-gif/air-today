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

                VStack(alignment: .leading, spacing: DS.spacingXXS) {
                    Text(title)
                        .font(DS.Typeface.rowTitle)
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail)
                        .font(DS.Typeface.caption)
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
                // The app's glass, lifted when chosen; the checkmark says which.
                if isOn {
                    DS.liftedGlass(in: RoundedRectangle(cornerRadius: DS.cornerRadius))
                } else {
                    DS.cardBackground
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: DS.cornerRadius))
        }
        .buttonStyle(.pressable)
        .sensoryFeedback(.selection, trigger: isOn)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityHint(detail)
        .accessibilityValue(isOn ? "Selected" : "Not selected")
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}
