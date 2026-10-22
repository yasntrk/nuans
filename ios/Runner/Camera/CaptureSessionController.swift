import AVFoundation
import Flutter

/// Owns the AVFoundation session: device selection, manual locks, the burst and
/// the reduction of its regions.
///
/// Every mutation runs on `sessionQueue`, every preview frame on `videoQueue`.
/// The two never touch the same state without the queue hop, because a capture
/// reconfiguring the session while a preview frame is being measured is exactly
/// the kind of race that shows up once a week on one device model.
final class CaptureSessionController: NSObject {
    /// Preview frame rate. 30 is plenty for a traffic light and leaves the
    /// thermal headroom that a locked, minimum-ISO sensor needs.
    private static let previewFrameRate: Int32 = 30

    private let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.nuans.app.camera.session")
    private let videoQueue = DispatchQueue(label: "com.nuans.app.camera.video")
    private let metricsComputer = PreviewMetricsComputer()
    private let store = CaptureStore()
    private let textureRegistry: FlutterTextureRegistry

    private var device: AVCaptureDevice?
    private var deviceInput: AVCaptureDeviceInput?
    private var capabilities: CameraCapabilities?
    private var bayerFormat: OSType?
    private var unguardedPreviewConfig: PreviewConfig?
    private var previewTexture: PreviewTexture?
    private var latestPreviewBuffer: CVPixelBuffer?
    private var focusObservation: NSKeyValueObservation?
    private var interruptionObservers: [NSObjectProtocol] = []
    private var burst: BurstCollector?
    private var isLocked = false

    /// Preview state is written on `sessionQueue` and read on `videoQueue`, so
    /// it is guarded rather than merely assigned.
    private let previewLock = NSLock()
    private var lastMetricsTimestamp: Int64 = 0

    /// Set by the plugin so out-of-band failures and progress can reach Dart.
    var events: ShadeCameraFlutterApi?

    /// The live region configuration, safe to touch from either queue.
    private var previewConfig: PreviewConfig? {
        get {
            previewLock.lock()
            defer { previewLock.unlock() }
            return unguardedPreviewConfig
        }
        set {
            previewLock.lock()
            unguardedPreviewConfig = newValue
            previewLock.unlock()
        }
    }

    init(textureRegistry: FlutterTextureRegistry) {
        self.textureRegistry = textureRegistry
        super.init()
    }

    // MARK: - Initialisation and capability probing

