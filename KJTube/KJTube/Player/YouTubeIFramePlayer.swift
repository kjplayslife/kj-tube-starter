import UIKit
import WebKit

/// The official YouTube IFrame player in one `WKWebView` that's created at launch and reused for
/// every video, so tapping play never pays a cold start (PLAN §5). YouTube's own controls are
/// hidden (`controls=0`); KJ Tube draws its own on top.
@MainActor
final class YouTubeIFramePlayer: NSObject, VideoPlayer, WKScriptMessageHandler, WKNavigationDelegate {
    static let shared = YouTubeIFramePlayer()

    /// YouTube requires a real-looking https origin/referrer for embeds in apps.
    private static let origin = "https://com.example.kjtube"

    let webView: WKWebView
    var onEvent: ((PlayerEvent) -> Void)? {
        didSet { onEvent == nil ? stopClock() : startClock() }
    }

    /// Asks the page for the time and state four times a second while the player is open.
    /// The page has its own timer too, but iOS can slow a page's timers to a crawl when it
    /// thinks the page is hidden (after the app was away, or the video moved between full
    /// screen and small). The clock then sat still while the video played. Asking from the
    /// app's side always gets through.
    private var clock: Timer?

    private var isReady = false
    /// JS to run once the API is ready (a load requested during warm-up).
    private var pending: [String] = []
    /// YouTube's player script didn't load (the app opened offline). The page is useless until
    /// it's loaded again (D107).
    private var scriptFailed = false
    #if DEBUG
    private var brokeOnce = false
    #endif
    private var pageRequestedAt = Date.now
    /// A page that still isn't ready after this long is loaded again on the next command.
    static let pageTimeout: TimeInterval = 10

