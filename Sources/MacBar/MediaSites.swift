import AppKit
import ApplicationServices
import Carbon.HIToolbox

extension Notification.Name {
    static let mediaSiteChanged = Notification.Name("dev.macbar.mediaSiteChanged")
}

enum MediaSite: Equatable {
    case youtube, netflix

    var name: String { self == .youtube ? "YouTube" : "Netflix" }

    static func detect(title: String) -> MediaSite? {
        if title.range(of: "YouTube", options: .caseInsensitive) != nil { return .youtube }
        if title.range(of: "Netflix", options: .caseInsensitive) != nil { return .netflix }
        return nil
    }

    func cleanTitle(_ title: String) -> String {
        var text = title
        for suffix in [" - YouTube Music", " - YouTube", " | Netflix", " - Netflix", "Netflix"] where text.hasSuffix(suffix) {
            text = String(text.dropLast(suffix.count))
        }
        text = text.replacingOccurrences(of: #"^\(\d+\)\s*"#, with: "", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespaces)
    }
}

final class MediaSiteMonitor {
    static let shared = MediaSiteMonitor()
    static let browsers: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.canary", "com.brave.Browser", "com.microsoft.edgemac",
        "com.vivaldi.Vivaldi", "company.thebrowser.Browser", "com.apple.Safari", "org.mozilla.firefox"
    ]

    private(set) var site: MediaSite?
    private(set) var browser: NSRunningApplication?
    private(set) var title = ""
    private var observer: AXObserver?
    private var pending: DispatchWorkItem?

    func start() {
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(activated(_:)),
                                                          name: NSWorkspace.didActivateApplicationNotification, object: nil)
        if let app = NSWorkspace.shared.frontmostApplication { attach(app) }
    }

    @objc private func activated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        attach(app)
    }

    private func attach(_ app: NSRunningApplication) {
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode) }
        observer = nil
        guard let id = app.bundleIdentifier, Self.browsers.contains(id) else { return update(nil, nil, "") }
        var created: AXObserver?
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            Unmanaged<MediaSiteMonitor>.fromOpaque(refcon).takeUnretainedValue().scheduleEvaluate()
        }
        if AXObserverCreate(app.processIdentifier, callback, &created) == .success, let created {
            let element = AXUIElementCreateApplication(app.processIdentifier)
            let refcon = Unmanaged.passUnretained(self).toOpaque()
            for name in [kAXTitleChangedNotification, kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification] {
                AXObserverAddNotification(created, element, name as CFString, refcon)
            }
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
            observer = created
        }
        browser = app
        evaluate()
    }

    private func scheduleEvaluate() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.evaluate() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func evaluate() {
        guard let browser else { return }
        let app = AXUIElementCreateApplication(browser.processIdentifier)
        var window: CFTypeRef?
        var title: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window, CFGetTypeID(window) == AXUIElementGetTypeID(),
              AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &title) == .success,
              let text = title as? String else { return update(nil, browser, "") }
        update(MediaSite.detect(title: text), browser, text)
    }

    private func update(_ site: MediaSite?, _ browser: NSRunningApplication?, _ title: String) {
        let changed = site != self.site || browser?.processIdentifier != self.browser?.processIdentifier
        self.site = site
        self.browser = browser
        self.title = title
        if changed { NotificationCenter.default.post(name: .mediaSiteChanged, object: nil) }
    }
}

enum MediaControl {
    enum Action { case toggle, back, forward, next, skip, speed, volumeDown, volumeUp }

    struct State {
        var time: Double
        var duration: Double
        var playing: Bool
        var volume: Double
        var rate: Double
        var canSkip: Bool
        var ad: Bool
        var title = ""
        var subtitle = ""
        var artwork: URL?
    }

    private static let nowPlaying = """
    var ti='',ar='',aw='';var md=navigator.mediaSession&&navigator.mediaSession.metadata;    if(md){ti=md.title||'';ar=md.artist||'';if(md.artwork&&md.artwork.length){aw=md.artwork[md.artwork.length-1].src}}    if(location.host.indexOf('netflix')>=0){    try{var vid=parseInt(location.pathname.split('/watch/')[1]||'',10);    var m=netflix.appContext.state.playerApp.getState().videoPlayer.videoMetadata[vid].getMetadata()._metadata.video;    ti=m.title;ar='';if(m.type==='show'){m.seasons.forEach(function(se){se.episodes.forEach(function(ep){    if(ep.id===vid||ep.episodeId===vid){ar='S'+se.seq+':E'+ep.seq+' · '+ep.title}})})}    if(m.boxart&&m.boxart.length){aw=m.boxart[0].url}}catch(e){}    var nt=document.querySelector('[data-uia=video-title]');    if(nt){var h=nt.querySelector('h4');var sp=[].map.call(nt.querySelectorAll('span'),function(e){return e.textContent.trim()})    .filter(function(x){return x}).join(' · ');window.__macbarNF={ti:(h?h.textContent:nt.textContent).trim(),ar:sp}}    if((!ti||ti==='Netflix')&&window.__macbarNF){ti=window.__macbarNF.ti;ar=window.__macbarNF.ar}}    else if(!ti){var h1=document.querySelector('h1.ytd-watch-metadata,#title h1');ti=h1?h1.textContent.trim():'';    var ch=document.querySelector('ytd-watch-metadata ytd-channel-name a,#owner #channel-name a');ar=ch?ch.textContent.trim():''}
    """