    func initialize(completion: @escaping (Result<CameraCapabilities, Error>) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            do {
                let probed = try self.configureSession()
                self.capabilities = probed
                completion(.success(probed))
            } catch {
                completion(.failure(error))
            }
        }
    }

    /// Selects the main rear wide lens and builds the session around it.
    ///
    /// `builtInWideAngleCamera` is requested by name rather than taking a
    /// virtual device such as `builtInTripleCamera`: a virtual device switches
    /// lenses on its own as the subject distance changes, and a measurement
    /// taken through a different lens than the profile was built for is not
    /// comparable. Zoom is pinned to 1 for the same reason.
    private func configureSession() throws -> CameraCapabilities {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            throw ShadeCameraFailure(
                .permissionDenied,
                "camera access has not been granted"
            )
        }
        guard
            let device = AVCaptureDevice.default(
                .builtInWideAngleCamera,
                for: .video,
                position: .back
            )
        else {
            throw ShadeCameraFailure(
                .deviceUnavailable,
                "this device has no rear wide-angle camera"
            )
        }
        self.device = device

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        if let existing = deviceInput {
            session.removeInput(existing)
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw ShadeCameraFailure(.configurationFailed, "cannot add the camera input")
        }
        session.addInput(input)
        deviceInput = input

        if !session.outputs.contains(photoOutput) {
            guard session.canAddOutput(photoOutput) else {
                throw ShadeCameraFailure(
                    .configurationFailed,
                    "cannot add the photo output"
                )
            }
            session.addOutput(photoOutput)
        }
        // Speed, not quality: this is what turns off the computational stack.
        // Deep Fusion, HDR fusion and night mode all merge several exposures
        // with local tone mapping, which destroys the one thing a colour
        // measurement needs, namely a known transfer function.
        photoOutput.maxPhotoQualityPrioritization = .speed
        if photoOutput.isAppleProRAWSupported {
            // Apple ProRAW is already demosaiced and tone-mapped. Bayer RAW is
            // the sensor as it was read out, which is the only thing worth
            // calibrating.
            photoOutput.isAppleProRAWEnabled = false
        }

        if !session.outputs.contains(videoOutput) {
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String:
                    kCVPixelFormatType_32BGRA,
            ]
            videoOutput.alwaysDiscardsLateVideoFrames = true
            guard session.canAddOutput(videoOutput) else {
                throw ShadeCameraFailure(
                    .configurationFailed,
                    "cannot add the preview output"
                )
            }
            session.addOutput(videoOutput)
            videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        }

        try selectHighestResolutionFormat(on: device)
        bayerFormat = photoOutput.availableRawPhotoPixelFormatTypes.first {
            AVCapturePhotoOutput.isBayerRAWPixelFormat($0)
        }
        observeInterruptions()

        return buildCapabilities(for: device)
    }

    private func selectHighestResolutionFormat(on device: AVCaptureDevice) throws {
        let candidates = device.formats.filter { $0.mediaType == .video }
        let best = candidates.max { lhs, rhs in
            photoArea(of: lhs) < photoArea(of: rhs)
        }
        guard let best else {
            throw ShadeCameraFailure(
                .configurationFailed,
                "the camera reports no usable format"
            )
        }
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        device.activeFormat = best
        device.videoZoomFactor = 1
        let duration = CMTime(value: 1, timescale: Self.previewFrameRate)
        device.activeVideoMinFrameDuration = duration
        device.activeVideoMaxFrameDuration = duration
        if let maximum = best.supportedMaxPhotoDimensions.last {
            photoOutput.maxPhotoDimensions = maximum
        }
    }

    private func photoArea(of format: AVCaptureDevice.Format) -> Int64 {
        guard let dimensions = format.supportedMaxPhotoDimensions.last else { return 0 }
        return Int64(dimensions.width) * Int64(dimensions.height)
    }

    private func buildCapabilities(for device: AVCaptureDevice) -> CameraCapabilities {
        let format = device.activeFormat
        let supportsManual = device.isExposureModeSupported(.custom)
        let supportsWhiteBalanceLock =
            device.isLockingWhiteBalanceWithCustomDeviceGainsSupported
        let supportsFocusLock = device.isFocusModeSupported(.locked)
        let hasRaw = bayerFormat != nil

        var limitations: [String] = []
        if !supportsManual { limitations.append("noManualSensor") }
        if !hasRaw { limitations.append("noRawSupport") }
        if !supportsWhiteBalanceLock { limitations.append("whiteBalanceNotLockable") }
        if !supportsFocusLock { limitations.append("focusNotLockable") }

        let dimensions = format.supportedMaxPhotoDimensions.last
            ?? CMVideoDimensions(width: 0, height: 0)
        return CameraCapabilities(
            tier: limitations.isEmpty ? .full : .limited,
            supportsManualSensor: supportsManual,
            supportsBayerRaw: hasRaw,
            supportsWhiteBalanceLock: supportsWhiteBalanceLock,
            supportsFocusLock: supportsFocusLock,
            minIso: Int64(format.minISO),
            maxIso: Int64(format.maxISO),
            minExposureSeconds: CMTimeGetSeconds(format.minExposureDuration),
            maxExposureSeconds: CMTimeGetSeconds(format.maxExposureDuration),
            defaultFormat: hasRaw ? .bayerRaw : .processedLinearisable,
            deviceModel: DeviceIdentity.hardwareModel,
            lensId: device.uniqueID,
            sensorWidthPixels: Int64(dimensions.width),
            sensorHeightPixels: Int64(dimensions.height),
            limitationCodes: limitations,
            focalLengthMillimeters: nil
        )
    }

    private func observeInterruptions() {
        guard interruptionObservers.isEmpty else { return }
        let centre = NotificationCenter.default
        interruptionObservers.append(
            centre.addObserver(
                forName: AVCaptureSession.wasInterruptedNotification,
                object: session,
                queue: nil
            ) { [weak self] note in
                self?.reportInterruption(note)
            }
        )
        interruptionObservers.append(
            centre.addObserver(
                forName: AVCaptureSession.runtimeErrorNotification,
                object: session,
                queue: nil
            ) { [weak self] _ in
                self?.events?.onCameraError(
                    error: ShadeCameraFailure(
                        .interrupted,
                        "the capture session reported a runtime error",
                        recoverable: true
                    ).event
                ) { _ in }
            }
        )
    }

    private func reportInterruption(_ note: Notification) {
        let raw = note.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int
        let reason: SessionInterruption
        switch AVCaptureSession.InterruptionReason(rawValue: raw ?? -1) {
        case .videoDeviceNotAvailableInBackground:
            reason = .backgrounded
        case .videoDeviceInUseByAnotherClient:
            reason = .deviceInUseByAnotherClient
        case .videoDeviceNotAvailableDueToSystemPressure:
            reason = .thermalThrottling
        default:
            reason = .unknown
        }
        events?.onSessionInterrupted(reason: reason) { _ in }
    }

    // MARK: - Preview

    func startPreview(
        config: PreviewConfig,
        completion: @escaping (Result<PreviewSession, Error>) -> Void
    ) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard let device = self.device else {
                completion(.failure(
                    ShadeCameraFailure(.configurationFailed, "initialize has not run")
                ))
                return
            }
            self.previewConfig = config
            self.metricsComputer.reset()
            if self.previewTexture == nil {
                self.previewTexture = PreviewTexture(registry: self.textureRegistry)
            }
            if !self.session.isRunning {
                self.session.startRunning()
            }
            // The active format's video dimensions, not the photo dimensions:
            // the texture carries what the video output produces, and that is
            // what every NormalizedRect in the contract is normalised against.
            let dimensions = CMVideoFormatDescriptionGetDimensions(
                device.activeFormat.formatDescription
            )
            // AVFoundation hands buffers over in the sensor's orientation
            // unless the connection is told otherwise, and this one is not.
            // Landscape-right is that orientation on every iPhone rear
            // camera, so an upright device needs a quarter turn.
            let rotation: Int64 = 90
            completion(.success(PreviewSession(
                textureId: self.previewTexture?.textureId ?? 0,
                previewWidth: Int64(dimensions.width),
                previewHeight: Int64(dimensions.height),
                displayRotationDegrees: rotation
            )))
        }
    }

    func updatePreviewRois(
        config: PreviewConfig,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        sessionQueue.async { [weak self] in
            self?.previewConfig = config
            completion(.success(()))
        }
    }

    func stopPreview(completion: @escaping (Result<Void, Error>) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
            self.previewConfig = nil
            self.latestPreviewBuffer = nil
            self.metricsComputer.reset()
            completion(.success(()))
        }
    }

    // MARK: - Focus

    /// Runs autofocus at a point and then locks the lens there.
    ///
    /// Locking matters more than focusing: autofocus hunting between the burst
    /// frames changes the magnification slightly, which moves the region
    /// outlines relative to the tooth.
    func focusAndLockAt(
        x: Double,
        y: Double,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.device else {
                completion(.failure(
                    ShadeCameraFailure(.deviceUnavailable, "no camera selected")
                ))
                return
            }
            guard device.isFocusPointOfInterestSupported,
                  device.isFocusModeSupported(.autoFocus)
            else {
                completion(.failure(ShadeCameraFailure(
                    .focusLockFailed,
                    "this camera cannot focus at a point"
                )))
                return
            }
            do {
                try device.lockForConfiguration()
                device.focusPointOfInterest = CGPoint(x: x, y: y)
                device.focusMode = .autoFocus
                if device.isSmoothAutoFocusSupported {
                    device.isSmoothAutoFocusEnabled = false
                }
                device.unlockForConfiguration()
            } catch {
                completion(.failure(ShadeCameraFailure(
                    .focusLockFailed,
                    "could not configure focus: \(error.localizedDescription)"
                )))
                return
            }

            self.focusObservation = device.observe(
                \.isAdjustingFocus,
                options: [.new]
            ) { [weak self] observed, change in
                guard change.newValue == false else { return }
                self?.focusObservation = nil
                self?.sessionQueue.async {
                    do {
                        try observed.lockForConfiguration()
                        if observed.isFocusModeSupported(.locked) {
                            observed.focusMode = .locked
                        }
                        observed.unlockForConfiguration()
                        completion(.success(()))
                    } catch {
                        completion(.failure(ShadeCameraFailure(
                            .focusLockFailed,
                            "could not lock focus: \(error.localizedDescription)"
                        )))
                    }
                }
            }
        }
    }

    // MARK: - Locking exposure and white balance

    /// Pins ISO at the sensor minimum, solves the shutter against the grey card
    /// and locks white balance at fixed gains.
    ///
    /// The white balance value itself does not matter; only that it stops
    /// moving. The real correction comes from the card.
    func lockCaptureParameters(
        settings: CaptureSettings,
        completion: @escaping (Result<ExposureState, Error>) -> Void
    ) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.device else {
                completion(.failure(
                    ShadeCameraFailure(.deviceUnavailable, "no camera selected")
                ))
                return
            }
            guard let config = self.previewConfig else {
                completion(.failure(ShadeCameraFailure(
                    .previewNotRunning,
                    "the shutter can only be solved against a running preview"
                )))
                return
            }
            guard device.isExposureModeSupported(.custom) else {
                completion(.failure(ShadeCameraFailure(
                    .exposureLockFailed,
                    "this camera has no manual exposure"
                )))
                return
            }
            self.events?.onCaptureProgress(
                progress: CaptureProgress(
                    captureId: "",
                    stage: .lockingParameters,
                    capturedFrames: 0,
                    requestedFrames: settings.burstFrameCount
                )
            ) { _ in }

            let format = device.activeFormat
            let iso = settings.isoOverride.map { Float($0) } ?? format.minISO
            let limits = ExposureSolver.Limits(
                minDuration: CMTimeGetSeconds(format.minExposureDuration),
                maxDuration: min(CMTimeGetSeconds(format.maxExposureDuration), 1.0 / 30)
            )
            var duration = settings.exposureSecondsOverride
                ?? max(limits.minDuration, min(1.0 / 120, limits.maxDuration))

            do {
                for iteration in 0..<ExposureSolver.maxIterations {
                    try self.applyExposure(
                        device: device,
                        duration: duration,
                        iso: iso
                    )
                    guard let measured = self.measureGrayCard(rect: config.grayCardRect)
                    else {
                        throw ShadeCameraFailure(
                            .previewNotRunning,
                            "no preview frame arrived while solving exposure",
                            recoverable: true
                        )
                    }
                    let outcome = ExposureSolver.evaluate(
                        iteration: iteration,
                        current: duration,
                        measuredCardLuma: measured.luma,
                        toothClippedFraction: measured.toothClipped,
                        targetLuma: settings.grayCardTargetLuma,
                        acceptableLumaRange: 0.20...0.70,
                        maxToothClippedFraction: settings.maxClippedFraction,
                        limits: limits
                    )
                    switch outcome {
                    case let .solved(solved):
                        duration = solved
                    case let .retry(next):
                        duration = next
                        continue
                    case let .outOfRange(last):
                        duration = last
                    }
                    break
                }
                try self.lockWhiteBalance(device: device)
                self.isLocked = true
                completion(.success(self.exposureState(of: device)))
            } catch let failure as ShadeCameraFailure {
                completion(.failure(failure))
            } catch {
                completion(.failure(ShadeCameraFailure(
                    .exposureLockFailed,
                    error.localizedDescription
                )))
            }
        }
    }

    private func applyExposure(
        device: AVCaptureDevice,
        duration: Double,
        iso: Float
    ) throws {
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        let clampedIso = max(device.activeFormat.minISO, min(iso, device.activeFormat.maxISO))
        device.setExposureModeCustom(
            duration: CMTime(seconds: duration, preferredTimescale: 1_000_000),
            iso: clampedIso,
            completionHandler: nil
        )
        // Let the new exposure reach a preview frame before it is measured.
        Thread.sleep(forTimeInterval: 0.12)
    }

    private func lockWhiteBalance(device: AVCaptureDevice) throws {
        guard device.isLockingWhiteBalanceWithCustomDeviceGainsSupported else {
            throw ShadeCameraFailure(
                .whiteBalanceLockFailed,
                "this camera cannot lock white balance at fixed gains"
            )
        }
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        var gains = device.deviceWhiteBalanceGains
        let maximum = device.maxWhiteBalanceGain
        gains.redGain = max(1, min(gains.redGain, maximum))
        gains.greenGain = max(1, min(gains.greenGain, maximum))
        gains.blueGain = max(1, min(gains.blueGain, maximum))
        device.setWhiteBalanceModeLocked(with: gains, completionHandler: nil)
    }

    func unlockCaptureParameters(completion: @escaping (Result<Void, Error>) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.device else {
                completion(.success(()))
                return
            }
            do {
                try device.lockForConfiguration()
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
                if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                    device.whiteBalanceMode = .continuousAutoWhiteBalance
                }
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }
                device.unlockForConfiguration()
            } catch {
                // Returning to automatic is a courtesy, not a requirement: the
                // session is about to be torn down anyway.
            }
            self.isLocked = false
            completion(.success(()))
        }
    }

    private func exposureState(of device: AVCaptureDevice) -> ExposureState {
        let gains = device.deviceWhiteBalanceGains
        return ExposureState(
            iso: Int64(device.iso),
            exposureSeconds: CMTimeGetSeconds(device.exposureDuration),
            focusLocked: device.focusMode == .locked,
            exposureLocked: device.exposureMode == .custom,
            whiteBalanceLocked: device.whiteBalanceMode == .locked,
            whiteBalanceGains: PreviewMetricsComputer.typedData([
                Double(gains.redGain),
                Double(gains.greenGain),
                Double(gains.blueGain),
            ]),
            focusDistanceDiopters: Double(device.lensPosition),
            colorTemperatureKelvin: Double(
                device.temperatureAndTintValues(for: gains).temperature
            )
        )
    }

    private func measureGrayCard(
        rect: NormalizedRect
    ) -> (luma: Double, toothClipped: Double)? {
        videoQueue.sync {
            guard let buffer = latestPreviewBuffer else { return nil }
            return metricsComputer.grayCardLuma(from: buffer, rect: rect)
        }
    }

    // MARK: - Capture

    func capture(
        request: CaptureRequest,
        completion: @escaping (Result<CaptureResult, Error>) -> Void
    ) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.device else {
                completion(.failure(
                    ShadeCameraFailure(.deviceUnavailable, "no camera selected")
                ))
                return
            }
            guard self.isLocked else {
                completion(.failure(ShadeCameraFailure(
                    .exposureLockFailed,
                    "capture parameters must be locked before a burst",
                    captureId: request.captureId
                )))
                return
            }
            guard self.burst == nil else {
                completion(.failure(ShadeCameraFailure(
                    .captureFailed,
                    "a burst is already in flight",
                    recoverable: true,
                    captureId: request.captureId
                )))
                return
            }
            let collector = BurstCollector(
                request: request,
                expected: Int(request.settings.burstFrameCount)
            ) { [weak self] photos, failure in
                guard let self else { return }
                self.burst = nil
                if let failure {
                    completion(.failure(failure))
                    return
                }
                do {
                    let result = try self.reduce(
                        photos: photos,
                        request: request,
                        device: device
                    )
                    completion(.success(result))
                } catch {
                    completion(.failure(error))
                }
            }
            self.burst = collector
            self.events?.onCaptureProgress(
                progress: CaptureProgress(
                    captureId: request.captureId,
                    stage: .capturingBurst,
                    capturedFrames: 0,
                    requestedFrames: request.settings.burstFrameCount
                )
            ) { _ in }
            for _ in 0..<collector.expected {
                self.photoOutput.capturePhoto(
                    with: self.makePhotoSettings(preferRaw: request.settings.preferBayerRaw),
                    delegate: self
                )
            }
        }
    }

    private func makePhotoSettings(preferRaw: Bool) -> AVCapturePhotoSettings {
        let settings: AVCapturePhotoSettings
        if preferRaw, let bayerFormat {
            settings = AVCapturePhotoSettings(
                rawPixelFormatType: bayerFormat,
                rawFileType: .dng,
                processedFormat: nil,
                processedFileType: nil
            )
        } else {
            settings = AVCapturePhotoSettings(
                format: [AVVideoCodecKey: AVVideoCodecType.hevc]
            )
        }
        settings.flashMode = .off
        settings.photoQualityPrioritization = .speed
        return settings
    }

    /// Selects frames, reduces every region and retains the survivors.
    private func reduce(
        photos: [AVCapturePhoto],
        request: CaptureRequest,
        device: AVCaptureDevice
    ) throws -> CaptureResult {
        guard !photos.isEmpty else {
            throw ShadeCameraFailure(
                .captureFailed,
                "the burst produced no photos",
                captureId: request.captureId
            )
        }
        events?.onCaptureProgress(
            progress: CaptureProgress(
                captureId: request.captureId,
                stage: .selectingFrames,
                capturedFrames: Int64(photos.count),
                requestedFrames: request.settings.burstFrameCount
            )
        ) { _ in }

        let metadata = RawPhotoMetadata.read(from: photos[0])
        var buffers: [CVPixelBuffer] = []
        for photo in photos {
            guard let buffer = photo.pixelBuffer else {
                throw ShadeCameraFailure(
                    .rawUnavailable,
                    "a burst frame carried no pixel buffer",
                    captureId: request.captureId
                )
            }
            buffers.append(buffer)
        }
        guard
            let pattern = BayerPattern(
                pixelFormat: CVPixelBufferGetPixelFormatType(buffers[0])
            )
        else {
            throw ShadeCameraFailure(
                .rawUnavailable,
                "the capture is not in a recognised Bayer layout",
                captureId: request.captureId
            )
        }

        // Frame selection. Sharpness is measured on the green cells of the
        // tooth region, which is the only place focus matters.
        let toothRect = request.rois.first { $0.kind == .toothBand }?.rect
            ?? NormalizedRect(left: 0.3, top: 0.3, width: 0.4, height: 0.4)
        var qualities: [FrameQuality] = []
        var sharpnessValues: [Double] = []
        for (index, buffer) in buffers.enumerated() {
            let sharpness = try withLockedBayerFrame(buffer) { frame -> Double in
                let roi = try SuperpixelRectangle.from(
                    NormalisedRectangle(toothRect),
                    frameWidth: frame.width,
                    frameHeight: frame.height
                )
                return BayerSharpness.greenLaplacianVariance(
                    frame: frame,
                    pattern: pattern,
                    levels: metadata.levels,
                    roi: roi
                )
            }
            sharpnessValues.append(sharpness)
            qualities.append(
                FrameQuality(
                    frameIndex: Int64(index),
                    sharpness: sharpness,
                    motionScore: 0,
                    clippedFraction: 0,
                    accepted: false,
                    rejectReason: nil
                )
            )
        }
        let bestSharpness = sharpnessValues.max() ?? 0
        let relativeFloor = bestSharpness * 0.60
        var accepted: [Int] = []
        for index in buffers.indices {
            let sharpness = sharpnessValues[index]
            let passes = sharpness >= max(request.settings.minSharpness, relativeFloor)
            qualities[index] = FrameQuality(
                frameIndex: Int64(index),
                sharpness: sharpness,
                motionScore: 0,
                clippedFraction: 0,
                accepted: passes,
                rejectReason: passes ? nil : .lowSharpness
            )
            if passes { accepted.append(index) }
        }
        guard !accepted.isEmpty else {
            throw ShadeCameraFailure(
                .captureFailed,
                "every frame of the burst was rejected as unsharp",
                recoverable: true,
                captureId: request.captureId
            )
        }

        events?.onCaptureProgress(
            progress: CaptureProgress(
                captureId: request.captureId,
                stage: .reducingRois,
                capturedFrames: Int64(photos.count),
                requestedFrames: request.settings.burstFrameCount
            )
        ) { _ in }

        let acceptedBuffers = accepted.map { buffers[$0] }
        let samples = try reduceRegions(
            buffers: acceptedBuffers,
            rois: request.rois,
            pattern: pattern,
            levels: metadata.levels,
            sampling: request.settings.sampling
        )

        store.store(
            RetainedCapture(
                captureId: request.captureId,
                frames: accepted.map {
                    RetainedFrame(pixelBuffer: buffers[$0], quality: qualities[$0])
                },
                pattern: pattern,
                levels: metadata.levels
            )
        )

        let hasRaw = bayerFormat != nil && request.settings.preferBayerRaw
        return CaptureResult(
            captureId: request.captureId,
            tier: capabilities?.tier ?? .limited,
            format: hasRaw ? .bayerRaw : .processedLinearisable,
            signalEncoding: hasRaw ? .linear : .displayReferredSrgb,
            rois: samples,
            frames: qualities,
            acceptedFrameCount: Int64(accepted.count),
            exposure: exposureState(of: device),
            capturedAtUtcMillis: Int64(Date().timeIntervalSince1970 * 1000),
            deviceModel: DeviceIdentity.hardwareModel,
            lensId: device.uniqueID,
            sensorWhiteLevel: metadata.levels.white,
            sensorBlackLevel: metadata.levels.blackLevel(atCell: 0),
            previewImagePath: nil,
            rawFilePath: nil,
            dngMetadata: metadata.bridged
        )
    }

    private func reduceRegions(
        buffers: [CVPixelBuffer],
        rois: [RoiRequest],
        pattern: BayerPattern,
        levels: SensorLevels,
        sampling: SamplingSettings
    ) throws -> [RoiSample] {
        var locked: [BayerFrame] = []
        var unlockers: [() -> Void] = []
        defer { unlockers.forEach { $0() } }
        for buffer in buffers {
            guard
                CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess,
                let base = CVPixelBufferGetBaseAddress(buffer)
            else {
                throw ShadeCameraFailure(.captureFailed, "could not lock a burst frame")
            }
            unlockers.append { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
            locked.append(
                BayerFrame(
                    samples: base.assumingMemoryBound(to: UInt16.self),
                    rowStride: CVPixelBufferGetBytesPerRow(buffer) / 2,
                    width: CVPixelBufferGetWidth(buffer),
                    height: CVPixelBufferGetHeight(buffer)
                )
            )
        }
        return try rois.map { roi in
            try reduceOne(
                roi: roi,
                frames: locked,
                pattern: pattern,
                levels: levels,
                sampling: sampling
            )
        }
    }

    private func reduceOne(
        roi: RoiRequest,
        frames: [BayerFrame],
        pattern: BayerPattern,
        levels: SensorLevels,
        sampling: SamplingSettings
    ) throws -> RoiSample {
        let rectangle = try SuperpixelRectangle.from(
            NormalisedRectangle(roi.rect),
            frameWidth: frames[0].width,
            frameHeight: frames[0].height
        )
        let budget = roi.kind == .colorCheckerPatch
            ? min(Int(sampling.maxSamplesPerRoi), 512)
            : Int(sampling.maxSamplesPerRoi)
        let reduction = try BayerReducer.reduce(
            frames: frames,
            pattern: pattern,
            levels: levels,
            roi: rectangle,
            maxSamples: budget,
            clippingThreshold: sampling.clippingThreshold
        )
        return RoiSample(
            roiId: roi.roiId,
            kind: roi.kind,
            rect: roi.rect,
            rgbSamples: PreviewMetricsComputer.typedData(reduction.samples),
            sampleCount: Int64(reduction.sampleCount),
            totalSuperpixels: Int64(reduction.totalSuperpixels),
            clippedSuperpixels: Int64(reduction.clippedSuperpixels),
            decimationStride: Int64(reduction.decimationStride),
            channelMean: PreviewMetricsComputer.typedData(reduction.channelMean),
            channelStdDev: PreviewMetricsComputer.typedData(reduction.channelStdDev),
            widthInSuperpixels: Int64(reduction.widthInSuperpixels),
            heightInSuperpixels: Int64(reduction.heightInSuperpixels),
            region: roi.region,
            index: roi.index
        )
    }

    func resampleRoi(
        captureId: String,
        roi: RoiRequest,
        sampling: SamplingSettings,
        completion: @escaping (Result<RoiSample, Error>) -> Void
    ) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard let retained = self.store.capture(withId: captureId) else {
                completion(.failure(ShadeCameraFailure(
                    .unknownCaptureId,
                    "no retained capture with this identifier",
                    captureId: captureId
                )))
                return
            }
            do {
                let sample = try self.reduceRegions(
                    buffers: retained.frames.map(\.pixelBuffer),
                    rois: [roi],
                    pattern: retained.pattern,
                    levels: retained.levels,
                    sampling: sampling
                )
                guard let first = sample.first else {
                    throw ShadeCameraFailure(
                        .captureFailed,
                        "the region produced no sample",
                        captureId: captureId
                    )
                }
                completion(.success(first))
            } catch {
                completion(.failure(error))
            }
        }
    }

    func releaseCapture(id: String, completion: @escaping (Result<Void, Error>) -> Void) {
        sessionQueue.async { [weak self] in
            self?.store.release(id: id)
            completion(.success(()))
        }
    }

    func dispose(completion: @escaping (Result<Void, Error>) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.focusObservation = nil
            self.interruptionObservers.forEach(NotificationCenter.default.removeObserver)
            self.interruptionObservers.removeAll()
            if self.session.isRunning { self.session.stopRunning() }
            self.videoOutput.setSampleBufferDelegate(nil, queue: nil)
            self.previewTexture?.unregister()
            self.previewTexture = nil
            self.store.releaseAll()
            self.latestPreviewBuffer = nil
            self.isLocked = false
            completion(.success(()))
        }
    }
}

