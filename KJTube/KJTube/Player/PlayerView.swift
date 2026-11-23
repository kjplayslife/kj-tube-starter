import SwiftUI
import UIKit

/// YouTube-mobile-style player without comments, likes, descriptions or recommendations
/// (docs/specs/player.md).
struct PlayerView: View {
    @Environment(AppStore.self) private var store
    /// Takes the player away. It lives on top of the tabs, not in a cover (D165).
    private let onClose: () -> Void
    @Environment(\.scenePhase) private var scenePhase

    @State private var controller: PlayerController
    /// Hidden when a video opens: it just plays, and a tap brings them up (D217).
    @State private var showsControls = false
    /// Set by a ±10 s skip: only the bar and the times show until the controls are next
    /// brought up by a plain tap (D227).
    @State private var barOnly = false
    @State private var scrubPosition: Double?
    /// Where the video was when a finger landed on the seek bar; nil when no finger is on it.
    /// A drag scrubs left or right from here (D130).
    @State private var scrubStart: Double?
    /// True once that finger has moved far enough to count as a drag, not a tap.
    @State private var scrubMoved = false
    /// YouTube's small preview picture for the time under the finger, shown over the video
    /// while the seek bar is dragged (D134).
    @State private var preview = ScrubPreview()
    /// Takes the preview away after the finger lifts, once the video has caught up.
    @State private var previewEnd: Task<Void, Never>?
    /// The longest the preview waits for the video to catch up after the finger lifts.
    static let previewMaxWait: TimeInterval = 4
    @State private var skipFlash: SkipFlash?
    /// Looked up once: creators don't change while the player is open.
    @State private var creators: [String: CreatorInfo] = [:]
    /// The last tap on a side of the video, to spot a double-tap.
    @State private var lastTap: (zone: Int, at: Date)?
    /// The last ±10 s skip. While it's fresh, more taps on that side keep skipping and the
    /// controls stay up (D129).
    @State private var lastSkip: (zone: Int, at: Date, id: UUID)?
    /// True while the right side is held down (2×), and for a moment after, so lifting the
    /// finger doesn't also count as a tap.
    @State private var holdingRight = false
    @GestureState private var holdPressed = false
    /// The soft color behind the top of the player, taken from the thumbnail (D76).
    @State private var glow: Color?
    /// How far the video has been pulled down by a swipe; it follows the finger (D78) and
    /// shrinks into a small player at the bottom on the way, like YouTube (D164).
    @State private var pullDown: CGFloat = 0
    /// How far down the whole page starts when it opens, before it slides up (D138).
    @State private var openSlide: CGFloat
    /// How far the video's top travels from its place to the small player's spot.
    private let pullTravel: CGFloat
    /// True for the last moment of a swipe away, while the small player fades out.
    @State private var leaving = false
    /// True while the video is the small player in the corner, still playing (D165).
    @State private var minimized = false
    /// The page under the video is light in light mode (D224). The video, its controls and
    /// full screen are always dark.
    @Environment(\.colorScheme) private var colorScheme
    private var pageColor: Color { colorScheme == .light ? .white : .black }
    /// How far the small player sits sideways from the bottom right corner: 0 in a right
    /// corner, `miniLeftX` in a left one, anything in between or past while a finger moves it
    /// (D186). Its height on the screen is `pullDown`: `pullTravel` at the bottom,
    /// `miniTopY` at the top.
    @State private var miniSlide: CGFloat = 0
    /// Where the small player was when a finger landed on it; nil with no finger on it.
    @State private var miniDragStart: CGSize?
    /// The small player's buttons show only while it rests in its spot: not on the way down,
    /// and gone the moment it starts back up.
    @State private var miniButtonsShown = false
    /// The small player the video shrinks into, measured from KJ's recording of YouTube: a
    /// rounded card 45% of the screen wide, in the bottom right corner just above the tab bar.
    static let miniWidthShare: CGFloat = 0.45
    static let miniMargin: CGFloat = 8
    /// The gap between the small player and the top of the tab bar (KJ: 8 was a little close).
    static let miniBottomGap: CGFloat = 16
    static let miniRadius: CGFloat = 10
    static let tabBarHeight: CGFloat = 49
    private let miniHeight: CGFloat
    /// Gap between the Skip Ad button and the right edge of the picture.
    static let skipAdInset: CGFloat = 12
    /// Counts Skip Ad taps, for the light haptic.
    @State private var skipAdTaps = 0
    static let doubleTapWindow: TimeInterval = 0.3
    /// How dark the Skip Ad and Next video pills are (D132, D219). The ±10 s and 2× chips have
    /// the same blurred gray as the other controls now (D227).
    static let chipShade: Double = 0.45
    /// The play/pause circle: about 20% smaller than the first one (was 64), still an easy tap.
    static let playButtonSize: CGFloat = 52
    /// How long the controls stay up after the last ±10 s skip, before they fade out (D129).
    static let skipHold: TimeInterval = 1
    /// How long the controls take to fade in or out. YouTube's is 0.2 s each way (timed from a
    /// recording, D133); KJ wanted ours quicker still (D211).
    static let controlsFade: TimeInterval = 0.12
    /// Coming up on a touch they are quicker still: there almost at once, but still a fade (D215).
    static let controlsFadeIn: TimeInterval = 0.05
    /// What sits behind the times and the full screen icon, now that the dark shade along the
    /// bottom is gone (D211): see-through and glossy like YouTube's, the video blurred behind it.
    static let timeChip = Material.ultraThinMaterial
    /// A touch of white over the blur, so it reads as gray, not black. Was 0.14; KJ wanted it a
    /// little darker (D214).
    static let timeChipLift: Double = 0.05
    /// A little under full, so a bit more of the video comes through the blur (D214). Much
    /// lower and the sharp picture shows instead of the blurred one (0.7 was tried).
    static let timeChipStrength: Double = 0.88
    /// A soft shadow under the controls' text and icons, like YouTube's, so they read on white.
    static let textShadow = Color.black.opacity(0.45)
    /// How far past the picture's sides the full screen controls reach (D213).
    static let fullscreenOverhang: CGFloat = 22
    /// How far the controls sit in from the picture's edges: closer in full screen (D211).
    static func controlsInset(fullscreen: Bool) -> CGFloat { fullscreen ? 6 : 12 }
    /// Which controls show (D227). `bar` is the seek bar and the times; `rest` is everything
    /// else. While skipping ±10 s (`barOnly`) only the bar shows. While holding for 2×
    /// (`boosted`) nothing shows but the 2× chip and the thin white line.
    static func controlParts(shown: Bool, barOnly: Bool, boosted: Bool) -> (bar: Bool, rest: Bool) {
        (bar: shown && !boosted, rest: shown && !barOnly && !boosted)
    }
    /// How long the glow waits, so it never lands in the middle of the opening slide (D163).
    static let openSettle: Duration = .milliseconds(450)

