//
//  ActuallyDoItUITests.swift
//  ActuallyDoItUITests
//
//  Created by Devin Harmse on 03/08/2026.
//

import XCTest
import SwiftUI
import UIKit

final class ActuallyDoItUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // XCUIAutomation Documentation
        // https://developer.apple.com/documentation/xcuiautomation
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}

// MARK: - App Store screenshots

/// Generates the framed, captioned App Store marketing screenshots.
///
/// This is not a pass/fail test — it drives the app (launched in `--screenshots` mode, which seeds
/// a curated in-memory store) into each showcase state, grabs the full device screen, then composes
/// a 1320×2868 marketing image (headline caption + a device-framed screenshot) with SwiftUI's
/// `ImageRenderer`. Each composed image is attached with `.keepAlways`, so a following
/// `xcrun xcresulttool export attachments` lands the final PNGs on disk (see
/// `Scripts/generate_screenshots.sh`).
///
/// Capturing the real screens has to happen on a running simulator (`ImageRenderer` can't rasterize
/// `List`/`Form` content), while the caption/framing is plain `Text`+`Image` that `ImageRenderer`
/// renders faithfully — so both halves live here, in the one process that can do each.
final class ScreenshotTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testGenerateAppStoreScreenshots() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--screenshots"]
        app.launch()

        // 01 — Doing-now hero (top of the Now screen).
        XCTAssertTrue(app.staticTexts["Doing now"].waitForExistence(timeout: 15))
        settle()
        attach(framedAppShot(caption: "Beat overwhelm —\none thing at a time"), "01-focus.png")

        // 04 — the day's board: release the current focus so the "Doing now" hero gives way to a
        // clean Today section (with its progress ring) and the suggested next tasks.
        app.buttons["Can't do this now"].firstMatch.tap()
        settle()
        attach(framedAppShot(caption: "Just today —\nnothing more"), "04-today.png")

        // 02 — the nudge system: open the pre-seeded, already-Relentless task and scroll to the
        // Nudge-intensity section and its timeline.
        app.staticTexts["Book a dentist appointment"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Task details"].waitForExistence(timeout: 10))
        scrollUntilHittable(app.buttons["Relentless"], in: app)
        settle()
        attach(framedAppShot(caption: "Reminders that\ndon't quit"), "02-nudges.png")
        app.buttons["Done"].firstMatch.tap()

        // 05 — the full Library, split into To Dos and Chores.
        app.buttons["All tasks"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["To Do"].waitForExistence(timeout: 10))
        settle()
        attach(framedAppShot(caption: "Everything\nin its place"), "05-library.png")
        app.buttons["Done"].firstMatch.tap()

        // 03 — the nudge payoff: a composed lock screen using the app's real reminder copy. No app
        // grab is needed; the whole "screen" is rendered in SwiftUI.
        attach(renderMarketing(caption: "It nudges until\nyou actually did it") {
            PhoneScreen { LockScreenMock() }
        }, "03-lockscreen.png")
    }

    // MARK: Capture helpers

    /// A framed marketing image wrapping the current device screen grab.
    @MainActor
    private func framedAppShot(caption: String) -> UIImage {
        let grab = XCUIScreen.main.screenshot().image
        return renderMarketing(caption: caption) {
            PhoneScreen { Image(uiImage: grab).resizable().scaledToFill() }
        }
    }

    /// Composes and rasterizes a full 1320×2868 marketing canvas.
    @MainActor
    private func renderMarketing<Screen: View>(caption: String,
                                               @ViewBuilder screen: () -> Screen) -> UIImage {
        let canvas = MarketingCanvas(caption: caption, screen: screen())
        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 1          // the canvas is already sized in device pixels
        renderer.isOpaque = true
        return renderer.uiImage ?? UIImage()
    }

    /// Swipes up until `element` is on screen and tappable (or a few attempts pass), so a target
    /// below the fold can be revealed for both tapping and capture.
    private func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 4) {
        var attempts = 0
        while !element.isHittable && attempts < maxSwipes {
            app.swipeUp()
            attempts += 1
        }
    }

    /// Attaches a PNG that survives the run so `xcresulttool export attachments` can extract it,
    /// using `name` as the exported file name.
    private func attach(_ image: UIImage, _ name: String) {
        guard let data = image.pngData() else {
            XCTFail("Could not encode \(name)")
            return
        }
        let attachment = XCTAttachment(uniformTypeIdentifier: "public.png",
                                       name: name,
                                       payload: data,
                                       userInfo: nil)
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Lets presentation/scroll animations finish before a grab.
    private func settle() {
        Thread.sleep(forTimeInterval: 1.2)
    }
}

