import SwiftUI
import AirTodayCore

/// First-launch onboarding in three steps — what the app does (the sky behind it
/// hazes over and clears to show how it looks when the air is bad), the optional
/// health profile, then location and alerts.
public struct OnboardingView: View {
    let locationService: LocationService
    let onComplete: () -> Void

    @State private var currentStep = Step.welcome
    /// The welcome step's sky, which hazes over once and clears.
    @State private var welcomeSky = AQILevel.good
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage(HealthProfile.Key.respiratory, store: .shared) private var hasRespiratoryCondition = false
    @AppStorage(HealthProfile.Key.ozoneSensitive, store: .shared) private var isOzoneSensitive = false
    @AppStorage(HealthProfile.Key.children, store: .shared) private var hasChildren = false
    @AppStorage(AQIScale.storageKey, store: .shared) private var scale: AQIScale = .usEPA
    @AppStorage(NotificationPreferences.Key.alertsOffered, store: .shared) private var alertsOffered = false
    @AppStorage(NotificationPreferences.Key.thresholdAlerts, store: .shared) private var thresholdAlerts = false

    /// From the health answers: those with a reason to be careful hear sooner.
    private var suggestedLevel: AQILevel {
        NotificationPreferences.suggestedThreshold(for: HealthProfile(
            hasRespiratoryCondition: hasRespiratoryCondition,
            isOzoneSensitive: isOzoneSensitive,
            hasChildren: hasChildren
        ))
    }

    public init(locationService: LocationService, onComplete: @escaping () -> Void) {
        self.locationService = locationService
        self.onComplete = onComplete
    }

    enum Step: Int, CaseIterable {
        case welcome, you, setup

        var label: String {
            switch self {
            case .welcome: "Welcome"
            case .you: "You"
            case .setup: "Set Up"
            }
        }
    }

    private var backgroundLevel: AQILevel {
        currentStep == .welcome ? welcomeSky : .good
    }

