import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: LauncherStore
    var showBar: () -> Void
    var hideBar: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your apps. One touch.").font(.system(size: 26, weight: .semibold))
                    Text("Tap an icon to open an app or bring it forward.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "rectangle.and.hand.point.up.left")
                    .font(.system(size: 32)).foregroundStyle(.blue)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("LIVE PREVIEW").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                LauncherBarPreview(store: store)
                    .frame(height: 30)
                    .padding(.vertical, 10)
                    .background(.black, in: RoundedRectangle(cornerRadius: 12))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                Text("Swipe the Touch Bar to reach more apps. The preview icons work too.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            HStack {
                Toggle("Background", isOn: Binding(get: { store.background.isEnabled }, set: {
                    var settings = store.background
                    settings.isEnabled = $0
                    store.setBackground(settings)
                }))
                Picker("Sizing", selection: Binding(get: { store.background.mode }, set: {
                    var settings = store.background
                    settings.mode = $0
                    store.setBackground(settings)
                })) {
                    ForEach(BackgroundMode.allCases, id: \.self) { mode in Text(mode.title).tag(mode) }
                }.frame(width: 150)
                Spacer()
                Button("Choose Image…", action: store.chooseBackground)
                Button("Use Default") { store.setBackground(BackgroundSettings()) }
            }

            HStack {
                Text("Apps on your bar").font(.headline)
                Text("\(store.apps.count)").foregroundStyle(.secondary)
                Spacer()
                Button("Import Dock") { store.importDock() }
                Button("Add Apps…", action: store.addApps)
            }
            List {
                ForEach(Array(store.apps.enumerated()), id: \.element.id) { index, app in
                    HStack(spacing: 12) {
                        Image(nsImage: store.icon(app)).resizable().frame(width: 30, height: 30)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(app.name).fontWeight(.medium)
                            Text(app.bundleIdentifier).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if store.appURL(app) == nil { Text("Not found").font(.caption).foregroundStyle(.orange) }
                        Button { store.move(app, by: -1) } label: { Image(systemName: "chevron.up") }
                            .disabled(index == 0).help("Move \(app.name) left")
                            .accessibilityLabel("Move \(app.name) left")
                        Button { store.move(app, by: 1) } label: { Image(systemName: "chevron.down") }
                            .disabled(index == store.apps.count - 1).help("Move \(app.name) right")
                            .accessibilityLabel("Move \(app.name) right")
                        Button { store.remove(app) } label: { Image(systemName: "minus.circle") }
                            .help("Remove \(app.name)").accessibilityLabel("Remove \(app.name)")
                    }.padding(.vertical, 4)
                }
            }
            .listStyle(.inset).frame(minHeight: 180)
            HStack {
                Button("Show Config File", action: store.revealConfiguration)
                Button("Reload", action: store.reload)
                Spacer()
                Button("Hide Bar", action: hideBar)
                Button("Show Touch Bar", action: showBar).buttonStyle(.borderedProminent)
            }
            Text("Close this window to keep using your bar. Hide Bar pauses it; Quit MacBar stops it.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(24).frame(minWidth: 640, minHeight: 580)
        .alert("MacBar", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
    }
}