    private static let netflixPlayer = """
    function nf(){try{var a=netflix.appContext.state.playerApp.getAPI().videoPlayer;\
    return a.getVideoPlayerBySessionId(a.getAllPlayerSessionIds()[0]);}catch(e){return null}}
    """
    private static let skipSelector = ".ytp-skip-ad-button,.ytp-ad-skip-button,.ytp-ad-skip-button-modern,"
        + "[data-uia=player-skip-intro],[data-uia=player-skip-recap],[data-uia=player-skip-preplay],"
        + "[data-uia=next-episode-seamless-button]"

    private static func script(_ body: String) -> String {
        "(function(){\(netflixPlayer);var v=document.querySelector('video');if(!v)return 'novideo';"
            + "var mp=document.getElementById('movie_player');\(body)})()"
    }

    @discardableResult
    static func runJavaScript(_ js: String, in app: NSRunningApplication) -> String? {
        guard let id = app.bundleIdentifier, id != "org.mozilla.firefox" else { return nil }
        let escaped = js.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let source: String
        switch id {
        case "com.apple.Safari":
            source = "tell application id \"\(id)\" to do JavaScript \"\(escaped)\" in current tab of front window"
        case "company.thebrowser.Browser":
            source = "tell application id \"\(id)\" to tell front window to tell active tab to execute javascript \"\(escaped)\""
        default:
            source = "tell application id \"\(id)\" to execute active tab of front window javascript \"\(escaped)\""
        }
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil ? (result?.stringValue ?? "") : nil
    }

    private static var stateScript: String {
        script(nowPlaying + """
        var s=document.querySelector('\(skipSelector)');\
        return JSON.stringify({t:v.currentTime,d:isFinite(v.duration)?v.duration:0,p:!v.paused,\
        v:(mp&&mp.getVolume)?mp.getVolume()/100:v.volume,r:v.playbackRate,s:!!s,a:!!document.querySelector('.ad-showing'),\
        ti:ti,ar:ar,aw:aw});
        """)
    }

    static func state(in app: NSRunningApplication) -> State? {
        guard let raw = runJavaScript(stateScript, in: app), let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return State(time: json["t"] as? Double ?? 0, duration: json["d"] as? Double ?? 0,
                     playing: json["p"] as? Bool ?? false, volume: json["v"] as? Double ?? 0,
                     rate: json["r"] as? Double ?? 1, canSkip: json["s"] as? Bool ?? false, ad: json["a"] as? Bool ?? false,
                     title: json["ti"] as? String ?? "", subtitle: json["ar"] as? String ?? "",
                     artwork: (json["aw"] as? String).flatMap { $0.isEmpty ? nil : URL(string: $0) })
    }

    static func javaScriptAvailable(in app: NSRunningApplication) -> Bool {
        runJavaScript("1", in: app) != nil
    }

    static func perform(_ action: Action, site: MediaSite, in app: NSRunningApplication) {
        if runJavaScript(javaScript(for: action), in: app) == nil { pressShortcut(action, site: site, pid: app.processIdentifier) }
    }

    static var allScripts: [String] {
        [stateScript, script("var p=nf();if(p){p.seek(0.5*p.getDuration())}else{v.currentTime=0.5*v.duration}return 'ok'")]
            + [Action.toggle, .back, .forward, .next, .skip, .speed, .volumeDown, .volumeUp].map(javaScript(for:))
    }

