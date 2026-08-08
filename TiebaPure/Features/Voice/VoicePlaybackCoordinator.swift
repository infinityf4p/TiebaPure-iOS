import AVFoundation
import Combine
import Foundation
import UIKit

extension Notification.Name {
    static let tiebaVoicePlaybackWillStart = Notification.Name(
        "dev.infinityf4p.tiebapure.voicePlaybackWillStart"
    )
}

enum VoicePlaybackPhase: String, Equatable, Sendable {
    case idle
    case loading
    case playing
    case paused
    case completed
    case failed
}

struct VoicePlaybackState: Equatable, Sendable {
    let key: String?
    let phase: VoicePlaybackPhase
    let loadProgress: Double?
    let currentTime: TimeInterval
    let duration: TimeInterval
    let errorMessage: String?

    static let idle = VoicePlaybackState(
        key: nil,
        phase: .idle,
        loadProgress: nil,
        currentTime: 0,
        duration: 0,
        errorMessage: nil
    )

    static func loading(key: String, progress: Double?) -> VoicePlaybackState {
        VoicePlaybackState(
            key: key,
            phase: .loading,
            loadProgress: progress,
            currentTime: 0,
            duration: 0,
            errorMessage: nil
        )
    }

    static func playback(
        key: String,
        phase: VoicePlaybackPhase,
        currentTime: TimeInterval,
        duration: TimeInterval
    ) -> VoicePlaybackState {
        VoicePlaybackState(
            key: key,
            phase: phase,
            loadProgress: nil,
            currentTime: currentTime,
            duration: duration,
            errorMessage: nil
        )
    }

    static func failed(key: String?, message: String) -> VoicePlaybackState {
        VoicePlaybackState(
            key: key,
            phase: .failed,
            loadProgress: nil,
            currentTime: 0,
            duration: 0,
            errorMessage: message
        )
    }

    var playbackProgress: Double {
        guard duration > 0, currentTime.isFinite, duration.isFinite else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }
}

@MainActor
protocol VoiceAudioPlayer: AnyObject {
    var currentTime: TimeInterval { get set }
    var duration: TimeInterval { get }
    var isPlaying: Bool { get }
    var onCompletion: ((Bool) -> Void)? { get set }

    @discardableResult func play() -> Bool
    func pause()
    func stop()
}

@MainActor
protocol VoiceAudioPlayerCreating {
    func makePlayer(data: Data) throws -> any VoiceAudioPlayer
}

@MainActor
protocol VoiceAudioSessionControlling {
    func activate() throws
    func deactivate() throws
    func relinquish()
}

enum VoicePlaybackEngineError: Error, Equatable, LocalizedError {
    case invalidAudioData
    case unableToStartPlayback

    var errorDescription: String? {
        switch self {
        case .invalidAudioData:
            return "无法解析语音内容"
        case .unableToStartPlayback:
            return "语音播放失败"
        }
    }
}

@MainActor
final class SystemVoiceAudioPlayerFactory: VoiceAudioPlayerCreating {
    func makePlayer(data: Data) throws -> any VoiceAudioPlayer {
        try SystemVoiceAudioPlayer(data: data)
    }
}

@MainActor
private final class SystemVoiceAudioPlayer: NSObject, VoiceAudioPlayer, AVAudioPlayerDelegate {
    private let player: AVAudioPlayer
    var onCompletion: ((Bool) -> Void)?

    var currentTime: TimeInterval {
        get { player.currentTime }
        set { player.currentTime = newValue }
    }

    var duration: TimeInterval { player.duration }
    var isPlaying: Bool { player.isPlaying }

    init(data: Data) throws {
        guard data.isEmpty == false else {
            throw VoicePlaybackEngineError.invalidAudioData
        }
        do {
            player = try AVAudioPlayer(data: data)
        } catch {
            throw VoicePlaybackEngineError.invalidAudioData
        }
        super.init()
        player.delegate = self
        guard player.prepareToPlay() else {
            throw VoicePlaybackEngineError.invalidAudioData
        }
    }

    @discardableResult
    func play() -> Bool {
        player.play()
    }

    func pause() {
        player.pause()
    }

