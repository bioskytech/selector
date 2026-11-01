import SwiftUI

@main
struct SelectorApp: App {
    @State private var app = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}

struct RootView: View {
    @Environment(AppState.self) private var app
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var app = app
        NavigationStack(path: $app.path) {
            Group {
                if app.catalog == nil {
                    VStack(spacing: 12) {
                        ProgressView().tint(Theme.ink)
                        Text("Opening the crate…").font(.text(14)).foregroundStyle(Theme.ink2)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.bg.ignoresSafeArea())
                } else {
                    TonightView()
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .brief: BriefView()
                case .plan: PlanView()
                case .songs: SongsView()
                case .playing: PlayingView()
                case .recap: RecapView()
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if app.player.isActive && app.current != .playing {
                MiniPlayer()
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = app.toast {
                ToastView(text: toast)
                    .padding(.bottom, app.player.isActive && app.current != .playing ? 84 : 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: app.toast)
        .sheet(item: $app.sheet) { sheet in
            switch sheet {
            case .occasion: OccasionSheet().presentationDetents([.medium, .large])
            case .length: LengthSheet().presentationDetents([.medium, .large])
            case .crowd: CrowdSheet().presentationDetents([.medium, .large])
            case .taste: TasteSheet().presentationDetents([.medium, .large])
            case .connect: ConnectSheet()
            case .steer: SteerSheet()
            }
        }
        .task { await app.load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background || phase == .inactive { app.saveCurrentNight() }
        }
    }
}
