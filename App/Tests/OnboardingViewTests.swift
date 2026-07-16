import InstalloryCore
import Testing
@testable import Installory

@Suite("Onboarding manager coverage")
struct OnboardingViewTests {
    @Test("UV-F1: onboarding names the persistent uv scanner")
    @MainActor
    func onboardingNamesPersistentUVTools() {
        #expect(OnboardingView.managerOverview.contains(PackageManager.uv.displayName))
    }
}
