import Testing
import Foundation
@testable import InstalloryCore

@Suite("AIAttribution")
struct AIAttributionTests {

    // MARK: - Helpers

    private func makeEvidence(withClaudeContext: Bool) -> ProvenanceEvidence {
        let ctx: ProvenanceEvidence.ClaudeCodeContext? = withClaudeContext
            ? ProvenanceEvidence.ClaudeCodeContext(
                sessionId: "test-session-001",
                projectPath: "/Users/demo/Projects/test-app",
                sessionSummary: "Setting up test project",
                firstUserMessage: "Help me install some tools",
                bashInvocation: "brew install ffmpeg",
                timestamp: Date()
              )
            : nil

        return ProvenanceEvidence(
            packageId: "brew::ffmpeg",
            fsInstallTime: Date(),
            fsInstallTimeSource: "INSTALL_RECEIPT.json",
            installCommand: nil,
            claudeCodeContext: ctx,
            nearbyProjects: [],
            coInstalledWithin1h: [],
            overallConfidence: .high,
            collectedAt: Date()
        )
    }

    // MARK: - Core predicate

    @Test func evidenceWithClaudeCodeContextReturnsTrue() {
        let evidence = makeEvidence(withClaudeContext: true)
        #expect(wasInstalledByAIAssistant(evidence) == true)
    }

    @Test func evidenceWithoutClaudeCodeContextReturnsFalse() {
        let evidence = makeEvidence(withClaudeContext: false)
        #expect(wasInstalledByAIAssistant(evidence) == false)
    }

    @Test func nilEvidenceReturnsFalse() {
        #expect(wasInstalledByAIAssistant(nil) == false)
    }

    // MARK: - Determinism

    @Test func deterministicForSameInput() {
        let withCtx = makeEvidence(withClaudeContext: true)
        let withoutCtx = makeEvidence(withClaudeContext: false)

        // Same result on multiple calls
        #expect(wasInstalledByAIAssistant(withCtx) == wasInstalledByAIAssistant(withCtx))
        #expect(wasInstalledByAIAssistant(withoutCtx) == wasInstalledByAIAssistant(withoutCtx))
        #expect(wasInstalledByAIAssistant(nil) == wasInstalledByAIAssistant(nil))
    }

    // MARK: - Input immutability

    @Test func inputEvidenceNotMutated() {
        let evidence = makeEvidence(withClaudeContext: true)
        let sessionIdBefore = evidence.claudeCodeContext?.sessionId
        _ = wasInstalledByAIAssistant(evidence)
        // The function must not mutate its input
        #expect(evidence.claudeCodeContext?.sessionId == sessionIdBefore)
    }
}
