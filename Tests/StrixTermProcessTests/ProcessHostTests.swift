#if canImport(Darwin)
import Testing
@testable import StrixTermProcess
@testable import StrixTermCore

@Suite("ProcessHost Tests")
struct ProcessHostTests {
    @Test("ProcessHost initialization")
    func initialization() {
        let host = ProcessHost()
        #expect(host.pid == 0)
    }
}
#endif
