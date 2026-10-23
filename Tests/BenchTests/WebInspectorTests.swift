// WebInspectorTests.swift — Safari's Web Inspector attaches to a release build
// only when the hidden setting says so (DESIGN.md, the web view's settings).
import Foundation
import Testing
@testable import Bench

@Suite struct WebInspectorTests {
    private func defaults(_ body: (UserDefaults) -> Void) {
        let scratch = ScratchDefaults.make(prefix: "capsid-inspector-tests")
        defer { scratch.discard() }
        body(scratch.defaults)
    }

    @Test func aReleaseBuildIsNotInspectableByDefault() {
        defaults { #expect(!WebSetup.inspectable(debug: false, defaults: $0)) }
    }

    @Test func theHiddenSettingOpensItInARelease() {
        defaults {
            $0.set(true, forKey: WebSetup.inspectorKey)
            #expect(WebSetup.inspectable(debug: false, defaults: $0))
        }
    }

    @Test func aDebugBuildIsAlwaysInspectable() {
        defaults { #expect(WebSetup.inspectable(debug: true, defaults: $0)) }
    }
}
