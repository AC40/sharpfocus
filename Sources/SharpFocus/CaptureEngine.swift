import AppKit
import CoreImage
import ScreenCaptureKit

/// One ScreenCaptureKit stream per display, feeding frames into the overlay's
/// capture layer. The overlay windows themselves are excluded from capture so
/// the overlay always shows what's *behind* it.
final class CaptureEngine {

    /// Called on the main queue whenever a stream dies unexpectedly.
    var onStreamStopped: (() -> Void)?

    private static let ciContext = CIContext(options: [.cacheIntermediates: false])

    private final class DisplayStream: NSObject, SCStreamOutput, SCStreamDelegate {
        private(set) var stream: SCStream?
        private weak var targetLayer: CALayer?
        /// Keeps the displayed frame's backing alive while it's on screen.
        private var displayedBuffer: Any?
        private let sampleQueue = DispatchQueue(label: "sharpfocus.capture", qos: .userInteractive)
        private var frameCount = 0
        private var bufferPool: CVPixelBufferPool?
        private let scale: CGFloat
        var onStopped: (() -> Void)?
        /// Skip frame processing entirely (e.g. while Mission Control is up).
        var paused = false

        init(
            filter: SCContentFilter, configuration: SCStreamConfiguration,
            targetLayer: CALayer, scale: CGFloat
        ) {
            self.targetLayer = targetLayer
            self.scale = scale
            super.init()
            CVPixelBufferPoolCreate(
                nil, nil,
                [
                    kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                    kCVPixelBufferWidthKey: configuration.width,
                    kCVPixelBufferHeightKey: configuration.height,
                    kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
                ] as CFDictionary,
                &bufferPool)
            let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
            self.stream = stream
            try? stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        }

        func stream(
            _ stream: SCStream,
            didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
            of type: SCStreamOutputType
        ) {
            guard
                !paused,
                type == .screen,
                sampleBuffer.isValid,
                let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
            else { return }

            // Filter once per delivered frame (frames only arrive when content
            // changes), so the window server composites plain contents with no
            // per-frame filtering. Settings are read live so slider changes
            // apply to the next frame.
            let settings = Settings.shared
            let saturation = 1.0 - settings.grayscale
            let blurRadius = settings.blurRadius
            let needsFilter = saturation < 0.999 || blurRadius > 0.1

            let surface: IOSurfaceRef
            let retained: Any
            if needsFilter {
                guard let pool = bufferPool else { return }
                var outBuffer: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outBuffer)
                guard let outBuffer else { return }
                var image = CIImage(cvPixelBuffer: pixelBuffer)
                let extent = image.extent
                if blurRadius > 0.1 {
                    image = image.clampedToExtent()
                        .applyingFilter("CIGaussianBlur", parameters: [
                            kCIInputRadiusKey: blurRadius * scale,
                        ])
                        .cropped(to: extent)
                }
                if saturation < 0.999 {
                    image = image.applyingFilter("CIColorControls", parameters: [
                        kCIInputSaturationKey: saturation,
                    ])
                }
                CaptureEngine.ciContext.render(image, to: outBuffer)
                guard let outSurface = CVPixelBufferGetIOSurface(outBuffer)?.takeUnretainedValue()
                else { return }
                surface = outSurface
                retained = outBuffer
            } else {
                // No filtering requested — show the raw frame.
                guard let rawSurface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue()
                else { return }
                surface = rawSurface
                retained = sampleBuffer
            }

            frameCount += 1
            if frameCount == 1 || frameCount % 600 == 0 {
                NSLog("SharpFocus: capture frame #\(frameCount)")
            }

            DispatchQueue.main.async { [weak self] in
                guard let self, let layer = self.targetLayer else { return }
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                layer.contents = surface
                CATransaction.commit()
                self.displayedBuffer = retained
            }
        }

        func stream(_ stream: SCStream, didStopWithError error: Error) {
            NSLog("SharpFocus: capture stream stopped: \(error.localizedDescription)")
            DispatchQueue.main.async { [weak self] in self?.onStopped?() }
        }

        func stop() async {
            try? await stream?.stopCapture()
            stream = nil
            displayedBuffer = nil
        }
    }

    private var streams: [DisplayStream] = []
    private(set) var isRunning = false

    static var hasScreenRecordingPermission: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Starts one stream per display. `excludedWindowNumbers` are our overlay
    /// windows, which must not show up in their own capture.
    func start(
        excludedWindowNumbers: [Int],
        layersByDisplay: [CGDirectDisplayID: CALayer]
    ) async {
        await stop()

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: false)
        } catch {
            NSLog("SharpFocus: cannot enumerate shareable content: \(error.localizedDescription)")
            return
        }

        let excludedIDs = Set(excludedWindowNumbers.map { CGWindowID($0) })
        let excludedWindows = content.windows.filter { excludedIDs.contains($0.windowID) }

        for display in content.displays {
            guard let layer = layersByDisplay[display.displayID] else { continue }

            let scale = NSScreen.screens
                .first {
                    $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                        as? CGDirectDisplayID == display.displayID
                }?
                .backingScaleFactor ?? 2

            let configuration = SCStreamConfiguration()
            configuration.width = Int(CGFloat(display.width) * scale)
            configuration.height = Int(CGFloat(display.height) * scale)
            configuration.pixelFormat = kCVPixelFormatType_32BGRA
            // The filtered background is de-emphasized content; 15 fps keeps
            // it feeling live at half the compositing cost of 30 fps.
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 15)
            configuration.queueDepth = 5
            configuration.showsCursor = false

            let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
            let displayStream = DisplayStream(
                filter: filter, configuration: configuration, targetLayer: layer, scale: scale)
            displayStream.onStopped = { [weak self] in self?.onStreamStopped?() }
            do {
                try await displayStream.stream?.startCapture()
                streams.append(displayStream)
            } catch {
                NSLog("SharpFocus: failed to start capture for display \(display.displayID): \(error.localizedDescription)")
            }
        }
        isRunning = !streams.isEmpty
    }

    func stop() async {
        for stream in streams {
            await stream.stop()
        }
        streams = []
        isRunning = false
    }

    /// Cheap on/off for frame processing without tearing down the streams
    /// (used while Mission Control is active).
    func setPaused(_ paused: Bool) {
        for stream in streams {
            stream.paused = paused
        }
    }
}