    struct SkipFlash: Equatable {
        let forward: Bool
        let id = UUID()
    }

    /// `openFrom` is the top of the tapped card's picture on screen. The player starts there and
    /// slides up to its place, like YouTube, instead of rising from the bottom edge (D138).
    init(store: AppStore, start: HomeEntry, openFrom: CGFloat? = nil, onClose: @escaping () -> Void) {
        self.onClose = onClose
        _controller = State(initialValue: PlayerController(store: store, player: YouTubeIFramePlayer.shared, start: start,
                                                                 leavesInboxAtWatchedLine: !AppConfig.isPublic))
        let screen = UIScreen.main.bounds.height
        let insets = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.keyWindow?.safeAreaInsets ?? .zero
        let start = (openFrom ?? screen * 0.4) - insets.top
        _openSlide = State(initialValue: min(max(start, 0), screen))
        miniHeight = UIScreen.main.bounds.width * Self.miniWidthShare * 9 / 16
        pullTravel = max(screen - insets.top - insets.bottom - Self.tabBarHeight - Self.miniBottomGap - miniHeight, 1)
    }

    /// 0 with the video in its place, 1 once it has shrunk to the small player (D164).
    /// Always 0 in the public version: it has no small player, the page just slides down (D179).
    /// The small player stays small wherever it is dragged (D186).
    private var shrink: CGFloat {
        if AppConfig.isPublic { return 0 }
        return minimized ? 1 : min(max(pullDown, 0) / pullTravel, 1)
    }
    /// The page under the video is gone in the first bit of the drag, so only the video is left
    /// over the Inbox. A slow fade left a see-through page hanging over it.
    private var pageFade: CGFloat { 1 - min(shrink / 0.12, 1) }

