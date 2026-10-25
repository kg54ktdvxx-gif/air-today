import SwiftUI
import AirTodayCore

/// First-launch onboarding — what the app does, how it looks when the air is bad,
/// the optional health profile, then location.
public struct OnboardingView: View {
    let locationService: LocationService
    let onComplete: () -> Void

    @State private var currentStep = Step.welcome

    @AppStorage(HealthProfile.Key.respiratory, store: .shared) private var hasRespiratoryCondition = false
    @AppStorage(HealthProfile.Key.ozoneSensitive, store: .shared) private var isOzoneSensitive = false
    @AppStorage(HealthProfile.Key.children, store: .shared) private var hasChildren = false

    public init(locationService: LocationService, onComplete: @escaping () -> Void) {
        self.locationService = locationService
        self.onComplete = onComplete
    }

    enum Step: Int, CaseIterable {
        case welcome, atmosphere, you, location

        var label: String {
            switch self {
            case .welcome: "Welcome"
            case .atmosphere: "Atmosphere"
            case .you: "You"
            case .location: "Location"
            }
        }

        /// The atmosphere step shows what a hazardous day looks like.
        var backgroundLevel: AQILevel {
            self == .atmosphere ? .hazardous : .good
        }
    }

    public var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                TabView(selection: $currentStep) {
                    welcomePage.tag(Step.welcome)
                    atmospherePage.tag(Step.atmosphere)
                    youPage.tag(Step.you)
                    locationPage.tag(Step.location)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .shadow(color: .black.opacity(0.45), radius: 6, y: 2)

                stepIndicator
                    .padding(.bottom, 16)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Background

    private var background: some View {
        GeometryReader { geo in
            ZStack {
                Color.black

                ForEach(Step.allCases, id: \.self) { step in
                    Image(step.backgroundLevel.backgroundImageName)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .opacity(step.backgroundLevel == currentStep.backgroundLevel ? 1 : 0)
                }

                // Readability: darker at top and bottom where text and buttons sit.
                LinearGradient(
                    colors: [.black.opacity(0.55), .black.opacity(0.15), .black.opacity(0.6)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .animation(DS.Motion.atmospheric, value: currentStep.backgroundLevel)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    // MARK: - Welcome

    private var welcomePage: some View {
        VStack(spacing: DS.spacingXL + 4) {
            Spacer()

            Image(systemName: "aqi.medium")
                .font(.system(size: 64))
                .foregroundStyle(.white)
                .symbolEffect(.breathe)
                .accessibilityHidden(true)

            Text("Air Today")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(.white)

            Text("Know when it's safe to be outside")
                .font(.title3)
                .foregroundStyle(.white.opacity(DS.opacityPrimary))
                .multilineTextAlignment(.center)

            Spacer()

            nextButton("Get Started") { advance(to: .atmosphere) }
        }
        .padding(DS.spacingXXL)
    }

    // MARK: - Atmosphere

    private var atmospherePage: some View {
        VStack(spacing: DS.spacingSM) {
            Spacer()

            Text("Stay indoors")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(AQILevel.hazardous.label)
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .foregroundStyle(.white.opacity(DS.opacityPrimary))

            Spacer()

            Text("The screen tells you the answer\nbefore the numbers do.")
                .font(.title3)
                .foregroundStyle(.white.opacity(DS.opacityPrimary))
                .multilineTextAlignment(.center)
                .padding(.bottom, DS.spacingXXL)

            nextButton("Continue") { advance(to: .you) }
        }
        .padding(DS.spacingXXL)
        .accessibilityElement(children: .contain)
    }

    // MARK: - You

    private var youPage: some View {
        VStack(spacing: DS.spacingXL) {
            Spacer()

            VStack(spacing: DS.spacingSM) {
                Text("Tailor your guidance")
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                Text("Optional — tap any that apply. We'll personalize your activity recommendations. Nothing leaves your device.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(DS.opacityPrimary))
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: DS.spacingMD) {
                HealthTile(
                    icon: "lungs.fill",
                    title: "Asthma or respiratory condition",
                    detail: "Earlier warnings and gentler activity advice",
                    isOn: $hasRespiratoryCondition
                )
                HealthTile(
                    icon: "sun.haze.fill",
                    title: "Sensitive to ozone",
                    detail: "Flags ozone afternoons and better times to go out",
                    isOn: $isOzoneSensitive
                )
                HealthTile(
                    icon: "figure.and.child.holdinghands",
                    title: "Children in household",
                    detail: "Stricter playground and outdoor play advice",
                    isOn: $hasChildren
                )
            }

            Spacer()

            nextButton("Continue") { advance(to: .location) }
        }
        .padding(.horizontal, DS.spacingXL)
        .padding(.vertical, DS.spacingXXL)
    }

    // MARK: - Location Permission

    private var locationPage: some View {
        VStack(spacing: DS.spacingXL + 4) {
            Spacer()

            Image(systemName: "location.circle.fill")
                .font(.system(size: 64))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.black.opacity(0.8), .white)
                .accessibilityHidden(true)

            Text("Enable Location")
                .font(.system(.title, design: .rounded, weight: .bold))
                .foregroundStyle(.white)

            Text("Air Today uses your location to find the nearest monitoring station. Your coordinates are only sent to the World Air Quality Index to fetch readings — never stored on a server or shared.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(DS.opacityPrimary))
                .multilineTextAlignment(.center)

            Spacer()

            VStack(spacing: DS.spacingMD) {
                nextButton("Enable Location") {
                    locationService.requestPermission()
                    onComplete()
                }

                Button("Skip for Now") {
                    onComplete()
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(DS.opacityPrimary))
            }
        }
        .padding(DS.spacingXXL)
    }

    // MARK: - Step Indicator

    private var stepIndicator: some View {
        HStack(spacing: 4) {
            ForEach(Step.allCases, id: \.self) { step in
                let isSelected = currentStep == step
                HStack(spacing: 4) {
                    Circle()
                        .fill(isSelected ? .white : .white.opacity(0.35))
                        .frame(width: 7, height: 7)

                    if isSelected {
                        Text(step.label)
                            .font(.system(.caption2, design: .rounded, weight: .semibold))
                            .foregroundStyle(.white)
                            .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .leading)))
                    }
                }
                .padding(.horizontal, isSelected ? 10 : 6)
                .padding(.vertical, 5)
                .background(isSelected ? .white.opacity(0.15) : .clear, in: Capsule())
                .contentShape(Capsule())
                .onTapGesture { advance(to: step) }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(step.label), step \(step.rawValue + 1) of \(Step.allCases.count)")
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.black.opacity(0.25), in: Capsule())
        .animation(DS.Motion.quick, value: currentStep)
    }

    // MARK: - Helpers

    private func advance(to step: Step) {
        withAnimation(DS.Motion.standard) { currentStep = step }
    }

    private func nextButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.spacingLG)
                .background(.white.opacity(0.25), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.35)))
        }
    }
}
