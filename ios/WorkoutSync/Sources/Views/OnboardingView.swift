import SwiftUI
import UIKit

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @EnvironmentObject var healthKitManager: HealthKitManager

    @State private var isRequestingAuthorization = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var currentPage = 0

    private let pages: [(title: String, body: String)] = [
        (
            "Apple Workout stays.",
            "Athletes train in Apple’s Workout app. TeamPulse reads Health and sends today’s rings to your coach."
        ),
        (
            "Rings, then the roster.",
            "Move, Exercise, and Stand — same as Fitness. The coach board shows who practiced and who needs rest."
        ),
        (
            "You control sharing.",
            "Health data only leaves the phone after you allow access and join a club."
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                PulseBrandMark(size: 26)
                Text("TeamPulse")
                    .font(.system(size: 20, weight: .bold))
                    .tracking(-0.4)
                    .foregroundColor(Pulse.text)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            TabView(selection: $currentPage) {
                ForEach(pages.indices, id: \.self) { index in
                    VStack(spacing: 16) {
                        Spacer(minLength: 8)
                        ActivityRingsView(
                            move: 0.82,
                            exercise: 0.64,
                            stand: 0.5,
                            lineWidth: 15,
                            gap: 5,
                            diameter: 140
                        )
                        Text(pages[index].title)
                            .font(.system(size: 28, weight: .bold))
                            .tracking(-0.5)
                            .foregroundColor(Pulse.text)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.85)
                            .lineLimit(3)
                        Text(pages[index].body)
                            .font(.system(size: 15))
                            .foregroundColor(Pulse.muted)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                    }
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 6) {
                ForEach(pages.indices, id: \.self) { index in
                    Capsule()
                        .fill(index == currentPage ? Color.white : Pulse.card2)
                        .frame(width: index == currentPage ? 16 : 6, height: 6)
                }
            }
            .padding(.bottom, 16)

            VStack(spacing: 10) {
                if currentPage == pages.count - 1 {
                    PulsePrimaryButton(
                        title: isRequestingAuthorization ? "Allowing…" : "Allow Health access",
                        enabled: !isRequestingAuthorization,
                        action: requestHealthKitAuthorization
                    )
                    Button("Skip") { skipOnboarding() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Pulse.muted)
                        .padding(.vertical, 8)
                } else {
                    PulsePrimaryButton(title: "Continue") {
                        withAnimation { currentPage += 1 }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Pulse.bg.ignoresSafeArea())
        .alert("Authorization Error", isPresented: $showError) {
            Button("OK") {}
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        } message: {
            Text(errorMessage)
        }
    }

    private func requestHealthKitAuthorization() {
        isRequestingAuthorization = true
        Task {
            do {
                try await healthKitManager.requestAuthorization()
                await MainActor.run {
                    hasCompletedOnboarding = true
                    isRequestingAuthorization = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isRequestingAuthorization = false
                }
            }
        }
    }

    private func skipOnboarding() {
        hasCompletedOnboarding = true
    }
}

#Preview {
    OnboardingView(hasCompletedOnboarding: .constant(false))
        .environmentObject(HealthKitManager.shared)
}