    func stop() {
        player.stop()
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            self?.onCompletion?(flag)
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor [weak self] in
            self?.onCompletion?(false)
        }
    }
}

@MainActor
final class SystemVoiceAudioSessionController: VoiceAudioSessionControlling {
    private let coordinator: any MediaAudioSessionCoordinating
    private var lease: MediaAudioSessionLease?

    init(coordinator: (any MediaAudioSessionCoordinating)? = nil) {
        self.coordinator = coordinator ?? MediaAudioSessionCoordinator.shared
    }

    func activate() throws {
        lease = try coordinator.acquire(
            owner: .voice,
            configuration: .voicePlayback
        )
    }

    func deactivate() throws {
        guard let lease else { return }
        guard coordinator.release(lease) else {
            throw MediaAudioSessionReleaseError.deactivationFailed
        }
        self.lease = nil
    }

    func relinquish() {
        guard let lease, coordinator.isCurrent(lease) == false else { return }
        self.lease = nil
    }
}

private enum MediaAudioSessionReleaseError: Error {
    case deactivationFailed
}

@MainActor
final class VoicePlaybackCoordinator: ObservableObject {
    static let shared = VoicePlaybackCoordinator()

    @Published private(set) var state: VoicePlaybackState = .idle

    private let loader: any VoiceAudioLoading
    private let playerFactory: any VoiceAudioPlayerCreating
    private let audioSession: any VoiceAudioSessionControlling
    private let notificationCenter: NotificationCenter
    private var notificationTokens: [NSObjectProtocol] = []
    private var loadTask: Task<Void, Never>?
    private var progressTask: Task<Void, Never>?
    private var audioSessionReleaseRetryTask: Task<Void, Never>?
    private var player: (any VoiceAudioPlayer)?
    private var generation: UInt64 = 0
    private var wasPlayingBeforeInterruption = false
    private var isAudioSessionInterrupted = false
    private var isApplicationInBackground = false
    private var ownsAudioSession = false
    private var audioSessionLeaseGeneration: UInt64 = 0

    init(
        loader: any VoiceAudioLoading = VoiceAudioClient.shared,
        playerFactory: (any VoiceAudioPlayerCreating)? = nil,
        audioSession: (any VoiceAudioSessionControlling)? = nil,
        notificationCenter: NotificationCenter = .default,
        observesSystemEvents: Bool = true
    ) {
        self.loader = loader
        self.playerFactory = playerFactory ?? SystemVoiceAudioPlayerFactory()
        self.audioSession = audioSession ?? SystemVoiceAudioSessionController()
        self.notificationCenter = notificationCenter
        if observesSystemEvents {
            observeSystemEvents()
        }
    }

    deinit {
        loadTask?.cancel()
        progressTask?.cancel()
        audioSessionReleaseRetryTask?.cancel()
        notificationTokens.forEach(notificationCenter.removeObserver)
    }

    func state(forMD5 md5: String) -> VoicePlaybackState {
        guard let key = VoiceAudioURLPolicy.normalizedMD5(md5), state.key == key else {
            return .idle
        }
        return state
    }

    func toggle(md5: String) {
        guard let key = VoiceAudioURLPolicy.normalizedMD5(md5) else {
            cancel()
            state = .failed(key: nil, message: VoiceAudioClientError.invalidMD5.localizedDescription)
            return
        }
        if isAudioSessionInterrupted {
            if state.phase == .paused {
                guard state.key == key else { return }
                resumeCurrent(preservingPauseOnActivationFailure: true)
                return
            }
            beginLoading(key: key)
            return
        }

        guard state.key == key else {
            beginLoading(key: key)
            return
        }
        switch state.phase {
        case .idle:
            beginLoading(key: key)
        case .loading:
            break
        case .playing:
            pauseCurrent(deactivateSession: true)
        case .paused:
            resumeCurrent()
        case .completed:
            replayCurrent()
        case .failed:
            beginLoading(key: key)
        }
    }

    func retry(md5: String) {
        guard let key = VoiceAudioURLPolicy.normalizedMD5(md5) else {
            cancel()
            state = .failed(key: nil, message: VoiceAudioClientError.invalidMD5.localizedDescription)
            return
        }
        if isAudioSessionInterrupted, state.phase == .paused { return }
        beginLoading(key: key)
    }