    override init() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsPictureInPictureMediaPlayback = false
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        config.userContentController.add(self, name: "yt")
        // The public version leaves YouTube's frame alone: nothing hidden, nothing read (D179).
        if !AppConfig.isPublic {
            config.userContentController.addUserScript(WKUserScript(
                source: Self.hideOverlaysJS, injectionTime: .atDocumentStart, forMainFrameOnly: false
            ))
        }
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.navigationDelegate = self
        loadPage()
        NotificationCenter.default.addObserver(
            self, selector: #selector(willEnterForeground),
            name: UIApplication.willEnterForegroundNotification, object: nil
        )
    }

    private func startClock() {
        guard clock == nil else { return }
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isReady else { return }
                self.webView.evaluateJavaScript("tick();", completionHandler: nil)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        clock = timer
    }

    private func stopClock() {
        clock?.invalidate()
        clock = nil
    }

    /// The time to pass on from a YouTube message, if any. A video that isn't running yet
    /// (just loaded, cued after the page was rebuilt, or buffering its first bytes) says 0,
    /// which would throw away the real place: the bar showed 0:00 with the video half-way.
    nonisolated static func timeToReport(state: Int?, time: Double?) -> Double? {
        guard let time, time.isFinite, time >= 0 else { return nil }
        switch state {
        case PlayerState.playing.rawValue: return time
        case PlayerState.buffering.rawValue: return time > 0 ? time : nil
        default: return nil
        }
    }

    // MARK: - Coming back from the background

    /// iOS can quietly kill the web page while the app sits in the background. The player then
    /// stays black and ignores play until the app is force-closed. So when that happens, or the
    /// page stops answering on the way back, load a fresh page and tell the controller.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        restart()
    }

    @objc private func willEnterForeground() {
        guard isReady else { return reloadPageIfStuck() }
        webView.evaluateJavaScript("player.getPlayerState()") { [weak self] result, error in
            if error != nil || result == nil { self?.restart() }
        }
    }

    private func restart() {
        isReady = false
        pending.removeAll()
        loadPage()
        onEvent?(.reset)
    }

    private func loadPage() {
        scriptFailed = false
        pageRequestedAt = .now
        var html = Self.html(public: AppConfig.isPublic)
        #if DEBUG
        // `-breakPlayerPage`: the first page load can't reach YouTube's script, like a launch offline.
        if !brokeOnce, ProcessInfo.processInfo.arguments.contains("-breakPlayerPage") {
            brokeOnce = true
            html = html.replacingOccurrences(of: "www.youtube.com/iframe_api", with: "www.youtube.invalid/iframe_api")
        }
        #endif
        webView.loadHTMLString(html, baseURL: URL(string: Self.origin))
    }

    /// The page never got ready (no connection at launch): load it again. Queued commands are
    /// kept and run once it's ready, so the video that was tapped still plays.
    private func reloadPageIfStuck() {
        guard !isReady, scriptFailed || Date.now.timeIntervalSince(pageRequestedAt) > Self.pageTimeout else { return }
        loadPage()
    }

    /// Call at launch so the web view and IFrame API are warm before the first tap.
    func prewarm() {}

    func load(videoID: String, startAt: TimeInterval) {
        let start = max(Int(startAt), 0)
        if !isReady { pending.removeAll() } // a newer video replaces whatever was queued
        run("player.loadVideoById({videoId: '\(videoID)', startSeconds: \(start)});")
        requestStoryboard(videoID)
    }

    func cue(videoID: String, startAt: TimeInterval) {
        let start = max(Int(startAt), 0)
        run("player.cueVideoById({videoId: '\(videoID)', startSeconds: \(start)});")
        requestStoryboard(videoID)
    }

    /// Asks YouTube's frame for the video's preview pictures (D134). Video ids are letters,
    /// digits, "-" and "_"; anything else is not sent into the page.
    private func requestStoryboard(_ videoID: String) {
        guard !AppConfig.isPublic else { return } // not an official API (D179)
        guard videoID.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil else { return }
        run("try { player.getIframe().contentWindow.postMessage({kjStoryboard: '\(videoID)'}, '*'); } catch (e) {}")
    }

    func play() { run("player.playVideo();") }
    func pause() { run("player.pauseVideo();") }
    func seek(to seconds: TimeInterval) { run("player.seekTo(\(max(seconds, 0)), true);") }
    /// In the public version speed and captions belong to YouTube's own controls (D179).
    func setRate(_ rate: Double) {
        guard !AppConfig.isPublic else { return }
        run("player.setPlaybackRate(\(rate));")
    }

    /// YouTube turns captions on by itself (from the viewer's settings or the video), often a
    /// moment after playback starts. So the page remembers the choice and re-applies it every
    /// time YouTube loads its captions module (`onApiChange`) and whenever a video starts.
    func setCaptions(_ on: Bool) {
        guard !AppConfig.isPublic else { return }
        run("wantCaptions = \(on); applyCaptions();")
    }

    func setMuted(_ on: Bool) {
        guard !AppConfig.isPublic else { return }
        run(on ? "player.mute();" : "player.unMute();")
    }

    private func run(_ js: String) {
        guard isReady else {
            pending.append(js)
            reloadPageIfStuck()
            return
        }
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    // MARK: - JS → Swift

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let kind = body["e"] as? String else { return }
        switch kind {
        case "ready":
            isReady = true
            pending.forEach { webView.evaluateJavaScript($0, completionHandler: nil) }
            pending.removeAll()
            onEvent?(.ready)
        case "state":
            let raw = body["s"] as? Int
            if let raw, let state = PlayerState(rawValue: raw) { onEvent?(.state(state)) }
            if let t = Self.timeToReport(state: raw, time: body["t"] as? Double) { onEvent?(.time(t)) }
        case "time":
            if let t = Self.timeToReport(state: body["s"] as? Int, time: body["t"] as? Double) { onEvent?(.time(t)) }
        case "seeked":
            onEvent?(.seeked)
        case "storyboard":
            if let id = body["id"] as? String, let spec = body["spec"] as? String {
                onEvent?(.storyboard(videoID: id, spec: spec))
            }
        case "scriptfail":
            scriptFailed = true
        case "error":
            if let code = body["c"] as? Int { onEvent?(.error(code)) }
        default:
            break
        }
    }

    /// YouTube's own title bar, logo, big play button, "More videos" and end-screen cards still
    /// show over the video for a few seconds with `controls=0`, under KJ Tube's controls (D85).
    /// This runs inside YouTube's embed frame and hides them. The "Includes paid promotion" label
    /// stays: it's a disclosure.
    private static let hideOverlaysJS = """
    if (location.hostname.endsWith('youtube.com') || location.hostname.endsWith('youtube-nocookie.com')) {
      var style = document.createElement('style');
      style.textContent = [
        // The current embed (mobile-web style): title bar, middle play/pause, share,
        // "Watch on YouTube", "More videos", the cued play button and end-screen picks.
        '.player-controls-top', '.player-controls-middle', '.player-controls-bottom',
        '.quick-actions-wrapper', '.action-menu-engagement-buttons-wrapper',
        '.watch-on-youtube-button-wrapper', '.fullscreen-controls', '.fullscreen-watch-next-entrypoint-wrapper',
        '.ytmCuedOverlayPlayButton', 'embedded-player-video-details', 'ytm-endscreen-video-renderer',
        '.ytFullscreenVideoRecommendationsRecommendation',
        // The older desktop embed, in case YouTube serves it.
        '.ytp-chrome-top', '.ytp-gradient-top', '.ytp-chrome-bottom', '.ytp-gradient-bottom',
        '.ytp-watermark', '.ytp-large-play-button', '.ytp-pause-overlay', '.ytp-impression-link',
        '.ytp-show-cards-title', '.ytp-cards-teaser', '.ytp-ce-element', '.ytp-endscreen-content'
      ].join(',') + '{display:none !important}'
        // The dark shade YouTube puts behind its (hidden) controls, which lingered at the top
        // after play/pause or a skip (D95). Ad pieces stay so "Skip ad" still works.
        + '[class*="gradient"]:not([class*="ad-"]),[class*="controls-background"],[class*="scrim"]:not([class*="ad-"])'
        + '{display:none !important}';
      (document.head || document.documentElement).appendChild(style);

      // Tells the app when the video's picture has caught up with a seek, so the seek-bar
      // preview can stay up until then (D134). Media events don't bubble, so this captures.
      document.addEventListener('seeked', function() {
        try { window.webkit.messageHandlers.yt.postMessage({e: 'seeked'}); } catch (e) {}
      }, true);

      // Preview pictures for the seek bar (D134). The app asks for a video's "storyboard";
      // this frame is on youtube.com, so it can ask YouTube the way its own mobile site does.
      // Not an official API: if it stops working, nothing is sent and there is just no preview.
      var kjStoryboardFor = null;
      window.addEventListener('message', function(ev) {
        var id = ev.data && ev.data.kjStoryboard;
        if (typeof id !== 'string' || !/^[A-Za-z0-9_-]+$/.test(id)) { return; }
        kjStoryboardFor = id;
        var tries = 0;
        (function ask() {
          if (kjStoryboardFor !== id) { return; } // a newer video was asked for
          var cfg = window.ytcfg && window.ytcfg.data_ && window.ytcfg.data_.INNERTUBE_CONTEXT;
          if (!cfg) { if (++tries < 20) { setTimeout(ask, 500); } return; }
          // YouTube answers differently depending on who asks, and now and then says a
          // video is "unavailable" for no reason (seen right after the app opens). So try a
          // few ways in turn until one has the pictures: its mobile site, its desktop site,
          // then the watch page itself. If none does, go round again a little later.
          var found = function(spec) {
            if (typeof spec !== 'string' || spec.indexOf('|') < 0) { return false; }
            if (kjStoryboardFor === id) {
              window.webkit.messageHandlers.yt.postMessage({e: 'storyboard', id: id, spec: spec});
            }
            return true;
          };
          var ways = ['MWEB', 'WEB', 'page'], rounds = 0;
          (function next(i) {
            if (kjStoryboardFor !== id) { return; }
            if (i >= ways.length) {
              if (++rounds < 3) { setTimeout(function() { next(0); }, rounds * 3000); }
              return;
            }
            var way = ways[i], request;
            if (way === 'page') {
              request = fetch('/watch?v=' + id).then(function(r) { return r.text(); }).then(function(t) {
                var m = t.match(/playerStoryboardSpecRenderer":[{]"spec":"([^"]+)"/);
                return m ? JSON.parse('"' + m[1] + '"') : null;
              });
            } else {
              var context = JSON.parse(JSON.stringify(cfg));
              context.client.clientName = way;
              context.client.clientVersion = '2.20251101.00.00';
              request = fetch('/youtubei/v1/player?prettyPrint=false', {
                method: 'POST', headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({context: context, videoId: id})
              }).then(function(r) { return r.json(); }).then(function(j) {
                return j && j.storyboards && j.storyboards.playerStoryboardSpecRenderer
                  && j.storyboards.playerStoryboardSpecRenderer.spec;
              });
            }
            request.then(function(spec) { if (!found(spec)) { next(i + 1); } })
              .catch(function() { next(i + 1); });
          })(0);
        })();
      });
    }
    """

    /// KJ's own app hides YouTube's controls and draws its own. The public version shows
    /// YouTube's (D179).
    static func playerVars(public isPublic: Bool) -> String {
        isPublic
            ? "playsinline: 1, controls: 1, rel: 0, fs: 0"
            : "playsinline: 1, controls: 0, rel: 0, iv_load_policy: 3, fs: 0, disablekb: 1, modestbranding: 1, cc_load_policy: 0"
    }

    static func html(public isPublic: Bool) -> String { """
    <!doctype html>
    <html><head>
    <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
    <style>html,body{margin:0;padding:0;background:#000;height:100%;overflow:hidden}
    #player{position:absolute;top:0;left:0;width:100%;height:100%}</style>
    </head><body>
    <div id="player"></div>
    <script>
    var player, timer = null, wantCaptions = false;
    function post(m) { window.webkit.messageHandlers.yt.postMessage(m); }
    function applyCaptions() {
      if (!player || !player.loadModule) { return; }
      if (wantCaptions) {
        player.loadModule('captions');
        player.setOption('captions', 'track', {languageCode: 'en'});
      } else {
        player.unloadModule('captions');
        player.unloadModule('cc');
      }
    }
    // Polls YouTube for the time and state four times a second for as long as the page lives
    // (the app also calls this itself, in case iOS slows this page's timers). It used to run
    // only between "playing" events, so when YouTube skipped one (after an ad, a buffer or
    // coming back from the background) the clock froze at 0:00 while the video kept playing.
    // A missed state change is caught here too. The app drops times from a video that isn't
    // running: a just-loaded video can briefly say 0, which would undo resume.
    var lastT = -1, lastS = null;
    function tick() {
      try {
        if (!player || !player.getCurrentTime) { return; }
        var s = player.getPlayerState();
        if (typeof s === 'number' && s !== lastS) { lastS = s; post({e: 'state', s: s}); }
        var t = player.getCurrentTime();
        if ((s === 1 || s === 3) && typeof t === 'number' && isFinite(t) && t !== lastT) { lastT = t; post({e: 'time', t: t, s: s}); }
      } catch (e) {}
    }
    function onYouTubeIframeAPIReady() {
      player = new YT.Player('player', {
        width: '100%', height: '100%',
        playerVars: {\(playerVars(public: isPublic)), origin: '\(origin)'},
        events: {
          onReady: function() {
            post({e: 'ready'});
            if (!timer) { timer = setInterval(tick, 250); }
          },
          onApiChange: function() { applyCaptions(); },
          onStateChange: function(ev) {
            if (ev.data === 1 || ev.data === -1) { applyCaptions(); }
            lastS = ev.data;
            post({e: 'state', s: ev.data, t: player.getCurrentTime()});
          },
          onError: function(ev) { post({e: 'error', c: ev.data}); }
        }
      });
    }
    </script>
    <script src="https://www.youtube.com/iframe_api" onerror="post({e: 'scriptfail'})"></script>
    </body></html>
    """
    }
}