    public var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                TabView(selection: $currentStep) {
                    fitOrScroll { welcomePage }.tag(Step.welcome)
                    fitOrScroll { youPage }.tag(Step.you)
                    fitOrScroll { setupPage }.tag(Step.setup)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                stepIndicator
                    .padding(.bottom, DS.spacingLG)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Background

    private var background: some View {
        GeometryReader { geo in
            ZStack {
                Color.black

                ForEach([AQILevel.good, .hazardous], id: \.self) { level in
                    Image(level.backgroundImageName)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .opacity(level == backgroundLevel ? 1 : 0)
                }

                // Readability: darker at top and bottom where text and buttons sit.
                LinearGradient(
                    colors: [.black.opacity(0.55), .black.opacity(0.15), .black.opacity(0.6)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .animation(DS.Motion.atmospheric, value: backgroundLevel)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    // MARK: - Welcome

    private var welcomePage: some View {
        VStack(spacing: DS.spacingXL) {
            Spacer()

            Image(systemName: "aqi.medium")
                .font(.system(size: 64))
                .symbolEffect(.breathe, isActive: !reduceMotion)
                .accessibilityHidden(true)

            VStack(spacing: DS.spacingSM) {
                Text("Air Today")
                    .font(.largeTitle.weight(.bold))
                Text("Know when it's safe to be outside")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(DS.opacityPrimary))
            }

            Spacer()

            Text("The sky in Air Today follows the air: clear when it's clean, hazy when it isn't.")
                .font(DS.Typeface.body)
                .foregroundStyle(.white.opacity(DS.opacityPrimary))

            nextButton("Get Started") { advance(to: .you) }
        }
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
        .skyTextShadow()
        .frame(maxWidth: DS.readableWidth)
        .padding(DS.spacingXXL)
        .task { await hazeOverOnce() }
    }

    /// Shows what a bad day looks like: the sky hazes over, then clears — and always
    /// ends clear, even if the step is left part-way.
    private func hazeOverOnce() async {
        guard !reduceMotion else { return }
        do {
            try await Task.sleep(for: .seconds(2))
            welcomeSky = .hazardous
            try await Task.sleep(for: .seconds(3))
        } catch {}
        welcomeSky = .good
    }

    // MARK: - You

    private var youPage: some View {
        VStack(spacing: DS.spacingXL) {
            Spacer()

            VStack(spacing: DS.spacingSM) {
                Text("Tailor your guidance")
                    .font(DS.Typeface.stepTitle)
                    .foregroundStyle(.white)
                Text("Optional — tap any that apply. We'll personalize your activity recommendations. Nothing leaves your device.")
                    .font(DS.Typeface.body)
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

            nextButton("Continue") { advance(to: .setup) }
        }
        .skyTextShadow()
        .frame(maxWidth: DS.readableWidth)
        .padding(.horizontal, DS.spacingXL)
        .padding(.vertical, DS.spacingXXL)
    }

    // MARK: - Location and Alerts

    private var setupPage: some View {
        VStack(spacing: DS.spacingXL) {
            Spacer()

            VStack(spacing: DS.spacingSM) {
                Text("Location and alerts")
                    .font(DS.Typeface.stepTitle)
                    .foregroundStyle(.white)
                Text("Both optional. You can change them in Settings.")
                    .font(DS.Typeface.body)
                    .foregroundStyle(.white.opacity(DS.opacityPrimary))
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: DS.spacingMD) {
                HealthTile(
                    icon: "location.fill",
                    title: "Use my location",
                    detail: "For the air where you are. Your coordinates go only to the World Air Quality Index, Open-Meteo and Apple Maps; Air Today has no server and keeps no record.",
                    isOn: Binding(
                        get: { locationService.hasPermission },
                        set: { if $0 { requestLocation() } }
                    )
                )
                HealthTile(
                    icon: "bell.fill",
                    title: "Alert me at \(scale.bandName(for: suggestedLevel))",
                    detail: "When the air reaches it on the \(scale.shortName), here and in the places you save. Checked in the background.",
                    isOn: Binding(
                        get: { thresholdAlerts },
                        set: { setAlerts($0) }
                    )
                )
            }

            Spacer()

            nextButton("Done") {
                // Someone who left alerts off has had the offer; don't repeat it on the main screen.
                if !thresholdAlerts { alertsOffered = true }
                onComplete()
            }
        }
        .skyTextShadow()
        .frame(maxWidth: DS.readableWidth)
        .padding(.horizontal, DS.spacingXL)
        .padding(.vertical, DS.spacingXXL)
    }

    /// Asks, or — once someone has said no — opens Settings, where they can change it.
    private func requestLocation() {
        if locationService.isDenied, let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        } else {
            locationService.requestPermission()
        }
    }

    private func setAlerts(_ on: Bool) {
        if on {
            let level = suggestedLevel
            Task { await NotificationPreferences.enableThresholdAlerts(at: level) }
        } else {
            thresholdAlerts = false
            Task { await AlertCoordinator.preferencesChanged() }
        }
    }

    /// A step at its own height, scrolling only when large text makes it taller than
    /// the screen — so its buttons can always be reached.
    private func fitOrScroll(@ViewBuilder _ page: () -> some View) -> some View {
        let page = page()
        return GeometryReader { geo in
            ScrollView(.vertical) {
                page
                    .frame(maxWidth: .infinity, minHeight: geo.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
        }
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
                            .font(DS.Typeface.fine.weight(.semibold))
                            .foregroundStyle(.white)
                            .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .leading)))
                    }
                }
                .padding(.horizontal, isSelected ? 10 : 6)
                .padding(.vertical, 5)
                .background(isSelected ? .white.opacity(0.15) : .clear, in: Capsule())
                // Small dots, full-size tap targets.
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
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
                .background { DS.liftedGlass(in: RoundedRectangle(cornerRadius: DS.cornerRadiusSM)) }
        }
    }
}
