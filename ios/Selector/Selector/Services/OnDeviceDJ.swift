import Foundation
#if canImport(FoundationModels)
import FoundationModels

/// When a request is phrased in a way the built-in parser doesn't know, ask the model that
/// ships on the iPhone (iOS 26, Apple Intelligence). Nothing leaves the device.
@available(iOS 26.0, *)
@Generable
struct DJInstruction {
    @Guide(description: "One of: more_energy, less_energy, familiar_songs, surprising_songs, more_of_sound, less_of_sound, wrap_up, unknown")
    var action: String
    @Guide(description: "For more_of_sound or less_of_sound: one sound key from the list given in the instructions. Otherwise empty.")
    var sound: String
    @Guide(description: "For wrap_up: how many minutes remain. Otherwise 0.")
    var minutes: Int
}

@available(iOS 26.0, *)
enum OnDeviceModel {
    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    static func interpret(_ text: String, sounds: [String]) async -> DJIntent? {
        guard isAvailable else { return nil }
        let session = LanguageModelSession(instructions: """
            You translate what a party guest says to a DJ into one instruction. \
            Sounds the DJ can play: \(sounds.joined(separator: ", ")). \
            If the request does not fit any action, answer unknown.
            """)
        guard let r = try? await session.respond(to: text, generating: DJInstruction.self) else { return nil }
        let i = r.content
        switch i.action {
        case "more_energy": return .energy(up: true)
        case "less_energy": return .energy(up: false)
        case "familiar_songs": return .familiar
        case "surprising_songs": return .surprise
        case "more_of_sound": return sounds.contains(i.sound) ? .more(vibe: i.sound) : nil
        case "less_of_sound": return sounds.contains(i.sound) ? .less(vibe: i.sound) : nil
        case "wrap_up": return .wrap(minutes: min(max(i.minutes, 5), 120))
        default: return nil
        }
    }
}
#endif

enum OnDeviceDJ {
    /// nil when the phone has no on-device model, or it couldn't make sense of the request either.
    static func interpret(_ text: String, sounds: [String]) async -> DJIntent? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) { return await OnDeviceModel.interpret(text, sounds: sounds) }
        #endif
        return nil
    }
}
