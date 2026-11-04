import SonyKit

extension NoiseMode {
    var title: String {
        switch self {
        case .noiseCancelling: "Noise Cancelling"
        case .ambient: "Ambient Sound"
        case .windReduction: "Wind Noise Reduction"
        case .off: "Off"
        }
    }

    var shortTitle: String {
        switch self {
        case .noiseCancelling: "Noise Cancel"
        case .ambient: "Ambient"
        case .windReduction: "Wind"
        case .off: "Off"
        }
    }

    var symbol: String {
        switch self {
        case .noiseCancelling: "waveform.slash"
        case .ambient: "ear.and.waveform"
        case .windReduction: "wind"
        case .off: "circle.slash"
        }
    }

    var menuBarSymbol: String {
        switch self {
        case .noiseCancelling: "headphones.circle.fill"
        case .ambient: "ear.and.waveform"
        case .windReduction: "wind"
        case .off: "headphones"
        }
    }
}