    var body: some View {
        GeometryReader { geo in
            let fullscreen = geo.size.width > geo.size.height
            Group {
                if fullscreen, AppConfig.isPublic {
                    publicFullscreen
                } else if fullscreen {
                    videoArea(fullscreen: true)
                        .ignoresSafeArea()
                } else {
                    let videoHeight = geo.size.width * 9 / 16
                    // Only a transform, so the web view is never laid out again mid-drag.
                    let scale = 1 - shrink * (1 - miniHeight / videoHeight)
                    VStack(spacing: 0) {
                        videoArea(fullscreen: false)
                            .aspectRatio(16 / 9, contentMode: .fit)
                            // Rounded while it slides open, and as it shrinks into the small card.
                            .clipShape(.rect(cornerRadius: pullDownRadius + Self.miniRadius * shrink / scale))
                            .layoutPriority(1) // full width even when a huge title needs room
                            // The bar sits half on the picture and half below it, so its knob is
                            // whole (D212). Gone while the video shrinks into the small player.
                            .overlay(alignment: .bottom) {
                                if !AppConfig.isPublic {
                                    seekBar(onEdge: true)
                                        .animation(.easeOut(duration: Self.controlsFade), value: controller.boosted)
                                        .offset(y: 15)
                                        .opacity(pageFade)
                                        .allowsHitTesting(shrink == 0)
                                }
                            }
                            .scaleEffect(scale, anchor: .topTrailing) // shrinks toward the right
                            .overlay(alignment: .topTrailing) {
                                if minimized {
                                    miniControls
                                        .frame(width: geo.size.width * scale, height: videoHeight * scale)
                                }
                            }
                            .offset(x: -Self.miniMargin * shrink + miniSlide)
                            .zIndex(1)
                        if AppConfig.isPublic { publicBar }
                        belowVideo
                            .overlay(alignment: .top) { if AppConfig.isPublic { noticeBanner } }
                            .background(pageColor)
                            .compositingGroup() // fades as one sheet, so the Inbox never shows through the text
                            .opacity(pageFade)
                            .allowsHitTesting(pageFade > 0) // the Inbox takes the touches once it shows
                    }
                }
            }
            // Turning the phone rebuilds the seek bar. A touch on the old one never "ends",
            // which would leave the clock showing where that touch was.
            .onChange(of: fullscreen) { scrubPosition = nil; scrubStart = nil; endPreview() }
            .statusBarHidden(fullscreen)
            .persistentSystemOverlays(fullscreen ? .hidden : .automatic)
            .background(alignment: .top) {
                if !fullscreen { ambientGlow(videoHeight: geo.size.width * 9 / 16).opacity(pageFade) }
            }
        }
        // The Inbox shows as soon as the video starts to shrink. The black reaches under the status
        // bar too: without that, only the see-through glow was there, so a list that had scrolled
        // up behind the player (a turn of the phone does that) showed through above the video.
        .background { pageColor.opacity(pageFade).ignoresSafeArea().allowsHitTesting(pageFade > 0) }
        // A mask that ignores the safe area: clipping to the view's bounds cut off the full-screen
        // video under the camera and home bar, so Inbox showed at the edges.
        .mask { RoundedRectangle(cornerRadius: pullDownRadius).ignoresSafeArea() }
        .offset(y: openSlide + pullDown)
        .task(id: controller.current.id) {
            // Off the main thread, and not until the opening slide is over: working the color
            // out mid-slide made the slide stutter (D163).
            try? await Task.sleep(for: Self.openSettle)
            let image = await ImageCache.shared.image(from: Thumbnail.urls(controller.current.id))
            let color = await Task.detached(priority: .utility) { image.flatMap(AmbientColor.of) }.value
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.6)) { glow = color }
        }
        .onAppear {
            creators = store.creatorInfoByID()
            AppDelegate.allowsLandscape = true
            UIApplication.shared.isIdleTimerDisabled = true // screen stays awake (⚙︎)
            controller.start()
            // The slide starts once the page's first picture is on screen. Started here, its
            // clock ran while the page was still being built, so it showed as a few jumps (D163).
            Task {
                try? await Task.sleep(for: .milliseconds(1))
                withAnimation(.spring(duration: 0.28, bounce: 0)) { openSlide = 0 } // timed from YouTube (D138)
            }
        }
        .onDisappear {
            controller.stop()
            UIApplication.shared.isIdleTimerDisabled = false
            AppDelegate.allowsLandscape = false
            Orientation.request(.portrait)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { controller.pause() } // D36
            scrubPosition = nil // leaving the app can cut a seek-bar drag off too
            scrubStart = nil
            endPreview()
        }
        // A seek-bar drag that another gesture cut off never "ends", which froze the clock.
        .onChange(of: controller.current.id) {
            scrubPosition = nil; scrubStart = nil; endPreview()
            // The next video opens like the first: no controls until a tap (D217).
            lastSkip = nil
            showsControls = false
            barOnly = false
        }
        // The seek bar goes away with the controls, which would cut a drag off the same way.
        .onChange(of: showsControls) { _, shown in
            if !shown { scrubPosition = nil; scrubStart = nil; endPreview() }
        }
        .task(id: controller.ending) {
            guard controller.ending == .allDone else { return }
            try? await Task.sleep(for: .seconds(3)) // D37
            onClose()
        }
        // A tap in the Skip Ad gap goes to YouTube, not to our touch layer. It still brings the
        // controls up, so the full screen button is there for the next tap.
        .onReceive(NotificationCenter.default.publisher(for: WKWebViewContainer.tapped)) { _ in
            // In the public version every tap is YouTube's own business (D179).
            guard !minimized, !AppConfig.isPublic else { return }
            if !showsControls { setControls(true) }
            // YouTube takes that tap as "pause". If the video was playing and stops right after,
            // start it again: the tap was for our controls, not for pausing.
            guard controller.state == .playing else { return }
            Task {
                // YouTube's "paused" can take a moment to arrive, so look twice.
                for wait in [350, 500] {
                    try? await Task.sleep(for: .milliseconds(wait))
                    if controller.state == .paused { return controller.togglePlay() }
                }
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: controller.current.id)
        .sensoryFeedback(.success, trigger: controller.ending == .allDone) { _, done in done }
        .alert("Play next video?", isPresented: switchAlertShown) {
            Button("Play") { controller.confirmSwitch() }
            Button("Cancel", role: .cancel) { controller.pendingSwitch = nil }
        } message: {
            Text("You won't be able to come back to this one.")
        }
    }

    private var switchAlertShown: Binding<Bool> {
        Binding(get: { controller.pendingSwitch != nil }, set: { if !$0 { controller.pendingSwitch = nil } })
    }

    // MARK: - Swipe down

    /// Corners are round while the page slides open, like a card (D86, D138).
    private var pullDownRadius: CGFloat { min(openSlide * 0.4, 32) }

    /// The video follows the finger down and shrinks. Let go far enough (or flick) and it becomes
    /// the small player, still playing (D165); otherwise it springs back up (D78). On the small
    /// player, a drag up opens it again and a drag down closes it. Global coordinates, since
    /// the view moves.
    private func swipeDown(enabled: Bool) -> some Gesture {
        DragGesture(minimumDistance: 20, coordinateSpace: .global)
            .onChanged { value in
                guard enabled, !leaving, !minimized else { return }
                setControls(false) // YouTube's go away as the drag starts
                pullDown = min(max(value.translation.height, 0), pullTravel)
            }
            .onEnded { value in
                guard enabled, !leaving, !minimized else { return }
                if value.translation.height > 200 || value.predictedEndTranslation.height > 500 {
                    if AppConfig.isPublic { slideAway() } else { minimize() }
                } else {
                    expand()
                }
            }
    }

    /// The public version has no small player: pulled down far enough, the page slides off the
    /// bottom and the video stops (D179).
    private func slideAway() {
        guard !leaving else { return }
        leaving = true
        withAnimation(.spring(duration: 0.25, bounce: 0)) {
            pullDown = UIScreen.main.bounds.height
        } completion: {
            onClose()
        }
    }

    // MARK: - Public version (D179)

    /// Close and full screen, in a row under the video. In the public version nothing of ours
    /// may sit on top of YouTube's player, so these live outside it.
    private var publicBar: some View {
        // A faint wash of the video's own color (the glow above the player), fading into the page,
        // so the bar reads as something to pull down (KJ, 2026-11-16).
        let tint = glow ?? Color(white: 0.5)
        return HStack {
            Button { slideAway() } label: { // slides down like a pull, not a blink (KJ, 2026-11-16)
                Label("Close", systemImage: "chevron.down")
                    .frame(minHeight: 44)
                    .contentShape(.rect)
            }
            Spacer()
            Button { Orientation.request(.landscapeRight) } label: {
                Label("Full screen", systemImage: "arrow.up.left.and.arrow.down.right")
                    .frame(minHeight: 44)
                    .contentShape(.rect)
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.primary)
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .overlay {
            Image(systemName: "chevron.compact.down") // the grabber
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary.opacity(0.4))
                .accessibilityHidden(true)
        }
        .background {
            LinearGradient(colors: [tint.opacity(0.32), tint.opacity(0.06)], startPoint: .top, endPoint: .bottom)
        }
        .background(pageColor)
        .contentShape(.rect)
        .gesture(swipeDown(enabled: true))
    }

    /// Full screen in the public version: the video at its own 16:9 shape in the middle, and
    /// the way back out in the black strip beside it, never on the picture.
    private var publicFullscreen: some View {
        HStack(spacing: 0) {
            Color.black
            videoArea(fullscreen: true)
                .aspectRatio(16 / 9, contentMode: .fit)
                .layoutPriority(1)
            Color.black.overlay(alignment: .bottom) {
                Button { Orientation.request(.portrait) } label: {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.35)) // dim, so it doesn't pull the eye from the video
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Exit full screen")
                .padding(.bottom, 24)
            }
        }
        .background(.black)
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
    }

    /// Settles into the small player in the bottom right corner and keeps playing (D165).
    private func minimize() {
        AppDelegate.allowsLandscape = false // the small player stays upright
        withAnimation(.spring(duration: 0.25, bounce: 0)) {
            pullDown = pullTravel
            minimized = true
        } completion: {
            if minimized { miniButtonsShown = true } // only once it has come to rest
        }
    }

    /// Back up to the full player, from whichever corner the small one was in.
    private func expand() {
        AppDelegate.allowsLandscape = true
        miniButtonsShown = false // at once, so they never ride along as the video grows
        withAnimation(.spring(duration: 0.3, bounce: 0)) {
            pullDown = 0
            miniSlide = 0
            minimized = false
        }
    }

    /// The small player slides off the screen past `edge` and the video stops: the X, or a
    /// flick toward an edge (D186). Only a slide, with no fade: fading a playing video made it
    /// stutter. It leaves at the finger's own speed, so there is no hitch as it's let go.
    private func leave(_ edge: Edge? = nil, speed: CGFloat = 0) {
        guard !leaving else { return }
        leaving = true
        // The X sends it off the side it is nearest.
        let edge = edge ?? (miniSlide < miniLeftX / 2 ? .leading : .trailing)
        let screen = UIScreen.main.bounds
        let from: CGFloat, to: CGFloat
        switch edge {
        case .trailing: (from, to) = (miniSlide, miniWidth + Self.miniMargin + 24)
        case .leading: (from, to) = (miniSlide, -(screen.width + 24))
        case .bottom: (from, to) = (pullDown, screen.height)
        case .top: (from, to) = (pullDown, -(miniHeight + 120))
        }
        let left = max(abs(to - from), 1)
        withAnimation(.interpolatingSpring(duration: 0.3, bounce: 0, initialVelocity: max(speed, 0) / left)) {
            if edge == .leading || edge == .trailing { miniSlide = to } else { pullDown = to }
        } completion: {
            onClose()
        }
    }

    // MARK: - Small player

    private var miniWidth: CGFloat { UIScreen.main.bounds.width * Self.miniWidthShare }
    /// `miniSlide` in a left corner: the same gap from the left edge as from the right.
    private var miniLeftX: CGFloat { -(UIScreen.main.bounds.width - miniWidth - 2 * Self.miniMargin) }
    /// `pullDown` in a top corner, just under the status bar.
    private var miniTopY: CGFloat { Self.miniMargin }

    /// The small player follows the finger anywhere, one to one from the first touch. Let go
    /// and it glides to the nearest corner, counting the flick. Pushed out past the side it
    /// started on, far enough or with a flick, it slides off that edge and closes (D186,
    /// changes D167).
    private var miniDrag: some Gesture {
        // No dead zone: with one, it sat still and then jumped, which felt like it had to be
        // dragged hard.
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                guard !leaving, minimized else { return }
                let start = miniDragStart ?? CGSize(width: miniSlide, height: pullDown)
                miniDragStart = start
                miniSlide = start.width + value.translation.width
                pullDown = start.height + value.translation.height
            }
            .onEnded { value in
                miniDragStart = nil
                // A tap opens the full player, and the X closes it: the drag has no say then.
                guard !leaving, minimized else { return }
                let spot = MiniSpot(x: miniSlide, y: pullDown)
                let flick = CGSize(width: value.predictedEndTranslation.width - value.translation.width,
                                   height: value.predictedEndTranslation.height - value.translation.height)
                let bounds = MiniSpot.Bounds(leftX: miniLeftX, topY: miniTopY, bottomY: pullTravel,
                                             width: miniWidth, height: miniHeight)
                switch spot.landing(flick: flick, in: bounds) {
                case .off(let edge):
                    let v = value.velocity
                    let speed: CGFloat = switch edge {
                    case .trailing: v.width
                    case .leading: -v.width
                    case .bottom: v.height
                    case .top: -v.height
                    }
                    leave(edge, speed: speed)
                case .corner(let x, let y):
                    // A soft landing: quick, with the smallest bounce.
                    withAnimation(.spring(duration: 0.35, bounce: 0.12)) {
                        miniSlide = x
                        pullDown = y
                    }
                }
            }
    }

    /// On the small player, like YouTube's: a dark see-through round button in each top corner,
    /// play/pause on the left and X on the right. A tap anywhere else opens the full player.
    private var miniControls: some View {
        HStack(alignment: .top, spacing: 0) {
            miniButton(controller.isPlaying ? "pause.fill" : "play.fill",
                       label: controller.isPlaying ? "Pause" : "Play") { controller.togglePlay() }
            Spacer(minLength: 0)
            miniButton("xmark", label: "Close player") { leave() }
        }
        .opacity(miniButtonsShown ? 1 : 0)
        // A quick fade in once it rests; no fade out at all.
        .animation(miniButtonsShown ? .easeOut(duration: 0.15) : nil, value: miniButtonsShown)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(.rect)
        .onTapGesture { expand() }
        // Alongside the tap and the two buttons, so a slide can start anywhere on the card,
        // even on a button.
        .simultaneousGesture(miniDrag)
    }

    /// A 28 pt dark circle, 6 pt in from the corner, inside an easy 44 pt touch area.
    private func miniButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(.black.opacity(0.55), in: .circle)
                .padding(6)
                .frame(width: 44, height: 44, alignment: .top)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Ambient glow

    /// A soft wash of the video's color in the status bar area and just under the video, like
    /// YouTube's ambient mode (D76).
    private func ambientGlow(videoHeight: CGFloat) -> some View {
        LinearGradient(
            stops: [
                .init(color: (glow ?? .clear).opacity(0.55), location: 0),
                .init(color: (glow ?? .clear).opacity(0.25), location: 0.6),
                .init(color: .clear, location: 1),
            ],
            startPoint: .top, endPoint: .bottom
        )
        .frame(height: videoHeight + 140)
        .blur(radius: 30)
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
    }

    // MARK: - Video + controls

    @ViewBuilder
    private func videoArea(fullscreen: Bool) -> some View {
        if AppConfig.isPublic {
            // YouTube's player and nothing else: no cover, no controls, no buttons of ours (D179).
            // No gesture of ours on it either, so every touch reaches YouTube's controls.
            PlayerSurface()
                .background(.black)
        } else {
            // Always dark: its buttons and labels sit on the picture (D224).
            privateVideoArea(fullscreen: fullscreen)
                .environment(\.colorScheme, .dark)
        }
    }

    private func privateVideoArea(fullscreen: Bool) -> some View {
        ZStack {
            PlayerSurface()
            if !controller.hasStarted { poster }
            if let frame = preview.image {
                // Small and stretched to fit, so it's soft, like YouTube's.
                Image(uiImage: frame)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.black)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            tapLayer
            // Always there, only see-through while hidden (D216). Building them fresh on every
            // touch (the times, the menus, the blurred glass) cost a few frames before the fade
            // could even start, which felt like a delay.
            // Each part fades by itself: while skipping only the bar and the times are up, and
            // while holding for 2× nothing is (D227).
            controls(fullscreen: fullscreen)
                .allowsHitTesting(showsControls)
                .accessibilityHidden(!parts.bar)
                .animation(.easeOut(duration: Self.controlsFade), value: controller.boosted)
            if let flash = skipFlash { skipFeedback(flash) }
            if controller.boosted { boostBadge }
            if fullscreen { fullscreenPlayNext }
            skipAdCorner(fullscreen: fullscreen)
            endingOverlay
        }
        .background(.black)
        .clipped()
        .overlay(alignment: .top) { noticeBanner }
        // Controls sit on top of a fixed-size video, so they can't grow like body text.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .gesture(swipeDown(enabled: !fullscreen))
        .task(id: autoHideKey) {
            // Not while a finger is on the seek bar: hiding the bar mid-drag cut the drag off, so
            // it never ended and the preview picture stayed over the video.
            guard showsControls, controller.isPlaying, scrubStart == nil else { return }
            // After a skip they go sooner, with a slow fade (D129).
            let afterSkip = lastSkip != nil
            try? await Task.sleep(for: .seconds(afterSkip ? Self.skipHold : 3))
            guard !Task.isCancelled else { return }
            lastSkip = nil
            // On their own they go as fast as on a tap, like YouTube's (measured: about 0.2 s each way).
            withAnimation(.easeOut(duration: afterSkip ? 0.8 : Self.controlsFade)) { showsControls = false }
        }
    }

    private var parts: (bar: Bool, rest: Bool) {
        Self.controlParts(shown: showsControls, barOnly: barOnly, boosted: controller.boosted)
    }

    private var autoHideKey: String {
        "\(showsControls)-\(controller.isPlaying)-\(controller.state == .ended)-\(scrubPosition == nil)-\(lastSkip?.id.uuidString ?? "")"
    }

    /// Single tap shows/hides controls (the middle also plays/pauses); double-tap the left/right
    /// third skips 10 s.
    private var tapLayer: some View {
        HStack(spacing: 0) {
            tapZone(0, skip: -PlayerController.skipInterval)
            tapZone(1, skip: nil)
            // While our own Skip Ad button is up the corner is ours: a tap that just misses the
            // button must not fall through to YouTube, which takes it as "pause" (D195).
            tapZone(2, skip: PlayerController.skipInterval, leavesAdCorner: controller.activeAd == nil)
                .simultaneousGesture(holdForSpeed)
        }
        .onChange(of: holdPressed) { _, pressed in
            if pressed {
                holdingRight = true
                controller.boosted = true
                setControls(false) // and they stay away after letting go (D227)
            } else {
                controller.boosted = false
                Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    holdingRight = false
                }
            }
        }
    }

    /// Press and hold the right side: 2× until you let go (D66).
    private var holdForSpeed: some Gesture {
        LongPressGesture(minimumDuration: 0.4)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .updating($holdPressed) { value, state, _ in
                if case .second(true, _) = value { state = true }
            }
    }

    /// `leavesAdCorner` cuts the bottom-right corner out of the touch area so "Skip ad" works (D51).
    /// A tap shows the controls at once (D62). A double-tap on a side skips 10 s and keeps the
    /// bar and the times up, steady, with the other controls gone (D227), while more taps keep
    /// skipping; `skipHold` after the last one they fade out (D129). A single tap never waits for a possible second tap, to show or to hide.
    private func tapZone(_ zone: Int, skip: TimeInterval?, leavesAdCorner: Bool = false) -> some View {
        Color.clear
            .contentShape(leavesAdCorner ? AnyShape(TouchLayerShape()) : AnyShape(Rectangle()), eoFill: true)
            .onTapGesture {
                guard !holdingRight else { return } // the end of a 2× hold, not a tap
                let now = Date.now
                let doubleTap = lastTap.map { $0.zone == zone && now.timeIntervalSince($0.at) < Self.doubleTapWindow } ?? false
                let stillSkipping = lastSkip.map { $0.zone == zone && now.timeIntervalSince($0.at) < Self.skipHold } ?? false
                if let skip, doubleTap || stillSkipping {
                    lastTap = nil
                    lastSkip = (zone, now, UUID()) // restarts the wait before the controls fade
                    controller.skip(by: skip)
                    skipFlash = SkipFlash(forward: skip > 0)
                    setControls(true, barOnly: true)
                    return
                }
                lastSkip = nil
                if skip == nil {
                    lastTap = nil
                    if !controller.isPlaying || showsControls {
                        // The middle is the play button now that ours is gone (D70): it plays when
                        // paused, and pauses once the controls are showing.
                        controller.togglePlay()
                        setControls(true)
                    } else {
                        setControls(!showsControls)
                    }
                } else {
                    lastTap = (zone, now)
                    setControls(!showsControls)
                }
            }
    }

    /// A tap fades the controls in and out, like YouTube's. It starts at once and stays quick (D133).
    /// `barOnly` brings up just the bar and the times, for a skip (D227). Hiding leaves it as it
    /// is, so the other controls don't flash back while the bar fades out.
    private func setControls(_ shown: Bool, barOnly only: Bool = false) {
        guard shown != showsControls || (shown && only != barOnly) else { return }
        let fade = shown && !showsControls ? Self.controlsFadeIn : Self.controlsFade
        withAnimation(.easeOut(duration: fade)) {
            showsControls = shown
            if shown { barOnly = only }
        }
    }

    private func controls(fullscreen: Bool) -> some View {
        let bar: Double = parts.bar ? 1 : 0
        let rest: Double = parts.rest ? 1 : 0
        return ZStack {
            // Shade only the top edge so the buttons read, not the whole video (D65). The bottom
            // has no shade: the times sit on light gray instead (D211).
            VStack(spacing: 0) {
                LinearGradient(colors: [.black.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 72)
                Spacer(minLength: 0)
            }
            .opacity(rest)
            .allowsHitTesting(false)
            VStack {
                // Every button gets a 44 × 44 pt tap area; the negative padding keeps the icons
                // where they were.
                HStack(spacing: 4) {
                    Button { onClose() } label: {
                        Image(systemName: "chevron.down").font(.title3.weight(.semibold))
                            .frame(width: 44, height: 44)
                            .contentShape(.rect)
                    }
                    Spacer()
                    speedMenu
                    Button { controller.captions.toggle() } label: {
                        Image(systemName: controller.captions ? "captions.bubble.fill" : "captions.bubble")
                            .font(.body.weight(.semibold))
                            .frame(width: 44, height: 44)
                            .contentShape(.rect)
                    }
                    .accessibilityLabel(controller.captions ? "Captions on" : "Captions off")
                }
                .shadow(color: Self.textShadow, radius: 1.5, y: 0.5)
                .padding(.horizontal, -10)
                .padding(.top, -10)
                .opacity(rest)
                .allowsHitTesting(parts.rest)
                .accessibilityHidden(!parts.rest)
                Spacer()
                // Like YouTube's, upright and in full screen (D212, D213): both times in one pill
                // on the left, full screen on the right. Upright the bar itself is down on the
                // picture's bottom edge; in full screen it runs under this row.
                HStack {
                    Text("\(Format.clock(scrubPosition ?? controller.position)) / \(Format.clock(controller.duration))")
                        .shadow(color: Self.textShadow, radius: 1.5, y: 0.5)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background { GlassChip(shape: Capsule()) }
                        .opacity(bar)
                    Spacer()
                    Group {
                        muteButton
                        fullscreenButton(fullscreen: fullscreen)
                    }
                    .opacity(rest)
                    .allowsHitTesting(parts.rest)
                    .accessibilityHidden(!parts.rest)
                }
                .font(.footnote.weight(.medium).monospacedDigit())
                .padding(.horizontal, fullscreen ? 0 : -6)
                if fullscreen {
                    seekBar()
                        // Right under the row and well clear of the bottom edge, where the home
                        // gesture lives: a drag on the bar closed the app by accident (D90, D214).
                        .padding(.top, -8)
                        .padding(.bottom, 34)
                        .opacity(bar)
                }
            }
            .padding(Self.controlsInset(fullscreen: fullscreen))
            playPauseButton
                .opacity(rest)
                .allowsHitTesting(parts.rest)
                .accessibilityHidden(!parts.rest)
        }
        .modifier(AroundPicture(on: fullscreen))
        .foregroundStyle(.white)
        .buttonStyle(.plain)
        .defersSystemGestures(on: fullscreen ? .bottom : [])
    }

    /// A round glossy button. Its touch area runs to the picture's right edge and, upright, down
    /// to its bottom edge, so it also covers the Skip Ad gap (D51) while the controls show. The
    /// paddings only grow the touch area: the matching negative ones keep everything in place.
    private func fullscreenButton(fullscreen: Bool) -> some View {
        let toRight: CGFloat = 6 // what is left to the picture's right edge, upright or not
        let toBottom: CGFloat = fullscreen ? 0 : 12 // in full screen the bar is right below
        return Button {
            Orientation.request(fullscreen ? .portrait : .landscapeRight)
        } label: {
            Image(systemName: fullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                .font(.body.weight(.semibold))
                .shadow(color: Self.textShadow, radius: 1.5, y: 0.5)
                .frame(width: 44, height: 44)
                .background { GlassChip(shape: Circle()).padding(4) }
                .padding(.trailing, -4)
            .environment(\.colorScheme, .dark)
            .padding(.leading, 4)
            .padding(.top, 10)
            .padding(.trailing, toRight)
            .padding(.bottom, toBottom)
            .contentShape(.rect)
        }
        .padding(.leading, -4)
        .padding(.top, -10)
        .padding(.trailing, -toRight)
        .padding(.bottom, -toBottom)
        .accessibilityLabel(fullscreen ? "Exit full screen" : "Full screen")
    }

    /// Takes the preview away. After a drag it waits until the video's picture is at the new
    /// spot: clearing it sooner showed the old spot for a moment, then a jump (D134).
    private func endPreview(whenSeekLands: Bool = false) {
        previewEnd?.cancel()
        guard whenSeekLands, preview.image != nil else { return preview.clear() }
        let before = controller.seeksLanded
        previewEnd = Task {
            let deadline = Date.now.addingTimeInterval(Self.previewMaxWait)
            while controller.seeksLanded == before, Date.now < deadline {
                try? await Task.sleep(for: .milliseconds(30))
                guard !Task.isCancelled else { return }
            }
            try? await Task.sleep(for: .milliseconds(120)) // one more beat for the frame to be drawn
            guard !Task.isCancelled else { return }
            preview.clear()
        }
    }

    /// The seek bar, like YouTube's (D130): a drag that starts anywhere on the bar moves the time
    /// left or right from where it is, without jumping to the finger. A plain tap jumps there.
    ///
    /// `onEdge` is the upright player's bar (D212): a thin line along the picture's bottom edge
    /// that is always there, like YouTube's. White while the controls are hidden; red, with its
    /// knob, and draggable once they show.
    private func seekBar(onEdge: Bool = false) -> some View {
        let resting = onEdge && !parts.bar
        return GeometryReader { geo in
            let knob: CGFloat = 14
            let travel = max(geo.size.width - knob, 1) // the knob stays inside the bar
            let duration = max(controller.duration, 1)
            let shown = min(max(scrubPosition ?? controller.position, 0), duration)
            let x = travel * shown / duration
            ZStack(alignment: .leading) {
                if onEdge {
                    Rectangle().fill(.white.opacity(0.3)).frame(height: 2)
                    Rectangle().fill(resting ? Color.white : Color.red).frame(width: x + knob / 2, height: 2)
                    Circle().fill(.red).frame(width: knob, height: knob).offset(x: x).opacity(resting ? 0 : 1)
                } else {
                    Capsule().fill(.white.opacity(0.3)).frame(height: 4)
                    Capsule().fill(.red).frame(width: x + knob / 2, height: 4)
                    Circle().fill(.white).frame(width: knob, height: knob).offset(x: x)
                }
            }
            .frame(maxHeight: .infinity)
            // Easier to hit than it looks: the touch area reaches past the bar.
            .contentShape(Rectangle().inset(by: -8))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        if scrubStart == nil {
                            scrubStart = controller.position
                            scrubMoved = false
                            scrubPosition = controller.position // also keeps the controls up
                            previewEnd?.cancel()
                            preview.warm(controller.storyboard)
                        }
                        if abs(drag.translation.width) > 6 { scrubMoved = true }
                        guard scrubMoved, let start = scrubStart else { return }
                        let time = min(max(start + drag.translation.width / travel * duration, 0), duration)
                        scrubPosition = time
                        preview.show(time: time, in: controller.storyboard)
                    }
                    .onEnded { drag in
                        guard scrubStart != nil else { return } // cut off (rotated, left the app)
                        let tapped = (drag.location.x - knob / 2) / travel * duration
                        let target = scrubMoved ? (scrubPosition ?? controller.position) : tapped
                        controller.seek(to: min(max(target, 0), duration))
                        scrubPosition = nil
                        scrubStart = nil
                        endPreview(whenSeekLands: true)
                    }
            )
        }
        .frame(height: 30)
        // Hidden controls: the line only shows the time, so a tap near the bottom never seeks.
        .allowsHitTesting(!resting)
        .accessibilityElement()
        .accessibilityLabel("Seek bar")
        .accessibilityValue(Format.clock(scrubPosition ?? controller.position))
        .accessibilityAdjustableAction { direction in
            let step = PlayerController.skipInterval
            controller.skip(by: direction == .increment ? step : -step)
        }
    }

    /// Sound off and on, left of full screen like YouTube's (D214).
    private var muteButton: some View {
        Button { controller.muted.toggle() } label: {
            Image(systemName: controller.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.subheadline.weight(.semibold))
                .contentTransition(.identity)
                .shadow(color: Self.textShadow, radius: 1.5, y: 0.5)
                .frame(width: 44, height: 44)
                .background { GlassChip(shape: Circle()).padding(4) }
                .contentShape(.rect)
        }
        .padding(.trailing, -4) // 8 pt between the two circles
        .accessibilityLabel(controller.muted ? "Unmute" : "Mute")
    }

    /// Our own play/pause in the middle, now that YouTube's overlays are hidden (D90).
    private var playPauseButton: some View {
        Button {
            controller.togglePlay()
            lastSkip = nil
            setControls(true)
        } label: {
            Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 24, weight: .semibold))
                // Swaps at once, with no symbol animation (D95).
                .contentTransition(.identity)
                // Only the swap is un-animated. A blanket "no animation" here made the icon jump
                // ahead of its circle when the player sprang back from a pull-down.
                .transaction(value: controller.isPlaying) { $0.animation = nil }
                .frame(width: Self.playButtonSize, height: Self.playButtonSize)
                .background { GlassChip(shape: Circle()) } // the same glass as the times (D214)
                .contentShape(.circle)
        }
        .accessibilityLabel(controller.isPlaying ? "Pause" : "Play")
    }

    /// Our own black loading screen over YouTube's (which shows the thumbnail), gone the moment
    /// the video plays. No thumbnail, so it doesn't flash before playback (D57).
    /// Never blocks taps, and lifts after a few seconds anyway so an ad (and its Skip button)
    /// is never hidden.
    private var poster: some View {
        // The video's own picture, like YouTube, not a black screen (D166). It is the one the
        // Inbox card already loaded, so it's there in the first frame and costs playback nothing.
        Color.black
            .overlay { CachedImage(urls: Thumbnail.urls(controller.current.id)).id(controller.current.id) }
            .clipped()
            .overlay { ProgressView().tint(.white).shadow(color: .black.opacity(0.6), radius: 4) }
            .allowsHitTesting(false)
            .transition(.opacity.animation(.easeOut(duration: 0.12)))
            .task(id: controller.current.id) {
                try? await Task.sleep(for: .seconds(PlayerController.posterTimeout))
                if !Task.isCancelled { controller.posterTimedOut() }
            }
    }

    /// Shown at the top middle while the right side is held, like YouTube's (D131).
    private var boostBadge: some View {
        pill(Label("2×", systemImage: "forward.fill").padding(.horizontal, 4), glass: true)
            .padding(.top, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .allowsHitTesting(false)
    }

    private var speedMenu: some View {
        Menu {
            Picker("Speed", selection: $controller.rate) {
                ForEach(PlayerController.rates, id: \.self) { rate in
                    Text(rate == 1 ? "Normal" : "\(rate.formatted())×").tag(rate)
                }
            }
        } label: {
            Text(controller.rate == 1 ? "1×" : "\(controller.rate.formatted())×")
                .font(.subheadline.weight(.semibold))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
        }
    }

    private func skipFeedback(_ flash: SkipFlash) -> some View {
        sidePill(forward: flash.forward) {
            Label("10 seconds", systemImage: flash.forward ? "goforward.10" : "gobackward.10")
        }
        .task(id: flash) {
            try? await Task.sleep(for: .milliseconds(700))
            if skipFlash == flash { skipFlash = nil }
        }
    }

    /// A gray glass pill centred in the gap between the play/pause button and the left or right
    /// edge of the video, easy to read on any picture (D101).
    private func sidePill<Content: View>(forward: Bool, @ViewBuilder _ label: () -> Content) -> some View {
        HStack(spacing: 0) {
            // Color.clear always takes its half, even when the pill is on the other side.
            Color.clear.overlay { if !forward { pill(label(), glass: true) } }
            Color.clear.frame(width: Self.playButtonSize) // the play/pause button
            Color.clear.overlay { if forward { pill(label(), glass: true) } }
        }
        .allowsHitTesting(false)
    }

    /// `glass` is the blurred gray of the other controls, for the ±10 s and 2× chips (D227).
    /// Without it, the dark pill of Skip Ad and Next video (D219).
    private func pill<Content: View>(_ label: Content, glass: Bool = false) -> some View {
        label
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.white)
            .shadow(color: glass ? Self.textShadow : .clear, radius: 1.5, y: 0.5)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                if glass { GlassChip(shape: Capsule()) } else { Capsule().fill(.black.opacity(Self.chipShade)) }
            }
            .fixedSize()
    }

    /// Full screen only: Next video, bottom-right, in the last seconds (D102, D161). The same
    /// dark pill in the same spot as Skip Ad (D219): the two never show together (D114).
    private var fullscreenPlayNext: some View {
        cornerPill(Label("Next video", systemImage: "forward.fill"), id: "nextVideo",
                   shown: controller.playNextOffer != nil, fullscreen: true) {
            if let next = controller.playNextOffer { controller.requestSwitch(to: next) }
        }
        .animation(.easeInOut(duration: 0.25), value: controller.playNextOffer?.id)
    }

    /// Skip Ad (beta, D111): a dark pill bottom-right while an in-video promotion plays. It
    /// stays up with the controls hidden and clears them when they show.
    private func skipAdCorner(fullscreen: Bool) -> some View {
        // Next video wins: when it pops up in full screen (D102), Skip Ad steps aside (D114).
        let playNextShowing = fullscreen && controller.playNextOffer != nil
        let visible = controller.activeAd != nil && !playNextShowing
        return cornerPill(Label("Skip Ad", systemImage: "forward.end.fill"), id: "skipAd",
                          shown: visible, fullscreen: fullscreen) {
            controller.skipAd()
            skipAdTaps += 1
        }
        .animation(.easeInOut(duration: 0.2), value: visible)
        .sensoryFeedback(.impact(weight: .light), trigger: skipAdTaps)
    }

    /// How far a corner pill's 44 pt touch row sits above the picture's bottom edge. With the
    /// controls up it ends 2 pt above the mute and full screen circles, so the pill itself is
    /// 8 pt clear of them (D219).
    static func cornerPillBottom(fullscreen: Bool, controls: Bool) -> CGFloat {
        if fullscreen { return controls ? 112 : 32 }
        return controls ? 54 : 12
    }

    /// Skip Ad and Next video: one look, one spot (D219).
    private func cornerPill(_ label: some View, id: String, shown: Bool, fullscreen: Bool,
                            action: @escaping () -> Void) -> some View {
        // A tap just beside the pill still counts (D195), but never on the side where the
        // controls' own buttons are: with the controls up, nothing is added below (D219).
        let margin = EdgeInsets(top: Self.skipAdInset, leading: Self.skipAdInset,
                                bottom: parts.bar ? 0 : Self.skipAdInset, trailing: Self.skipAdInset)
        return GeometryReader { geo in
            // In full screen the video is 16:9 in the middle of a wider screen, with black bars
            // at the sides. Keep the button inside the picture, not out on a bar (D127).
            let sideBar = fullscreen ? max((geo.size.width - geo.size.height * 16 / 9) / 2, 0) : 0
            ZStack(alignment: .bottomTrailing) {
                Color.clear.allowsHitTesting(false)
                if shown {
                    Button(action: action) {
                        pill(label)
                            .frame(minHeight: 44)
                            .padding(margin)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    // The matching negative padding keeps the pill where it was.
                    .padding(EdgeInsets(top: -margin.top, leading: -margin.leading,
                                        bottom: -margin.bottom, trailing: -margin.trailing))
                    .accessibilityIdentifier(id)
                    .padding(.trailing, sideBar + Self.skipAdInset)
                    .padding(.bottom, Self.cornerPillBottom(fullscreen: fullscreen, controls: parts.bar))
                    .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: parts.bar)
    }

    @ViewBuilder
    private var endingOverlay: some View {
        switch controller.ending {
        case .none:
            EmptyView()
        case .next(let entry):
            ZStack {
                Color.black.opacity(0.6)
                Button { controller.playNext() } label: {
                    VStack(spacing: 6) {
                        Label("Next video", systemImage: "play.fill").font(.headline)
                        Text(entry.video.title).font(.footnote).lineLimit(1).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.glass)
                .padding(24)
            }
        case .allDone:
            ZStack {
                Color.black.opacity(0.7)
                Text("That's it for today").font(.headline).foregroundStyle(.white)
            }
        }
    }

    @ViewBuilder
    private var noticeBanner: some View {
        if let notice = controller.notice {
            Text(notice)
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.thinMaterial, in: .capsule)
                .padding(8)
                .task {
                    try? await Task.sleep(for: .seconds(3))
                    controller.clearNotice()
                }
        }
    }

    // MARK: - Details + Up Next

    /// Built from plain values and compared with `==`, so the 4-times-a-second playback updates
    /// that redraw the controls don't rebuild (or re-fetch) the scrolling page below the video.
    private var belowVideo: some View {
        BelowVideo(
            video: controller.current.video,
            upNext: controller.upNext,
            creators: creators,
            extras: store.videoExtras,
            subscribers: store.subscriberCounts,
            onSelect: { controller.requestSwitch(to: $0) },
            onMove: { controller.moveUpNext(fromOffsets: $0, toOffset: $1) }
        )
        .equatable()
    }
}

/// A creator's name and avatar, looked up once when the player opens.
struct CreatorInfo: Equatable, Codable, Sendable {
    let title: String
    let avatarURL: URL?
}

/// One scrolling page under the video: title, views, creator, description, then the rest of
/// today's videos as full cards with up/down arrows to reorder (D69).
private struct BelowVideo: View, Equatable {
    let video: Video
    let upNext: [HomeEntry]
    let creators: [String: CreatorInfo]
    let extras: [String: VideoExtras]
    let subscribers: [String: Int]
    let onSelect: (HomeEntry) -> Void
    let onMove: (IndexSet, Int) -> Void

    // `nonisolated`: View makes this struct main-actor isolated, but Equatable's `==` isn't
    // (a Swift 6 error otherwise). It only reads `let`s of Sendable value types.
    nonisolated static func == (a: Self, b: Self) -> Bool {
        a.video == b.video && a.upNext == b.upNext && a.creators == b.creators
            && a.extras == b.extras && a.subscribers == b.subscribers
    }

    var body: some View {
        List {
            details
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 8, trailing: 16))
            ForEach(Array(upNext.enumerated()), id: \.element.id) { index, entry in
                let creator = creators[entry.video.creatorID]
                VideoCard(
                    entry: entry,
                    creator: creator?.title ?? "",
                    avatarURL: creator?.avatarURL,
                    views: extras[entry.id]?.viewCount,
                    trailing: .arrows(
                        moveUp: index > 0 ? { onMove([index], index - 1) } : nil,
                        moveDown: index < upNext.count - 1 ? { onMove([index], index + 2) } : nil
                    )
                )
                .contentShape(.rect)
                .onTapGesture { onSelect(entry) }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var details: some View {
        let creator = creators[video.creatorID]
        let extra = extras[video.id]
        let meta = [extra?.viewCount.map { "\(Format.views($0)) views" }, Format.age(video.publishedAt)]
            .compactMap { $0 }
            .joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(video.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                Text(meta)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Avatar(url: creator?.avatarURL, size: 40)
                // Name with the subscriber count under it, like YouTube (D94).
                VStack(alignment: .leading, spacing: 2) {
                    Text(creator?.title ?? "")
                        .font(.headline)
                        .lineLimit(1)
                    if let count = subscribers[video.creatorID] {
                        Text("\(Format.views(count)) subscribers")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if let next = upNext.first {
                    // Same as tapping the first Up Next card, so a started video still asks first (D12).
                    Button("Play Next", systemImage: "forward.fill") { onSelect(next) }
                        .labelStyle(.titleAndIcon)
                        .fixedSize()
                        .buttonStyle(.glassProminent)
                        .tint(.blue)
                }
            }
            if let text = extra?.description, !text.isEmpty {
                DescriptionBox(text: text)
                    .id(video.id) // collapses again for each new video
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The video's description: two lines with "more", tap to open it all; "less" at the end, tap to close
/// (like YouTube and Signal). Once open, links are blue and open in Safari (D35).
private struct DescriptionBox: View {
    let text: String
    @Environment(\.colorScheme) private var colorScheme
    @State private var expanded = false
    /// Link detection runs once, the first time the description opens.
    @State private var linked: AttributedString?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if expanded {
                Text(linked ?? AttributedString(text))
                    .tint(.blue)
                    .fixedSize(horizontal: false, vertical: true)
                Text("less")
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
            } else {
                Text(text.split(whereSeparator: \.isNewline).joined(separator: " "))
                    .lineLimit(2)
                Text("more")
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        // Apple's light gray in light mode: its "tertiary" is white there, the same as the page (D224).
        .background(Color(colorScheme == .light ? .secondarySystemBackground : .tertiarySystemBackground), in: .rect(cornerRadius: 14))
        .contentShape(.rect)
        .onTapGesture {
            if linked == nil { linked = Format.linked(text) }
            expanded.toggle()
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(expanded ? "Shows less" : "Shows the full description")
    }
}

/// Hosts the single shared, pre-warmed web view.
private struct PlayerSurface: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebViewContainer {
        WKWebViewContainer()
    }

    func updateUIView(_ uiView: WKWebViewContainer, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebViewContainer, coordinator: ()) {
        // Only if it's still here: after a turn to or from full screen the new host may
        // already have taken the web view, and pulling it out again hides it from iOS.
        let webView = YouTubeIFramePlayer.shared.webView
        if webView.superview === uiView { webView.removeFromSuperview() }
    }
}

/// Container so the shared web view can move between hosts without being recreated.
final class WKWebViewContainer: UIView, UIGestureRecognizerDelegate {
    /// Posted when a tap reaches the web view itself, which only happens in the Skip Ad gap.
    static let tapped = Notification.Name("WKWebViewContainer.tapped")

    override init(frame: CGRect) {
        super.init(frame: frame)
        // Watches only: the tap still goes on to YouTube, so its own Skip ad keeps working.
        let tap = UITapGestureRecognizer(target: self, action: #selector(didTap))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        addGestureRecognizer(tap)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func didTap() {
        NotificationCenter.default.post(name: Self.tapped, object: nil)
    }

    func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        let webView = YouTubeIFramePlayer.shared.webView
        webView.removeFromSuperview()
        webView.frame = bounds
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(webView)
    }
}

/// In full screen the controls go with the picture, not the screen: a little past its sides, like
/// YouTube's, not far out in the black beside it (D211, D213).
/// What sits behind the times and the round buttons: the video blurred, in a light gray, like
/// YouTube's (D211, D214).
private struct GlassChip<S: Shape>: View {
    let shape: S

    var body: some View {
        shape.fill(PlayerView.timeChip)
            .overlay { shape.fill(.white.opacity(PlayerView.timeChipLift)) }
            .opacity(PlayerView.timeChipStrength)
            .environment(\.colorScheme, .dark)
    }
}

private struct AroundPicture: ViewModifier {
    let on: Bool

    func body(content: Content) -> some View {
        if on {
            content
                .padding(.horizontal, -PlayerView.fullscreenOverhang)
                .aspectRatio(16.0 / 9, contentMode: .fit)
        } else {
            content
        }
    }
}