// MARK: - Framing (SwiftUI)

/// The dimensions of an iPhone 6.9" App Store screenshot.
private enum Canvas {
    static let width: CGFloat = 1320
    static let height: CGFloat = 2868
}

/// A full marketing screenshot: a soft accent-green wash, a bold headline, and a device-framed
/// screen beneath it.
private struct MarketingCanvas<Screen: View>: View {
    let caption: String
    let screen: Screen

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.82, green: 0.94, blue: 0.85),
                         Color(red: 0.96, green: 0.99, blue: 0.96)],
                startPoint: .top, endPoint: .bottom
            )

            VStack(spacing: 0) {
                Spacer().frame(height: 150)

                Text(caption)
                    .font(.system(size: 100, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.09, green: 0.19, blue: 0.13))
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 1120)

                Spacer(minLength: 80)

                screen

                Spacer(minLength: 70)
            }
        }
        .frame(width: Canvas.width, height: Canvas.height)
    }
}

/// Wraps arbitrary "screen" content in a rounded device shell (clip + edge + shadow). The height is
/// derived from the 6.9" screen aspect so app grabs are shown undistorted.
private struct PhoneScreen<Content: View>: View {
    var width: CGFloat = 1040
    @ViewBuilder let content: () -> Content

    private var height: CGFloat { width * Canvas.height / Canvas.width }

    var body: some View {
        content()
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 64, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 64, style: .continuous)
                    .stroke(Color.black.opacity(0.88), lineWidth: 12)
            )
            .shadow(color: .black.opacity(0.22), radius: 42, x: 0, y: 20)
    }
}

/// A mock iOS lock screen showing the app's real reminder copy, so the "nudge" story is legible
/// without needing to trigger and photograph live notifications.
private struct LockScreenMock: View {
    private struct Nudge {
        let title: String
        let body: String
    }

    // Real notification copy: reminders use "<title>" / "<surfacingReason> · <estimate>", and the
    // morning digest uses "Good morning" / the "…tasks due…" body — see NudgeScheduler.
    private let nudges: [Nudge] = [
        Nudge(title: "Take out the bins", body: "Due today · 5 min"),
        Nudge(title: "Book a dentist appointment", body: "Overdue · 10 min"),
        Nudge(title: "Good morning",
              body: "You have 3 tasks due — take a look at what's on your list for today.")
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.13, blue: 0.10),
                         Color(red: 0.02, green: 0.06, blue: 0.05)],
                startPoint: .top, endPoint: .bottom
            )

            VStack(spacing: 0) {
                Spacer().frame(height: 130)

                Text("Monday 30 August")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(.white.opacity(0.82))

                Text("9:41")
                    .font(.system(size: 176, weight: .bold))
                    .foregroundStyle(.white)

                Spacer().frame(height: 90)

                VStack(spacing: 22) {
                    ForEach(nudges.indices, id: \.self) { index in
                        card(nudges[index])
                    }
                }
                .padding(.horizontal, 40)

                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func card(_ nudge: Nudge) -> some View {
        HStack(alignment: .top, spacing: 20) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.green)
                .frame(width: 72, height: 72)
                .overlay(
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(.white)
                )

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(nudge.title)
                        .font(.system(size: 33, weight: .semibold))
                        .foregroundStyle(.black)
                    Spacer(minLength: 8)
                    Text("now")
                        .font(.system(size: 26))
                        .foregroundStyle(.black.opacity(0.4))
                }
                Text(nudge.body)
                    .font(.system(size: 30))
                    .foregroundStyle(.black.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(26)
        .background(Color.white.opacity(0.96), in: RoundedRectangle(cornerRadius: 36, style: .continuous))
    }
}
