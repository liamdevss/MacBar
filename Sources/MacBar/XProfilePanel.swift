import AppKit

enum XStats {
    struct Stats: Equatable {
        var followers: Int
        var following: Int
        var posts: Int
    }

    private static let lastFollowersKey = "x.lastFollowers"

    static func fetch(username: String, completion: @escaping (Stats?) -> Void) {
        guard let url = URL(string: "https://api.fxtwitter.com/\(username)") else { return completion(nil) }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("MacBar", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, _, _ in
            let user = data
                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                .flatMap { $0["user"] as? [String: Any] }
            let stats = user.flatMap { user -> Stats? in
                guard let followers = user["followers"] as? Int, let following = user["following"] as? Int,
                      let posts = user["tweets"] as? Int else { return nil }
                return Stats(followers: followers, following: following, posts: posts)
            }
            DispatchQueue.main.async { completion(stats) }
        }.resume()
    }

    static func followerDelta(_ followers: Int) -> Int {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: lastFollowersKey) as? Int
        defaults.set(followers, forKey: lastFollowersKey)
        return previous.map { followers - $0 } ?? 0
    }

    static func compact(_ value: Int) -> String {
        switch value {
        case 1_000_000...: return String(format: "%.1fM", Double(value) / 1_000_000)
        case 10_000...: return String(format: "%.0fK", Double(value) / 1_000)
        case 1_000...: return String(format: "%.1fK", Double(value) / 1_000)
        default: return "\(value)"
        }
    }
}

extension Notification.Name {
    static let xStatsChanged = Notification.Name("dev.macbar.xStatsChanged")
}

final class XStatsStore {
    static let shared = XStatsStore()
    private(set) var stats: XStats.Stats?
    private(set) var delta = 0
    private var fetchedAt = Date.distantPast
    private var loading = false
    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        refresh(force: true)
        let timer = Timer(timeInterval: 300, repeats: true) { [weak self] _ in self?.refresh(force: true) }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func refresh(force: Bool = false) {
        guard !loading, force || Date().timeIntervalSince(fetchedAt) > 60 else { return }
        loading = true
        XStats.fetch(username: ProfileLink.username) { [weak self] stats in
            guard let self else { return }
            self.loading = false
            guard let stats else { return }
            self.fetchedAt = Date()
            if stats.followers != self.stats?.followers {
                let change = XStats.followerDelta(stats.followers)
                if change != 0 { self.delta = change }
            }
            self.stats = stats
            NotificationCenter.default.post(name: .xStatsChanged, object: nil)
        }
    }
}

final class XProfilePanel: NSView {
    private let followers = GlassButton()
    private let following = GlassButton()
    private let posts = GlassButton()
    private let viewProfile = GlassButton()
    private let post = GlassButton()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let base = ProfileLink.url.absoluteString
        followers.onPress = { NSWorkspace.shared.open(URL(string: base + "/followers")!) }
        following.onPress = { NSWorkspace.shared.open(URL(string: base + "/following")!) }
        posts.onPress = { NSWorkspace.shared.open(ProfileLink.url) }
        viewProfile.image = NSImage(systemSymbolName: "person.crop.circle", accessibilityDescription: nil)
        viewProfile.setTitle("View Profile")
        viewProfile.onPress = { NSWorkspace.shared.open(ProfileLink.url) }
        post.prominent = true
        post.contentTintColor = .black
        post.image = NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: nil)
        post.setTitle("Post", weight: .semibold)
        post.onPress = { NSWorkspace.shared.open(URL(string: "https://x.com/compose/post")!) }
        for button in [followers, following, posts, viewProfile, post] { addSubview(button) }
        NotificationCenter.default.addObserver(self, selector: #selector(render), name: .xStatsChanged, object: nil)
        render()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func refresh() {
        render()
        animateIn()
        XStatsStore.shared.refresh()
    }

    private func animateIn() {
        for (index, view) in [followers, following, posts, viewProfile, post].enumerated() {
            Glass.appear(view, delay: Double(index) * 0.04)
        }
    }

    private func tile(_ button: GlassButton, value: Int?, label: String, delta: Int = 0) {
        let text = NSMutableAttributedString(string: value.map(XStats.compact) ?? "–", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .bold), .foregroundColor: NSColor.white
        ])
        if delta != 0 {
            text.append(NSAttributedString(string: delta > 0 ? " +\(delta)" : " \(delta)", attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: delta > 0 ? NSColor.systemGreen : NSColor.systemRed
            ]))
        }
        text.append(NSAttributedString(string: " \(label)", attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .regular), .foregroundColor: NSColor.white.withAlphaComponent(0.7)
        ]))
        button.attributedTitle = text
        button.imagePosition = .noImage
    }

    @objc private func render() {
        let stats = XStatsStore.shared.stats
        tile(followers, value: stats?.followers, label: "followers", delta: XStatsStore.shared.delta)
        tile(following, value: stats?.following, label: "following")
        tile(posts, value: stats?.posts, label: "posts")
        for button in [followers, following, posts] { button.needsDisplay = true }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        var x: CGFloat = 0
        for button in [followers, following, posts] {
            let width = button.fittingWidth()
            button.frame = NSRect(x: x, y: 0, width: width, height: bounds.height)
            x += width + Glass.gap
        }
        let postWidth = post.fittingWidth(padding: 14), viewWidth = viewProfile.fittingWidth(padding: 14)
        post.frame = NSRect(x: bounds.width - postWidth, y: 0, width: postWidth, height: bounds.height)
        viewProfile.frame = NSRect(x: post.frame.minX - Glass.gap - viewWidth, y: 0, width: viewWidth, height: bounds.height)
    }
}
