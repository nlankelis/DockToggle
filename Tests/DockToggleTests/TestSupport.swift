import Foundation

// Small serial assertion runner: no external packages or developer test runtime.
// Tests use a fake backend and virtual time; they never manipulate the user's Dock.
private var assertionCount = 0
private var testCount = 0
private var failureCount = 0

func expect(_ condition: @autoclosure () -> Bool, file: StaticString = #filePath, line: UInt = #line) {
    assertionCount += 1
    if !condition() {
        failureCount += 1
        print("FAIL \(file):\(line)")
    }
}
func run(_ name: String, _ test: () -> Void) {
    let previous = failureCount
    testCount += 1
    test()
    print("\(failureCount == previous ? "PASS" : "FAIL") \(name)")
}
func finish() -> Never {
    print("\(testCount) tests, \(assertionCount) assertions, \(failureCount) failures")
    exit(failureCount == 0 ? 0 : 1)
}
