import Testing
@testable import InstalloryCore

@Suite("GrantedPathResolver")
struct GrantedPathResolverTests {
    @Test("exact and ancestor grants cover a target")
    func ancestorCoverage() {
        #expect(
            GrantedPathResolver.deepestCoveringPath(
                for: "/Users/tester/projects/Installory",
                among: ["/Users/tester/projects/Installory"]
            ) == "/Users/tester/projects/Installory"
        )
        #expect(
            GrantedPathResolver.deepestCoveringPath(
                for: "/Users/tester/projects/Installory",
                among: ["/Users/tester"]
            ) == "/Users/tester"
        )
    }

    @Test("child and sibling-prefix grants do not cover a target")
    func rejectsChildAndSiblingPrefix() {
        #expect(
            GrantedPathResolver.deepestCoveringPath(
                for: "/Users/tester",
                among: ["/Users/tester/.claude", "/Users/tester2"]
            ) == nil
        )
    }

    @Test("deepest covering grant wins independent of input order")
    func deepestGrantWinsDeterministically() {
        let grants = ["/Users", "/", "/Users/tester/projects", "/Users/tester"]
        let target = "/Users/tester/projects/Installory"

        #expect(
            GrantedPathResolver.deepestCoveringPath(for: target, among: grants)
                == "/Users/tester/projects"
        )
        #expect(
            GrantedPathResolver.deepestCoveringPath(for: target, among: Array(grants.reversed()))
                == "/Users/tester/projects"
        )
    }

    @Test("redundant path components are standardized before comparison")
    func standardizesPaths() {
        #expect(
            GrantedPathResolver.deepestCoveringPath(
                for: "/Users/tester/projects/../projects/Installory/",
                among: ["/Users/tester/projects/./"]
            ) == "/Users/tester/projects/./"
        )
        #expect(
            GrantedPathResolver.referToSameLocation(
                "/Users/tester/projects/Installory/",
                "/Users/tester/projects/./Installory"
            )
        )
    }
}