    func cancel() {
        generation &+= 1
        tearDownCurrentPlayback()
        state = .idle
    }

    func handleInterruptionBegan(reason: AVAudioSession.InterruptionReason? = nil) {
        isAudioSessionInterrupted = true
        let preventsAutomaticResume: Bool
        if #available(iOS 17.0, *) {
            preventsAutomaticResume = reason == .routeDisconnected
        } else {
            preventsAutomaticResume = false
        }
        switch state.phase {
        case .loading:
            cancel()
        case .playing:
            wasPlayingBeforeInterruption = preventsAutomaticResume == false
            pauseCurrent(deactivateSession: false, clearsInterruptionIntent: false)
        case .idle, .paused, .completed, .failed:
            break
        }
    }

    func handleInterruptionEnded(shouldResume: Bool) {
        isAudioSessionInterrupted = false
        let shouldResumePlayback = shouldResume
            && wasPlayingBeforeInterruption
            && isApplicationInBackground == false
        wasPlayingBeforeInterruption = false
        guard state.phase == .paused else { return }
        if shouldResumePlayback {
            resumeCurrent()
        } else {
            deactivateOwnedAudioSession()
        }
    }

    func handleRouteChange(reason: AVAudioSession.RouteChangeReason) {
        guard reason == .oldDeviceUnavailable else { return }
        switch state.phase {
        case .loading:
            cancel()
        case .playing:
            wasPlayingBeforeInterruption = false
            pauseCurrent(deactivateSession: true)
        case .paused:
            wasPlayingBeforeInterruption = false
            deactivateOwnedAudioSession()
        case .idle, .completed, .failed:
            deactivateOwnedAudioSession()
        }
    }

    func handleApplicationDidEnterBackground() {
        isApplicationInBackground = true
        wasPlayingBeforeInterruption = false
        switch state.phase {
        case .loading:
            cancel()
        case .playing:
            pauseCurrent(deactivateSession: true)
        case .paused:
            deactivateOwnedAudioSession()
        case .idle, .completed, .failed:
            deactivateOwnedAudioSession()
        }
    }

    func handleApplicationWillEnterForeground() {
        isApplicationInBackground = false
        wasPlayingBeforeInterruption = false
    }

    @discardableResult
    func handleVideoPlaybackWillStart() -> Bool {
        generation &+= 1
        let didReleaseAudioSession = tearDownCurrentPlayback(
            releasePolicy: .transferToExternalPlayback
        )
        state = .idle
        return didReleaseAudioSession
    }

    private func beginLoading(key: String) {
        generation &+= 1
        let requestGeneration = generation
        tearDownCurrentPlayback()
        state = .loading(key: key, progress: nil)

        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let payload = try await loader.load(md5: key) { [weak self] progress in
                    await self?.receiveLoadProgress(
                        progress,
                        key: key,
                        generation: requestGeneration
                    )
                }
                try Task.checkCancellation()
                guard isCurrent(key: key, generation: requestGeneration) else { return }

                let newPlayer = try playerFactory.makePlayer(data: payload.data)
                guard isCurrent(key: key, generation: requestGeneration) else {
                    newPlayer.stop()
                    return
                }
                newPlayer.onCompletion = { [weak self] successfully in
                    self?.receivePlaybackCompletion(
                        successfully: successfully,
                        key: key,
                        generation: requestGeneration
                    )
                }
                player = newPlayer
                notificationCenter.post(name: .tiebaVoicePlaybackWillStart, object: self)
                try activateOwnedAudioSession()
                guard newPlayer.play() else {
                    throw VoicePlaybackEngineError.unableToStartPlayback
                }
                isAudioSessionInterrupted = false
                wasPlayingBeforeInterruption = false
                state = .playback(
                    key: key,
                    phase: .playing,
                    currentTime: safeTime(newPlayer.currentTime),
                    duration: safeTime(newPlayer.duration)
                )
                startProgressUpdates(key: key, generation: requestGeneration)
            } catch is CancellationError {
                receiveCancellation(key: key, generation: requestGeneration)
            } catch let error as URLError where error.code == .cancelled {
                receiveCancellation(key: key, generation: requestGeneration)
            } catch {
                receiveFailure(error, key: key, generation: requestGeneration)
            }
        }
    }

    private func receiveLoadProgress(
        _ progress: BoundedURLSessionProgress,
        key: String,
        generation: UInt64
    ) {
        guard isCurrent(key: key, generation: generation), state.phase == .loading else { return }
        state = .loading(key: key, progress: progress.fractionCompleted)
    }

    private func receiveCancellation(key: String, generation: UInt64) {
        guard isCurrent(key: key, generation: generation) else { return }
        tearDownCurrentPlayback()
        state = .idle
    }

    private func receiveFailure(_ error: Error, key: String, generation: UInt64) {
        guard isCurrent(key: key, generation: generation) else { return }
        tearDownCurrentPlayback()
        state = .failed(
            key: key,
            message: (error as? LocalizedError)?.errorDescription ?? "语音加载失败"
        )
    }

    private func receivePlaybackCompletion(
        successfully: Bool,
        key: String,
        generation: UInt64
    ) {
        guard isCurrent(key: key, generation: generation), let player else { return }
        guard successfully else {
            receiveFailure(
                VoicePlaybackEngineError.unableToStartPlayback,
                key: key,
                generation: generation
            )
            return
        }
        progressTask?.cancel()
        progressTask = nil
        deactivateOwnedAudioSession()
        let duration = safeTime(player.duration)
        state = .playback(
            key: key,
            phase: .completed,
            currentTime: duration,
            duration: duration
        )
    }

    private func pauseCurrent(
        deactivateSession: Bool,
        clearsInterruptionIntent: Bool = true
    ) {
        guard let key = state.key, let player else { return }
        if clearsInterruptionIntent {
            wasPlayingBeforeInterruption = false
        }
        player.pause()
        progressTask?.cancel()
        progressTask = nil
        if deactivateSession {
            deactivateOwnedAudioSession()
        }
        state = .playback(
            key: key,
            phase: .paused,
            currentTime: safeTime(player.currentTime),
            duration: safeTime(player.duration)
        )
    }

    private func resumeCurrent(preservingPauseOnActivationFailure: Bool = false) {
        guard let key = state.key, let player else { return }
        do {
            notificationCenter.post(name: .tiebaVoicePlaybackWillStart, object: self)
            try activateOwnedAudioSession()
        } catch {
            if preservingPauseOnActivationFailure {
                deactivateOwnedAudioSession()
                return
            }
            receiveFailure(error, key: key, generation: generation)
            return
        }
        do {
            guard player.play() else {
                throw VoicePlaybackEngineError.unableToStartPlayback
            }
            isAudioSessionInterrupted = false
            wasPlayingBeforeInterruption = false
            state = .playback(
                key: key,
                phase: .playing,
                currentTime: safeTime(player.currentTime),
                duration: safeTime(player.duration)
            )
            startProgressUpdates(key: key, generation: generation)
        } catch {
            receiveFailure(error, key: key, generation: generation)
        }
    }

    private func replayCurrent() {
        guard let player else {
            if let key = state.key { beginLoading(key: key) }
            return
        }
        player.currentTime = 0
        resumeCurrent()
    }

    private func startProgressUpdates(key: String, generation: UInt64) {
        progressTask?.cancel()
        progressTask = Task { @MainActor [weak self] in
            while Task.isCancelled == false {
                do {
                    try await Task.sleep(nanoseconds: 100_000_000)
                } catch {
                    return
                }
                guard let self,
                      isCurrent(key: key, generation: generation),
                      state.phase == .playing,
                      let player else {
                    return
                }
                state = .playback(
                    key: key,
                    phase: .playing,
                    currentTime: safeTime(player.currentTime),
                    duration: safeTime(player.duration)
                )
            }
        }
    }

    private func isCurrent(key: String, generation: UInt64) -> Bool {
        self.generation == generation && state.key == key
    }

    private enum AudioSessionReleasePolicy {
        case retry
        case transferToExternalPlayback
    }

    @discardableResult
    private func tearDownCurrentPlayback(
        releasePolicy: AudioSessionReleasePolicy = .retry
    ) -> Bool {
        loadTask?.cancel()
        loadTask = nil
        progressTask?.cancel()
        progressTask = nil
        player?.onCompletion = nil
        player?.stop()
        player = nil
        wasPlayingBeforeInterruption = false
        switch releasePolicy {
        case .retry:
            deactivateOwnedAudioSession()
            return true
        case .transferToExternalPlayback:
            return relinquishAudioSessionToExternalPlayback()
        }
    }

    private func activateOwnedAudioSession() throws {
        cancelAudioSessionReleaseRetry()
        audioSessionLeaseGeneration &+= 1
        ownsAudioSession = true
        try audioSession.activate()
    }

    private func relinquishAudioSessionToExternalPlayback() -> Bool {
        audioSessionLeaseGeneration &+= 1
        cancelAudioSessionReleaseRetry()
        guard ownsAudioSession else {
            audioSession.relinquish()
            return true
        }
        do {
            try audioSession.deactivate()
            audioSession.relinquish()
            ownsAudioSession = false
            return true
        } catch {
            scheduleAudioSessionReleaseRetry()
            return false
        }
    }

    private func deactivateOwnedAudioSession() {
        guard ownsAudioSession else {
            cancelAudioSessionReleaseRetry()
            return
        }
        guard tryDeactivateOwnedAudioSession() == false else { return }
        scheduleAudioSessionReleaseRetry()
    }

    private func tryDeactivateOwnedAudioSession() -> Bool {
        do {
            try audioSession.deactivate()
            ownsAudioSession = false
            cancelAudioSessionReleaseRetry()
            return true
        } catch {
            return false
        }
    }

    private func scheduleAudioSessionReleaseRetry() {
        guard ownsAudioSession, audioSessionReleaseRetryTask == nil else { return }
        let leaseGeneration = audioSessionLeaseGeneration
        audioSessionReleaseRetryTask = Task { @MainActor [weak self] in
            for delay in [100_000_000, 300_000_000, 900_000_000] as [UInt64] {
                do {
                    try await Task.sleep(nanoseconds: delay)
                } catch {
                    return
                }
                guard let self else { return }
                guard self.audioSessionLeaseGeneration == leaseGeneration else {
                    self.audioSessionReleaseRetryTask = nil
                    return
                }
                guard self.ownsAudioSession else {
                    self.audioSessionReleaseRetryTask = nil
                    return
                }
                if self.tryDeactivateOwnedAudioSession() {
                    return
                }
            }
            self?.audioSessionReleaseRetryTask = nil
        }
    }

    private func cancelAudioSessionReleaseRetry() {
        audioSessionReleaseRetryTask?.cancel()
        audioSessionReleaseRetryTask = nil
    }

    private func safeTime(_ value: TimeInterval) -> TimeInterval {
        value.isFinite && value > 0 ? value : 0
    }

    private func observeSystemEvents() {
        notificationTokens.append(notificationCenter.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                self?.receiveInterruption(notification)
            }
        })
        notificationTokens.append(notificationCenter.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                self?.receiveRouteChange(notification)
            }
        })
        notificationTokens.append(notificationCenter.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleApplicationDidEnterBackground()
            }
        })
        notificationTokens.append(notificationCenter.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleApplicationWillEnterForeground()
            }
        })
    }

    private func receiveInterruption(_ notification: Notification) {
        guard let rawType = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber)?.uintValue,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else {
            return
        }
        switch type {
        case .began:
            let rawReason = (notification.userInfo?[AVAudioSessionInterruptionReasonKey] as? NSNumber)?.uintValue
            let reason = rawReason.flatMap(AVAudioSession.InterruptionReason.init(rawValue:))
            handleInterruptionBegan(reason: reason)
        case .ended:
            let rawOptions = (notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? NSNumber)?.uintValue ?? 0
            handleInterruptionEnded(
                shouldResume: AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume)
            )
        @unknown default:
            break
        }
    }

    private func receiveRouteChange(_ notification: Notification) {
        guard let rawReason = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? NSNumber)?.uintValue,
              let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason) else {
            return
        }
        handleRouteChange(reason: reason)
    }
}
