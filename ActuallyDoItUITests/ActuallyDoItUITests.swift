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
/// a curated in-memory store) into each showcase state, grabs the running screen, then composes a
/// marketing image (headline caption + a device-framed screenshot) with SwiftUI's `ImageRenderer`.
/// Each composed image is attached with `.keepAlways`, so a following
/// `xcrun xcresulttool export attachments` lands the final PNGs on disk (see
/// `Scripts/generate_screenshots.sh`).
///
/// The canvas size, caption scale and framing all come from a `DeviceProfile` that is picked
/// automatically from whatever the test is running on: iPhone (1320×2868, portrait), iPad
/// (2064×2752, portrait), or Mac Catalyst (2880×1800, landscape) — the three App Store Connect
/// display sizes for this app. The same UI-driving steps run on all three.
///
/// Capturing the real screens has to happen on a running app (`ImageRenderer` can't rasterize
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
        let profile = detectProfile()
        settle()
        attach(framedAppShot(app: app, profile: profile,
                             caption: "Not overwhelming —\none thing at a time"), "01-focus.png")

        // 04 — the day's board: release the current focus so the "Doing now" hero gives way to a
        // clean Today section (with its progress ring) and the suggested next tasks.
        app.buttons["Can't do this now"].firstMatch.tap()
        settle()
        attach(framedAppShot(app: app, profile: profile,
                             caption: "Just today —\nnothing more"), "04-today.png")

        // 02 — the nudge system: open the pre-seeded, already-Relentless task and scroll to the
        // Nudge-intensity section and its timeline.
        app.staticTexts["Book a dentist appointment"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Task details"].waitForExistence(timeout: 10))
        scrollUntilHittable(app.buttons["Relentless"], in: app)
        settle()
        attach(framedAppShot(app: app, profile: profile,
                             caption: "Reminders that\ndon't quit"), "02-nudges.png")
        app.buttons["Done"].firstMatch.tap()

        // 05 — the full Library, split into To Dos and Chores.
        app.buttons["All tasks"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["To Do"].waitForExistence(timeout: 10))
        settle()
        attach(framedAppShot(app: app, profile: profile,
                             caption: "Everything\nin its place"), "05-library.png")
        app.buttons["Done"].firstMatch.tap()

        // 03 — the nudge payoff: a composed lock screen using the app's real reminder copy. No app
        // grab is needed; the whole "screen" is rendered in SwiftUI. This story is iPhone-specific,
        // so it's skipped on iPad/Mac.
        if profile.includesLockScreen {
            attach(renderMarketing(caption: "It nudges until\nyou actually do it", profile: profile) {
                DeviceScreen(aspect: profile.canvas.width / profile.canvas.height, profile: profile) {
                    LockScreenMock()
                }
            }, "03-lockscreen.png")
        }
    }

    // MARK: Device profile

    /// The App Store display size to compose for, detected from what's actually on screen.
    ///
    /// Mac Catalyst is known at compile time. iPhone vs iPad is told apart by the captured screen's
    /// pixel width rather than `UIDevice.current.userInterfaceIdiom` — the UI-test runner reports
    /// `.phone` even on an iPad (its target is iPhone-family), so we measure the real grab instead.
    @MainActor
    private func detectProfile() -> DeviceProfile {
        #if targetEnvironment(macCatalyst)
        return .mac
        #else
        let pixelWidth = XCUIScreen.main.screenshot().image.cgImage?.width ?? 0
        return pixelWidth >= 1600 ? .iPad : .iPhone
        #endif
    }

    // MARK: Capture helpers

    /// A framed marketing image wrapping the current screen grab.
    ///
    /// On iPhone/iPad we grab the whole device screen (`XCUIScreen.main`) so the pinned 9:41 status
    /// bar is part of the shot; on Mac Catalyst both `XCUIScreen.main` and `app.screenshot()` capture
    /// the whole desktop, so we grab the app's window element instead. The grab's own aspect ratio
    /// drives the frame so the screenshot is never distorted.
    @MainActor
    private func framedAppShot(app: XCUIApplication, profile: DeviceProfile, caption: String) -> UIImage {
        let shot: XCUIScreenshot
        if profile.kind == .mac {
            let window = app.windows.firstMatch
            shot = window.exists ? window.screenshot() : app.screenshot()
        } else {
            shot = XCUIScreen.main.screenshot()
        }
        let grab = shot.image
        let aspect = grab.size.width / max(grab.size.height, 1)
        return renderMarketing(caption: caption, profile: profile) {
            DeviceScreen(aspect: aspect, profile: profile) {
                Image(uiImage: grab).resizable().scaledToFill()
            }
        }
    }

    /// Composes and rasterizes a full marketing canvas at the profile's exact pixel size.
    @MainActor
    private func renderMarketing<Screen: View>(caption: String,
                                               profile: DeviceProfile,
                                               @ViewBuilder screen: () -> Screen) -> UIImage {
        let canvas = MarketingCanvas(caption: caption, profile: profile, screen: screen())
        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 1          // the canvas is already sized in device pixels
        renderer.isOpaque = true
        return renderer.uiImage ?? UIImage()
    }

    /// Swipes up until `element` is on screen and tappable (or a few attempts pass), so a target
    /// below the fold can be revealed for both tapping and capture.
    ///
    /// Swiping targets a concrete scrollable container rather than the whole app: on Mac Catalyst
    /// `app.swipeUp()` has no hit point and throws, whereas a scroll view / collection / table does.
    private func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 6) {
        let scroller: XCUIElement
        if app.scrollViews.firstMatch.exists {
            scroller = app.scrollViews.firstMatch
        } else if app.collectionViews.firstMatch.exists {
            scroller = app.collectionViews.firstMatch
        } else if app.tables.firstMatch.exists {
            scroller = app.tables.firstMatch
        } else {
            scroller = app
        }
        var attempts = 0
        while !element.isHittable && attempts < maxSwipes {
            scroller.swipeUp()
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

// MARK: - Device profiles

private enum DeviceKind { case iPhone, iPad, mac }

/// Everything that varies between the three App Store display sizes: the exact canvas size App Store
/// Connect requires, plus caption scale and framing tuned to look right at that size.
private struct DeviceProfile {
    let kind: DeviceKind
    /// The exact output pixel size (must match an App Store Connect accepted screenshot size).
    let canvas: CGSize
    let captionFontSize: CGFloat
    let captionWidth: CGFloat
    let captionLineSpacing: CGFloat
    let topInset: CGFloat
    let captionToScreenGap: CGFloat
    let bottomInset: CGFloat
    /// The bounding box the device-framed screen is fit into (aspect-preserving).
    let screenBox: CGSize
    let cornerRadius: CGFloat
    let strokeWidth: CGFloat
    /// Whether to emit the iPhone-only composed lock-screen story.
    let includesLockScreen: Bool

    /// iPhone 6.9" — 1320×2868, portrait.
    static let iPhone = DeviceProfile(
        kind: .iPhone,
        canvas: CGSize(width: 1320, height: 2868),
        captionFontSize: 100,
        captionWidth: 1120,
        captionLineSpacing: 6,
        topInset: 150,
        captionToScreenGap: 80,
        bottomInset: 70,
        screenBox: CGSize(width: 1040, height: 1040 * 2868 / 1320),
        cornerRadius: 64,
        strokeWidth: 12,
        includesLockScreen: true
    )

    /// iPad 13" — 2064×2752, portrait.
    static let iPad = DeviceProfile(
        kind: .iPad,
        canvas: CGSize(width: 2064, height: 2752),
        captionFontSize: 132,
        captionWidth: 1760,
        captionLineSpacing: 8,
        topInset: 180,
        captionToScreenGap: 100,
        bottomInset: 110,
        screenBox: CGSize(width: 1560, height: 1900),
        cornerRadius: 56,
        strokeWidth: 14,
        includesLockScreen: false
    )

    /// Mac — 2880×1800, landscape.
    static let mac = DeviceProfile(
        kind: .mac,
        canvas: CGSize(width: 2880, height: 1800),
        captionFontSize: 120,
        captionWidth: 2400,
        captionLineSpacing: 6,
        topInset: 130,
        captionToScreenGap: 70,
        bottomInset: 90,
        screenBox: CGSize(width: 2560, height: 1180),
        cornerRadius: 28,
        strokeWidth: 10,
        includesLockScreen: false
    )
}

// MARK: - Framing (SwiftUI)

/// A full marketing screenshot: a soft accent-green wash, a bold headline, and a device-framed
/// screen beneath it, sized to the given `DeviceProfile`.
private struct MarketingCanvas<Screen: View>: View {
    let caption: String
    let profile: DeviceProfile
    let screen: Screen

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.82, green: 0.94, blue: 0.85),
                         Color(red: 0.96, green: 0.99, blue: 0.96)],
                startPoint: .top, endPoint: .bottom
            )

            VStack(spacing: 0) {
                Spacer().frame(height: profile.topInset)

                Text(caption)
                    .font(.system(size: profile.captionFontSize, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.09, green: 0.19, blue: 0.13))
                    .multilineTextAlignment(.center)
                    .lineSpacing(profile.captionLineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: profile.captionWidth)

                Spacer(minLength: profile.captionToScreenGap)

                screen

                Spacer(minLength: profile.bottomInset)
            }
        }
        .frame(width: profile.canvas.width, height: profile.canvas.height)
    }
}

/// Wraps arbitrary "screen" content in a rounded device shell (clip + edge + shadow). The content is
/// fit — aspect-preserving — into the profile's `screenBox`, using the content's own `aspect`
/// (width / height), so grabs are shown undistorted whether portrait (iPhone/iPad) or landscape (Mac).
private struct DeviceScreen<Content: View>: View {
    let aspect: CGFloat
    let profile: DeviceProfile
    @ViewBuilder let content: () -> Content

    private var size: CGSize {
        let box = profile.screenBox
        var width = box.width
        var height = width / max(aspect, 0.01)
        if height > box.height {
            height = box.height
            width = height * aspect
        }
        return CGSize(width: width, height: height)
    }

    var body: some View {
        let fitted = size
        content()
            .frame(width: fitted.width, height: fitted.height)
            .clipShape(RoundedRectangle(cornerRadius: profile.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: profile.cornerRadius, style: .continuous)
                    .stroke(Color.black.opacity(0.88), lineWidth: profile.strokeWidth)
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
