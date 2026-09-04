import SwiftUI
import MediaPlayer
import MusicKit
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

// MARK: - Now Playing Track

struct NowPlayingTrack: Equatable {
    let title: String
    let artist: String
    let bpm: Int?
    let isPlaying: Bool
    let artworkURL: URL?

    static func == (lhs: NowPlayingTrack, rhs: NowPlayingTrack) -> Bool {
        lhs.title == rhs.title &&
        lhs.artist == rhs.artist &&
        lhs.bpm == rhs.bpm &&
        lhs.isPlaying == rhs.isPlaying
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
@MainActor final class AnyMusicController: ObservableObject, MusicControlling {
    let service: MusicService

    @Published var nowPlaying: NowPlayingTrack? = nil
    @Published var isAuthorized: Bool = false

    private let _refresh: () -> Void
    private let _requestAccess: () async -> Void
    private let _togglePlayPause: () -> Void
    private let _skipForward: () -> Void
    private let _skipBack: () -> Void

    private var cancellables: Set<AnyCancellable> = []

    init<C>(_ base: C) where C: MusicControlling {
        self.service = base.service

        self.nowPlaying = base.nowPlaying
        self.isAuthorized = base.isAuthorized

        self._refresh = { base.refresh() }
        self._requestAccess = { await base.requestAccess() }
        self._togglePlayPause = { base.togglePlayPause() }
        self._skipForward = { base.skipForward() }
        self._skipBack = { base.skipBack() }

        base.objectWillChange
            .sink { [weak self] _ in
                self?.nowPlaying = base.nowPlaying
                self?.isAuthorized = base.isAuthorized
            }
            .store(in: &cancellables)
    }

    func refresh() { _refresh() }
    func requestAccess() async { await _requestAccess() }
    func togglePlayPause() { _togglePlayPause() }
    func skipForward() { _skipForward() }
    func skipBack() { _skipBack() }
}

// MARK: - Concrete Apple Music Controller

@MainActor
final class AppleMusicController: ObservableObject, MusicControlling {
    @Published var nowPlaying: NowPlayingTrack? = nil
    @Published var isAuthorized: Bool = false

    let service: MusicService = .appleMusic
    private let player = MPMusicPlayerController.systemMusicPlayer

    init() {
        refresh()
    }

    func refresh() {
        // MediaPlayer is enough to control playback; MusicKit is best-effort for artwork.
        let mpOK = MPMediaLibrary.authorizationStatus() == .authorized
        isAuthorized = mpOK
        if mpOK { Task { await updateNowPlaying() } }
    }

    func requestAccess() async {
        let mp = await MPMediaLibrary.requestAuthorization()
        // Request MusicKit too when available so artwork can resolve — failure is non-fatal.
        _ = await MusicAuthorization.request()
        isAuthorized = mp == .authorized
        if mp == .authorized { await updateNowPlaying() }
    }

    func togglePlayPause() {
        player.playbackState == .playing ? player.pause() : player.play()
        Task { await updateNowPlaying() }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func skipForward() { player.skipToNextItem(); Task { await updateNowPlaying() } }
    func skipBack()    { player.skipToPreviousItem(); Task { await updateNowPlaying() } }

    private func updateNowPlaying() async {
        guard let item = player.nowPlayingItem else { nowPlaying = nil; return }

        var artworkURL: URL? = nil
        let storeID = item.playbackStoreID
        if !storeID.isEmpty, MusicAuthorization.currentStatus == .authorized {
            do {
                let request = MusicCatalogResourceRequest<Song>(
                    matching: \.id,
                    equalTo: MusicItemID(storeID)
                )
                let response = try await request.response()
                artworkURL = response.items.first?.artwork?.url(width: 88, height: 88)
            } catch { }
        }

        nowPlaying = NowPlayingTrack(
            title:      item.title  ?? "Unknown",
            artist:     item.artist ?? "Unknown Artist",
            bpm:        item.beatsPerMinute > 0 ? item.beatsPerMinute : nil,
            isPlaying:  player.playbackState == .playing,
            artworkURL: artworkURL
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
