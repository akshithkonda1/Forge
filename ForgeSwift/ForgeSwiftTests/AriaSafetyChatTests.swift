import XCTest
import ForgeCore
@testable import ForgeSwift

/// App-side pieces of ARIA's chat safety: the care line every path leads with,
/// the safety reply and its voice-first session, the dial chips, and a
/// tolerant `safety` decode. The classifier itself is ForgeCore's
/// (AriaSafetyTriageTests asserts the shared corpus).
@MainActor
final class AriaSafetyChatTests: XCTestCase {

    private let sharp = "Sharp is the kind I take seriously — worth a professional look. Nothing today should reproduce it."

    func testCareLineLeadsACoachingReply() {
        let reply = AriaResponse(proseSummary: "Keep it light today.", message: "What I notice\nKeep it light today.")
        let led = AriaService.withCareLine(reply, for: "I get a sharp pain in my knee when I squat")
        XCTAssertEqual(led.message, sharp + "\n\nWhat I notice\nKeep it light today.")
        XCTAssertEqual(led.proseSummary, sharp + " Keep it light today.")
    }

    func testCareLineKeepsAOneLineVoiceReplyOneLine() {
        let reply = AriaResponse(proseSummary: "Keep it light today.", message: "Keep it light today.")
        let led = AriaService.withCareLine(reply, for: "I get a sharp pain in my knee when I squat")
        XCTAssertEqual(led.message, led.proseSummary)
    }

    func testCareLineIsNeverAddedTwice() {
        // /ai/chat already led with it; on-device voice may have appended it.
        let live = AriaResponse(proseSummary: sharp + " Easy today.", message: sharp + "\n\nEasy today.")
        XCTAssertEqual(AriaService.withCareLine(live, for: "sharp pain in my knee"), live)
        let local = AriaResponse(proseSummary: nil, message: "Easy today. " + sharp)
        XCTAssertEqual(AriaService.withCareLine(local, for: "sharp pain in my knee"), local)
    }

    func testOrdinaryTurnsCarryNoCareLine() {
        let reply = AriaResponse(proseSummary: "Steady.", message: "Steady.")
        for text in ["what are my numbers today", "my wife is pregnant, how can I support her?", "should I train hard today?"] {
            XCTAssertEqual(AriaService.withCareLine(reply, for: text), reply, text)
        }
    }

    func testSafetyReplyCarriesTheVoiceFirstSession() throws {
        let decision = try XCTUnwrap(AriaSafetyTriage.assess("I have chest pain"))
        let reply = AriaService.safetyResponse(decision)
        XCTAssertEqual(reply.guidanceBand, AriaSafetyBand.triage)
        XCTAssertEqual(reply.message, decision.prose)
        let session = try XCTUnwrap(reply.safety)
        XCTAssertTrue(session.isTriage)
        XCTAssertTrue(session.wantsVoice)
        XCTAssertNotNil(session.replyTopic)
    }

    func testSafetyChipsDial() {
        XCTAssertEqual(AriaSafetyDialer.number(forAction: "Call 911"), "911")
        XCTAssertEqual(AriaSafetyDialer.number(forAction: " call or text 988 "), "988")
        XCTAssertEqual(AriaSafetyDialer.number(forAction: "Call Poison Control"), "18002221222")
        XCTAssertNil(AriaSafetyDialer.number(forAction: "Plan my week"))
    }

    func testMalformedSafetyBlockNeverCostsTheReply() throws {
        let json = #"{"message": "Call 911 now.", "guidance_band": "emergency", "safety": {"phase": 7}}"#
        let reply = try JSONDecoder().decode(AriaResponse.self, from: Data(json.utf8))
        XCTAssertEqual(reply.message, "Call 911 now.")
        XCTAssertEqual(reply.guidanceBand, "emergency")
        XCTAssertNil(reply.safety)
    }
}