// MARK: - Preview frames

extension CaptureSessionController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        latestPreviewBuffer = buffer
        previewTexture?.present(buffer)

        guard let config = previewConfig, let device else { return }
        let elapsed = CMTimeGetSeconds(
            CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        )
        let timestamp = Int64(elapsed * 1000)
        guard timestamp - lastMetricsTimestamp >= config.metricsIntervalMillis else {
            return
        }
        lastMetricsTimestamp = timestamp
        guard
            let metrics = metricsComputer.metrics(
                from: buffer,
                config: config,
                exposure: exposureState(of: device),
                format: bayerFormat == nil ? .processedLinearisable : .bayerRaw,
                timestampMillis: timestamp
            )
        else { return }
        events?.onPreviewMetrics(metrics: metrics) { _ in }
    }
}

// MARK: - Photo delegate

extension CaptureSessionController: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard let collector = burst else { return }
        if let error {
            collector.fail(
                ShadeCameraFailure(
                    .captureFailed,
                    "a burst frame failed: \(error.localizedDescription)",
                    recoverable: true,
                    captureId: collector.request.captureId
                )
            )
            return
        }
        collector.add(photo)
        events?.onCaptureProgress(
            progress: CaptureProgress(
                captureId: collector.request.captureId,
                stage: .capturingBurst,
                capturedFrames: Int64(collector.count),
                requestedFrames: collector.request.settings.burstFrameCount
            )
        ) { _ in }
    }
}

/// Gathers the photos of one burst and reports once they have all arrived.
private final class BurstCollector {
    let request: CaptureRequest
    let expected: Int

    private var photos: [AVCapturePhoto] = []
    private var finished = false
    private let completion: ([AVCapturePhoto], ShadeCameraFailure?) -> Void

    init(
        request: CaptureRequest,
        expected: Int,
        completion: @escaping ([AVCapturePhoto], ShadeCameraFailure?) -> Void
    ) {
        self.request = request
        self.expected = max(1, expected)
        self.completion = completion
    }

    var count: Int { photos.count }

    func add(_ photo: AVCapturePhoto) {
        guard !finished else { return }
        photos.append(photo)
        if photos.count >= expected {
            finished = true
            completion(photos, nil)
        }
    }

    func fail(_ failure: ShadeCameraFailure) {
        guard !finished else { return }
        finished = true
        completion([], failure)
    }
}
