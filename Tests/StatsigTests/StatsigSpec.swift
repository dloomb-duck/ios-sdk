import Foundation

import Quick
import Nimble
import OHHTTPStubs
import OHHTTPStubsSwift

@testable import Statsig

class StatsigSpec: QuickSpec {
    static let mockUserValues: [String: Any] = [
        "feature_gates": [
            "gate_name_1".sha256(): ["value": false, "rule_id": "rule_id_1"],
            "gate_name_2".sha256(): ["value": true, "rule_id": "rule_id_2"]
        ],
        "dynamic_configs": [
            "config".sha256(): DynamicConfigSpec.TestMixedConfig
        ]
    ]

    override func spec() {
        describe("starting Statsig") {
            beforeEach {
                InternalStore.deleteLocalStorage()
            }

            afterEach {
                HTTPStubs.removeAllStubs()
                Statsig.shutdown()
                InternalStore.deleteLocalStorage()
            }

            context("when starting with invalid SDK keys") {
                it("works when provided invalid SDK key by returning default value") {
                    stub(condition: isHost("api.statsig.com")) { _ in
                        let notConnectedError = NSError(domain: NSURLErrorDomain, code: 403)
                        return HTTPStubsResponse(error: notConnectedError)
                    }

                    var error: String?
                    var gate: Bool?
                    var config: DynamicConfig?
                    Statsig.start(sdkKey: "invalid_sdk_key", options: StatsigOptions()) { errorMessage in
                        error = errorMessage
                        gate = Statsig.checkGate("show_coupon")
                        config = Statsig.getConfig("my_config")
                    }
                    expect(error).toEventually(contain("403"))
                    expect(gate).toEventually(beFalse())
                    expect(NSDictionary(dictionary: config!.value)).toEventually(equal(NSDictionary(dictionary: [:])))
                }

                it("works when provided server secret by returning default value") {
                    var error: String?
                    var gate: Bool?
                    var config: DynamicConfig?
                    Statsig.start(sdkKey: "secret-key") { errorMessage in
                        error = errorMessage
                        gate = Statsig.checkGate("show_coupon")
                        config = Statsig.getConfig("my_config")
                    }
                    expect(error).toEventually(equal("Must use a valid client SDK key."))
                    expect(gate).toEventually(beFalse())
                    expect(NSDictionary(dictionary: config!.value)).toEventually(equal(NSDictionary(dictionary: [:])))
                }
            }

            context("when starting Statsig with valid SDK keys") {
                let gateName1 = "gate_name_1"
                let gateName2 = "gate_name_2"
                let nonExistentGateName = "gate_name_3"

                let configName = "config"
                let nonExistentConfigName = "non_existent_config"

                it("only makes 1 network request if start() is called multiple times") {
                    var requestCount = 0;
                    stub(condition: isHost("api.statsig.com")) { _ in
                        requestCount += 1;
                        return HTTPStubsResponse(jsonObject: [:], statusCode: 200, headers: nil)
                    }

                    Statsig.start(sdkKey: "client-api-key")
                    Statsig.start(sdkKey: "client-api-key")
                    Statsig.start(sdkKey: "client-api-key")

                    expect(requestCount).toEventually(equal(1))
                }

                it("makes 3 network request in 20 seconds and updates internal store's updatedTime correctly each time") {
                    var requestCount = 0;
                    var lastSyncTime: Double = 0;
                    let now = NSDate().timeIntervalSince1970

                    stub(condition: isHost("api.statsig.com")) { request in
                        requestCount += 1;

                        let httpBody = try! JSONSerialization.jsonObject(
                            with: request.ohhttpStubs_httpBody!,
                            options: []) as! [String: Any]
                        lastSyncTime = httpBody["lastSyncTimeForUser"] as? Double ?? 0

                        return HTTPStubsResponse(jsonObject: ["time": now * 1000], statusCode: 200, headers: nil)
                    }

                    Statsig.start(sdkKey: "client-api-key")

                    // first request, "lastSyncTimeForUser" field should not be present in the request body
                    expect(requestCount).toEventually(equal(1), timeout: .seconds(1))
                    expect(lastSyncTime).to(equal(0))

                    // second request, "lastSyncTimeForUser" field should be the time when the first request was sent
                    expect(requestCount).toEventually(equal(2), timeout: .seconds(11))
                    expect(Int(lastSyncTime / 1000)).toEventually(equal(Int(now)), timeout: .seconds(11))
                }

                it("works correctly with a valid JSON response") {
                    stub(condition: isHost("api.statsig.com")) { _ in
                        return HTTPStubsResponse(jsonObject: StatsigSpec.mockUserValues, statusCode: 200, headers: nil)
                    }

                    var gate1: Bool?
                    var gate2: Bool?
                    var nonExistentGate: Bool?
                    var dc: DynamicConfig?
                    var nonExistentDC: DynamicConfig?
                    Statsig.start(sdkKey: "client-api-key") { errorMessage in
                        gate1 = Statsig.checkGate(gateName1)
                        gate2 = Statsig.checkGate(gateName2)
                        nonExistentGate = Statsig.checkGate(nonExistentGateName)

                        dc = Statsig.getConfig(configName)
                        nonExistentDC = Statsig.getConfig(nonExistentConfigName)
                    }

                    expect(gate1).toEventually(beFalse())
                    expect(gate2).toEventually(beTrue())
                    expect(nonExistentGate).toEventually(beFalse())

                    expect(NSDictionary(dictionary: dc!.value)).toEventually(
                        equal(NSDictionary(dictionary: DynamicConfigSpec.TestMixedConfig["value"] as! [String: Any])))
                    expect(NSDictionary(dictionary: nonExistentDC!.value)).toEventually(equal(NSDictionary(dictionary: [:])))
                }

                it("times out if the request took too long and responds early with default values, when there is no local cache") {
                    stub(condition: isHost("api.statsig.com")) { _ in
                        return HTTPStubsResponse(jsonObject: StatsigSpec.mockUserValues, statusCode: 200, headers: nil)
                            .responseTime(4.0)
                    }

                    var error: String?
                    var gate: Bool?
                    var dc: DynamicConfig?
                    let timeBefore = NSDate().timeIntervalSince1970
                    var timeDiff: TimeInterval? = 0

                    Statsig.start(sdkKey: "client-api-key") { errorMessage in
                        error = errorMessage
                        gate = Statsig.checkGate(gateName2)
                        dc = Statsig.getConfig(configName)
                        timeDiff = NSDate().timeIntervalSince1970 - timeBefore
                    }

                    // check the values immediately following the completion block from start() assignments
                    expect(error).toEventually(beNil(), timeout: .milliseconds(3500))
                    expect(gate).toEventually(beFalse(), timeout: .milliseconds(3500))
                    expect(NSDictionary(dictionary: dc!.value)).toEventually(equal(NSDictionary(dictionary: [:])), timeout: .milliseconds(3500))
                    expect(Int(timeDiff!)).toEventually(equal(3), timeout: .milliseconds(3500))

                    // check the same gate and config >4 seconds later should return the results from response JSON
                    expect(Statsig.checkGate(gateName2)).toEventually(beTrue(), timeout: .milliseconds(4500))
                    expect(Statsig.getConfig(configName)).toEventuallyNot(beNil(), timeout: .milliseconds(4500))
                }

                it("times out and returns value from local cache") {
                    stub(condition: isHost("api.statsig.com")) { _ in
                        return HTTPStubsResponse(jsonObject: StatsigSpec.mockUserValues, statusCode: 200, headers: nil)
                    }

                    var gate: Bool?
                    var nonExistentGate: Bool?
                    var dc: DynamicConfig?
                    var nonExistentDC: DynamicConfig?

                    // First call start() to fetch and store values in local storage
                    Statsig.start(sdkKey: "client-api-key") { errorMessage in
                        // shutdown client to call start() again, and makes response slow so we can test early timeout with cached return
                        Statsig.shutdown()
                        stub(condition: isHost("api.statsig.com")) { _ in
                            return HTTPStubsResponse(jsonObject: StatsigSpec.mockUserValues, statusCode: 200, headers: nil).responseTime(3)
                        }

                        Statsig.start(sdkKey: "client-api-key", options: StatsigOptions(initTimeout: 0.1)) { errorMessage in
                            gate = Statsig.checkGate(gateName2)
                            nonExistentGate = Statsig.checkGate(nonExistentGateName)
                            dc = Statsig.getConfig(configName)
                            nonExistentDC = Statsig.getConfig(nonExistentConfigName)
                        }
                    }

                    expect(gate).toEventually(beTrue())
                    expect(nonExistentGate).toEventually(beFalse())
                    expect(dc).toEventuallyNot(beNil())
                    expect(NSDictionary(dictionary: nonExistentDC!.value)).toEventually(equal(NSDictionary(dictionary: [:])))
                }

                it("correctly shuts down") {
                    var trueBool: Bool?
                    var dc: DynamicConfig?
                    Statsig.start(sdkKey: "client-api-key") { errorMessage in
                        Statsig.shutdown()
                        trueBool = Statsig.checkGate(gateName2)
                        dc = Statsig.getConfig(configName)
                    }
                    expect(trueBool).toEventually(beFalse())
                    expect(NSDictionary(dictionary: dc!.value)).toEventually(equal(NSDictionary(dictionary: [:])))
                }
            }
        }
    }
}