    static func javaScript(for action: Action) -> String {
        let body: String
        switch action {
        case .toggle: body = "v.paused?v.play():v.pause();return 'ok'"
        case .back, .forward:
            let delta = action == .back ? -10 : 10
            body = "var p=nf();if(p){p.seek(p.getCurrentTime()+\(delta * 1000))}else{v.currentTime+=\(delta)}return 'ok'"
        case .next:
            body = "var b=document.querySelector('.ytp-next-button,[data-uia=control-next],[data-uia=next-episode-seamless-button]');"
                + "if(b){b.click();return 'ok'}return 'none'"
        case .skip:
            body = "var b=document.querySelector('\(skipSelector)');if(b){b.click();return 'ok'}return 'none'"
        case .speed:
            body = "var r=[1,1.25,1.5,2];var i=r.indexOf(v.playbackRate);var n=r[(i+1)%r.length];"
                + "if(mp&&mp.setPlaybackRate){mp.setPlaybackRate(n)}else{v.playbackRate=n}return 'ok'"
        case .volumeDown, .volumeUp:
            let delta = action == .volumeDown ? -0.1 : 0.1
            body = "if(mp&&mp.setVolume){mp.unMute&&mp.unMute();mp.setVolume(Math.max(0,Math.min(100,mp.getVolume()+\(delta * 100))))}"
                + "else{var p=nf();if(p&&p.setVolume){p.setVolume(Math.max(0,Math.min(1,p.getVolume()+\(delta))))}"
                + "else{v.muted=false;v.volume=Math.max(0,Math.min(1,v.volume+\(delta)))}}return 'ok'"
        }
        return script(body)
    }

    static func seek(toFraction fraction: Double, in app: NSRunningApplication) {
        runJavaScript(script("var p=nf();if(p){p.seek(\(fraction)*p.getDuration())}else{v.currentTime=\(fraction)*v.duration}return 'ok'"), in: app)
    }

    private static func pressShortcut(_ action: Action, site: MediaSite, pid: pid_t) {
        let key: (Int, Bool)?
        switch (site, action) {
        case (.youtube, .toggle): key = (kVK_ANSI_K, false)
        case (.youtube, .back): key = (kVK_ANSI_J, false)
        case (.youtube, .forward): key = (kVK_ANSI_L, false)
        case (.youtube, .next): key = (kVK_ANSI_N, true)
        case (.youtube, .speed): key = (kVK_ANSI_Period, true)
        case (.netflix, .toggle): key = (kVK_Space, false)
        case (.netflix, .back): key = (kVK_LeftArrow, false)
        case (.netflix, .forward): key = (kVK_RightArrow, false)
        case (.netflix, .skip): key = (kVK_ANSI_S, false)
        case (_, .volumeUp): key = (kVK_UpArrow, false)
        case (_, .volumeDown): key = (kVK_DownArrow, false)
        default: key = nil
        }
        guard let (code, shift) = key else { return }
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(code), keyDown: down)
            if shift { event?.flags = .maskShift }
            event?.postToPid(pid)
        }
    }
}

final class MediaLogoView: NSView {
    var site: MediaSite = .youtube { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        switch site {
        case .youtube:
            let h = min(bounds.height, bounds.width / 1.42)
            let rect = NSRect(x: bounds.midX - h * 0.71, y: bounds.midY - h / 2, width: h * 1.42, height: h)
            NSColor(srgbRed: 1, green: 0, blue: 0.2, alpha: 1).setFill()
            NSBezierPath(roundedRect: rect, xRadius: h * 0.28, yRadius: h * 0.28).fill()
            let t = h * 0.36
            let play = NSBezierPath()
            play.move(to: NSPoint(x: rect.midX - t * 0.4, y: rect.midY + t / 2))
            play.line(to: NSPoint(x: rect.midX + t * 0.55, y: rect.midY))
            play.line(to: NSPoint(x: rect.midX - t * 0.4, y: rect.midY - t / 2))
            play.close()
            NSColor.white.setFill()
            play.fill()
        case .netflix:
            let h = bounds.height
            let w = min(bounds.width, h * 0.56)
            let x0 = bounds.midX - w / 2, x1 = x0 + w, bar = w * 0.3
            NSColor(srgbRed: 0.69, green: 0.02, blue: 0.06, alpha: 1).setFill()
            NSRect(x: x0, y: 0, width: bar, height: h).fill()
            NSRect(x: x1 - bar, y: 0, width: bar, height: h).fill()
            let ribbon = NSBezierPath()
            ribbon.move(to: NSPoint(x: x0, y: h))
            ribbon.line(to: NSPoint(x: x0 + bar, y: h))
            ribbon.line(to: NSPoint(x: x1, y: 0))
            ribbon.line(to: NSPoint(x: x1 - bar, y: 0))
            ribbon.close()
            NSColor(srgbRed: 0.9, green: 0.04, blue: 0.08, alpha: 1).setFill()
            ribbon.fill()
        }
    }
}
