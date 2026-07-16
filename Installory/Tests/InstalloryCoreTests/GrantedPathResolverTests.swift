import Testing
@testable import InstalloryCore

@Suite("GrantedPathResolver")
struct GrantedPathResolverTests {
    @Test("exact and ancestor grants cover a target")
    func ancestorCoverage() {
        #expect(
            GrantedPathResolver.deepestCoveringPath(
                for: "/Users/willy/projects/Installory",
                among: ["/Users/willy/projects/Installory"]
            ) == "/Users/willy/projects/Installory"
        )
        #expect(
            GrantedPathResolver.deepestCoveringPath(
                for: "/Users/willy/projects/Installory",
                among: ["/Users/willy"]
            ) == "/Users/willy"
        )
    }

    @Test("child and sibling-prefix grants do not cover a target")
    func rejectsChildAndSiblingPrefix() {
        #expect(
            GrantedPathResolver.deepestCoveringPath(
                for: "/Users/willy",
                among: ["/Users/willy/.claude", "/Users/willy2"]
            ) == nil
        )
    }

    @Test("deepest covering grant wins independent of input order")
    func deepestGrantWinsDeterministically() {
        let grants = ["/Users", "/", "/Users/willy/projects", "/Users/willy"]
        let target = "/Users/willy/projects/Installory"

        #expect(
            GrantedPathResolver.deepestCoveringPath(for: target, among: grants)
                == "/Users/willy/projects"
        )
        #expect(
            GrantedPathResolver.deepestCoveringPath(for: target, among: Array(grants.reversed()))
                == "/Users/willy/projects"
        )
    }

    @Test("redundant path components are standardized before comparison")
    func standardizesPaths() {
        #expect(
            GrantedPathResolver.deepestCoveringPath(
                for: "/Users/willy/projects/../projects/Installory/",
                among: ["/Users/willy/projects/./"]
            ) == "/Users/willy/projects/./"
        )
        #expect(
            GrantedPathResolver.referToSameLocation(
                "/Users/willy/projects/Installory/",
                "/Users/willy/projects/./Installory"
            )
        )
    }
}
