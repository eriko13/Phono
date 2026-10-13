import AVFoundation
import Observation
import PushToTalk

/// A walkie-talkie channel with nobody on the other end.
///
/// Once Phono joins it, iOS shows a Talk button in the status bar or the
/// Dynamic Island. Pressing it starts Phono in the background with the
/// microphone on, which iOS allows no other way. So dictation works without
/// opening the app, even after iOS has closed it.
@MainActor
@Observable
final class TalkChannel: NSObject {
    /// iOS allows one channel at a time, for the whole phone.
    nonisolated private static let uuid = UUID(uuidString: "5E3C6B1A-7F0D-4E83-9C2A-0D1B8F4A6E27")!
    nonisolated private static let descriptor = PTChannelDescriptor(name: "Phono", image: nil)

    private(set) var isJoined = false
    private(set) var error: String?

    /// The system turned the microphone on for a Talk press.
    @ObservationIgnored var onActivate: () -> Void = {}
    /// The Talk press ended.
    @ObservationIgnored var onEnd: () -> Void = {}

    @ObservationIgnored private var manager: PTChannelManager?

    /// Call at launch. iOS restores a joined channel only after this, and a
    /// Talk press launches the app in the background to get here.
    func start() async {
        do {
            let manager = try await PTChannelManager.channelManager(delegate: self, restorationDelegate: self)
            self.manager = manager
            isJoined = manager.activeChannelUUID == Self.uuid
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Only works while the app is in front.
    func join() {
        error = nil
        manager?.requestJoinChannel(channelUUID: Self.uuid, descriptor: Self.descriptor)
    }

    func leave() {
        manager?.leaveChannel(channelUUID: Self.uuid)
    }
}

extension TalkChannel: PTChannelManagerDelegate, PTChannelRestorationDelegate {
    nonisolated func channelManager(_ channelManager: PTChannelManager, didJoinChannel channelUUID: UUID, reason: PTChannelJoinReason) {
        Task { @MainActor in self.isJoined = true }
    }

    nonisolated func channelManager(_ channelManager: PTChannelManager, didLeaveChannel channelUUID: UUID, reason: PTChannelLeaveReason) {
        Task { @MainActor in self.isJoined = false }
    }

    nonisolated func channelManager(_ channelManager: PTChannelManager, failedToJoinChannel channelUUID: UUID, error: any Error) {
        let message = error.localizedDescription
        Task { @MainActor in self.error = message }
    }

    nonisolated func channelManager(_ channelManager: PTChannelManager, failedToBeginTransmittingInChannel channelUUID: UUID, error: any Error) {
        let message = error.localizedDescription
        Task { @MainActor in self.error = message }
    }

    nonisolated func channelManager(_ channelManager: PTChannelManager, channelUUID: UUID, didBeginTransmittingFrom source: PTChannelTransmitRequestSource) {
        // The system activates the session, but only one that can record.
        let session = AVAudioSession.sharedInstance()
        if session.category != .playAndRecord {
            try? session.setCategory(.playAndRecord, mode: .default)
        }
    }

    nonisolated func channelManager(_ channelManager: PTChannelManager, channelUUID: UUID, didEndTransmittingFrom source: PTChannelTransmitRequestSource) {
        Task { @MainActor in self.onEnd() }
    }

    nonisolated func channelManager(_ channelManager: PTChannelManager, didActivate audioSession: AVAudioSession) {
        Task { @MainActor in self.onActivate() }
    }

    nonisolated func channelManager(_ channelManager: PTChannelManager, didDeactivate audioSession: AVAudioSession) {}

    nonisolated func channelManager(_ channelManager: PTChannelManager, receivedEphemeralPushToken pushToken: Data) {}

    /// Nobody else is on the channel, so no push should arrive.
    nonisolated func incomingPushResult(channelManager: PTChannelManager, channelUUID: UUID, pushPayload: [String: Any]) -> PTPushResult {
        .leaveChannel
    }

    nonisolated func channelDescriptor(restoredChannelUUID channelUUID: UUID) -> PTChannelDescriptor {
        Self.descriptor
    }
}
