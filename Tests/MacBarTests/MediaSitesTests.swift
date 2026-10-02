import JavaScriptCore
import XCTest
@testable import MacBar

final class MediaSitesTests: XCTestCase {
    func testDetectsSitesFromWindowTitles() {
        XCTAssertEqual(MediaSite.detect(title: "(3) Lofi beats - YouTube"), .youtube)
        XCTAssertEqual(MediaSite.detect(title: "Netflix"), .netflix)
        XCTAssertNil(MediaSite.detect(title: "GitHub - Google Chrome"))
        XCTAssertEqual(MediaSite.youtube.cleanTitle("(3) Lofi beats - YouTube"), "Lofi beats")
    }

    func testPageScriptsAreValidJavaScript() {
        let context = JSContext()!
        for source in MediaControl.allScripts {
            context.exception = nil
            context.evaluateScript(source)
            let message = context.exception?.toString() ?? ""
            XCTAssertFalse(message.contains("SyntaxError"), "\(message)\n\(source)")
        }
    }

    func testScriptsDriveAVideoElement() throws {
        let context = JSContext()!
        context.evaluateScript("""
        var video={currentTime:30,duration:120,paused:true,volume:0.5,muted:false,playbackRate:1,
          play:function(){this.paused=false},pause:function(){this.paused=true}};
        var document={querySelector:function(s){return s==='video'?video:null},getElementById:function(){return null}};
        var location={host:'www.youtube.com',pathname:'/watch'};
        var navigator={mediaSession:{metadata:{title:'Lofi beats',artist:'Lofi Girl',artwork:[{src:'https://i.ytimg.com/a.jpg'}]}}};
        """)
        let scripts = MediaControl.allScripts
        let state = try XCTUnwrap(context.evaluateScript(scripts[0])?.toString())
        XCTAssertTrue(state.contains("\"t\":30") && state.contains("\"d\":120"), state)
        XCTAssertTrue(state.contains("\"ti\":\"Lofi beats\"") && state.contains("\"ar\":\"Lofi Girl\""), state)
        context.evaluateScript(MediaControl.javaScript(for: .forward))
        XCTAssertEqual(context.evaluateScript("video.currentTime")?.toDouble(), 40)
        context.evaluateScript(MediaControl.javaScript(for: .toggle))
        XCTAssertEqual(context.evaluateScript("video.paused")?.toBool(), false)
        context.evaluateScript(MediaControl.javaScript(for: .speed))
        XCTAssertEqual(context.evaluateScript("video.playbackRate")?.toDouble(), 1.25)
        context.evaluateScript(MediaControl.javaScript(for: .volumeUp))
        XCTAssertEqual(context.evaluateScript("video.volume")?.toDouble() ?? 0, 0.6, accuracy: 0.001)
    }

    @MainActor
    func testPanelRenders() throws {
        guard let path = ProcessInfo.processInfo.environment["MACBAR_PREVIEW_PATH"] else { return }
        _ = NSApplication.shared
        for (site, name) in [(MediaSite.youtube, "youtube"), (.netflix, "netflix")] {
            let panel = MediaPanelView(frame: NSRect(x: 0, y: 0, width: 600, height: 30))
            panel.show(site: site, browser: .current, splash: name == "netflix")
            panel.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(panel.bitmapImageRepForCachingDisplay(in: panel.bounds))
            panel.cacheDisplay(in: panel.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: path.replacingOccurrences(of: ".png", with: "-\(name).png")))
        }
    }

    func testNetflixShowAndEpisode() throws {
        let context = JSContext()!
        context.evaluateScript("""
        var video={currentTime:60,duration:3000,paused:false,volume:1,playbackRate:1};
        var document={querySelector:function(s){return s==='video'?video:null},getElementById:function(){return null}};
        var location={host:'www.netflix.com',pathname:'/watch/81234'};
        var navigator={};
        var show={title:'Stranger Things',type:'show',
          seasons:[{seq:4,episodes:[{id:81233,seq:2,title:'Vecna'},{id:81234,seq:3,title:'The Monster'}]}]};
        var meta={getMetadata:function(){return {_metadata:{video:show}}}};
        var netflix={appContext:{state:{playerApp:{
          getAPI:function(){throw 'x'},
          getState:function(){return {videoPlayer:{videoMetadata:{81234:meta}}}}
        }}}};
        """)
        let state = try XCTUnwrap(context.evaluateScript(MediaControl.allScripts[0])?.toString())
        XCTAssertNil(context.exception, context.exception?.toString() ?? "")
        XCTAssertTrue(state.contains("\"ti\":\"Stranger Things\""), state)
        XCTAssertTrue(state.contains("S4:E3 · The Monster"), state)
    }
}
