import Foundation

protocol StringRepresentableEnum {
    var rawValue: String { get }
    init?(rawValue: String)
}

enum AppConstants {
    static let clientVersion =
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
}

enum VideoDynamicRange: String {
    case sdr
    case hdr10
    case hlg
    case hdr10Plus
    case dolbyVision
    case unknown
}

enum PlaybackBackendDirective: String {
    case mpv
    case native
}

enum VideoCapabilityDetector {
    enum AppleTVGeneration: String {
        case hd
        case k4Gen1
        case k4Gen2
        case k4Gen3
        case unknown
    }
}

enum PlaybackQualityProfile: String {
    case auto
    case compatibility
    case highQuality

    static func recommended(for generation: VideoCapabilityDetector.AppleTVGeneration)
        -> PlaybackQualityProfile
    {
        return .compatibility
    }
}
