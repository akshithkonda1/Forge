import SwiftUI
import MediaPlayer
import Combine

// MARK: - Music Service

enum MusicService: String, CaseIterable, Equatable {
    case appleMusic = "Apple Music"

    var iconName: String {
        switch self {
        case .appleMusic: return "music.note"
        }
    }

    var accentColor: Color {
        switch self {
        case .appleMusic: return Color(hex: "FA2D48") // Apple Music red/pink-ish
        }
    }
}

// MARK: - Protocol & Type Erasure

@MainActor protocol MusicControlling: ObservableObject {
    var service: MusicService { get }
    var nowPlaying: NowPlayingTrack? { get set }
    var isAuthorized: Bool { get set }

    func refresh()
    func requestAccess() async
    func togglePlayPause()
    func skipForward()
    func skipBack()
}

/// Type-erased wrapper so views don't depend on concrete controller types
@MainActor final class AnyMusicController: MusicControlling {
    let service: MusicService

    @Published var nowPlaying: NowPlayingTrack? = nil
    @Published var isAuthorized: Bool = false

    private let _refresh: () -> Void
    private let _requestAccess: () async -> Void
    private let _togglePlayPause: () -> Void
    private let _skipForward: () -> Void
    private let _skipBack: () -> Void

    private var cancellables: Set<AnyCancellable> = []

    init<C: MusicControlling>(_ base: C) {
        self.service = base.service
        // Mirror base's publishers into our own @Published vars
        base.publisher(for: \C.nowPlaying)
            .sink { [weak self] in self?.nowPlaying = $0 }
            .store(in: &cancellables)

        base.publisher(for: \C.isAuthorized)
            .sink { [weak self] in self?.isAuthorized = $0 }
            .store(in: &cancellables)

        self._refresh = { base.refresh() }
        self._requestAccess = { await base.requestAccess() }
        self._togglePlayPause = { base.togglePlayPause() }
        self._skipForward = { base.skipForward() }
        self._skipBack = { base.skipBack() }
    }

    func refresh() { _refresh() }
    func requestAccess() async { await _requestAccess() }
    func togglePlayPause() { _togglePlayPause() }
    func skipForward() { _skipForward() }
    func skipBack() { _skipBack() }
}

// Convenience to expose KeyPath publisher from any ObservableObject
private extension ObservableObject {
    func publisher<Value>(for keyPath: KeyPath<Self, Value>) -> AnyPublisher<Value, Never> {
        // This uses Combine's mirror to emit values when objectWillChange fires
        // and then map to the latest value at subscription time and on each change.
        let initial = Just(self[keyPath: keyPath]).eraseToAnyPublisher()
        let changes = objectWillChange
            .map { [weak self] _ in self?[keyPath: keyPath] }
            .compactMap { $0 }
            .eraseToAnyPublisher()
        return initial.merge(with: changes).eraseToAnyPublisher()
    }
}

// MARK: - Concrete Apple Music Controller

@MainActor
final class AppleMusicController: MusicControlling {
    @Published var nowPlaying: NowPlayingTrack? = nil
    @Published var isAuthorized: Bool = false

    let service: MusicService = .appleMusic
    private let player = MPMusicPlayerController.systemMusicPlayer

    init() {
        refresh()
    }

    func refresh() {
        isAuthorized = MPMediaLibrary.authorizationStatus() == .authorized
        if isAuthorized { updateNowPlaying() }
    }

    func requestAccess() async {
        let status = await MPMediaLibrary.requestAuthorization()
        isAuthorized = status == .authorized
        if isAuthorized { updateNowPlaying() }
    }

    func togglePlayPause() {
        player.playbackState == .playing ? player.pause() : player.play()
        updateNowPlaying()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func skipForward() { player.skipToNextItem(); updateNowPlaying() }
    func skipBack()    { player.skipToPreviousItem(); updateNowPlaying() }

    private func updateNowPlaying() {
        guard let item = player.nowPlayingItem else { nowPlaying = nil; return }
        nowPlaying = NowPlayingTrack(
            title:     item.title  ?? "Unknown",
            artist:    item.artist ?? "Unknown Artist",
            bpm:       item.beatsPerMinute > 0 ? item.beatsPerMinute : nil,
            isPlaying: player.playbackState == .playing
        )
    }
}

// MARK: - Factory

@MainActor
enum MusicControllerFactory {
    static func make(for service: MusicService) -> AnyMusicController {
        switch service {
        case .appleMusic:
            return AnyMusicController(AppleMusicController())
        }
    }
}

