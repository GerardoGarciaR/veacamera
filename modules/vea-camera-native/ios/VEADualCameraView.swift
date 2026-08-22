import AVFoundation
import CoreImage
import CoreMedia
import ExpoModulesCore
import Photos
import UIKit

final class VEADualCameraView: ExpoView, AVCaptureDataOutputSynchronizerDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
  let onReady = EventDispatcher()
  let onError = EventDispatcher()
  let onRecordingStarted = EventDispatcher()
  let onRecordingFinished = EventDispatcher()
  let onRecordingError = EventDispatcher()

  // MARK: - React props

  var pipDiameter: CGFloat = 132 {
    didSet { setNeedsLayout() }
  }

  var pipMargin: CGFloat = 18 {
    didSet { setNeedsLayout() }
  }

  var logoVisible: Bool = true {
    didSet {
      logoLayer.isHidden = !logoVisible
      setNeedsLayout()
    }
  }

  var logoWidthRatio: CGFloat = 0.24 {
    didSet { setNeedsLayout() }
  }

  var tiktokSafeRightRatio: CGFloat = 0.16 {
    didSet { setNeedsLayout() }
  }

  var tiktokSafeBottomRatio: CGFloat = 0.18 {
    didSet { setNeedsLayout() }
  }

  var showTikTokSafeZone: Bool = false {
    didSet { safeZoneOverlay.isHidden = !showTikTokSafeZone }
  }

  var frontCameraVisible: Bool = true {
    didSet {
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.frontPreviewLayer?.isHidden = !self.frontCameraVisible
        self.setNeedsLayout()
      }
    }
  }

  var sermonTitle: String = "" {
    didSet {
      DispatchQueue.main.async { [weak self] in
        self?.setNeedsLayout()
      }
    }
  }

  var coverImageUri: String = "" {
    didSet {
      DispatchQueue.main.async { [weak self] in
        self?.loadCoverImageFromCurrentURI()
      }
    }
  }

  var recording: Bool = false {
    didSet {
      guard recording != oldValue else { return }
      if recording {
        requestStartRecording()
      } else {
        requestStopRecording()
      }
    }
  }

  // MARK: - Capture session

  private let session = AVCaptureMultiCamSession()
  private let sessionQueue = DispatchQueue(label: "org.vea.camera.multicam.session", qos: .userInitiated)
  private let recordingQueue = DispatchQueue(label: "org.vea.camera.multicam.recording", qos: .userInitiated)

  private var backPreviewLayer: AVCaptureVideoPreviewLayer?
  private var frontPreviewLayer: AVCaptureVideoPreviewLayer?

  private let backVideoOutput = AVCaptureVideoDataOutput()
  private let frontVideoOutput = AVCaptureVideoDataOutput()
  private var audioOutput: AVCaptureAudioDataOutput?
  private var outputSynchronizer: AVCaptureDataOutputSynchronizer?

  private var configured = false
  private var configuring = false

  // MARK: - Branding / preview layers

  private var logoImage: UIImage?
  private var coverImage: UIImage?

  private let logoLayer = CALayer()
  private let topWebsiteLayer = CATextLayer()
  private let coverLayer = CALayer()
  private let watchingLayer = CATextLayer()
  private let titleLayer = CATextLayer()
  private let churchLayer = CATextLayer()
  private let pastorLayer = CATextLayer()
  private let bottomWebsiteLayer = CATextLayer()

  private let safeZoneOverlay: UIView = {
    let view = UIView()
    view.backgroundColor = .clear
    view.isUserInteractionEnabled = false
    view.isHidden = true
    view.layer.borderWidth = 1
    view.layer.borderColor = UIColor.systemYellow.withAlphaComponent(0.72).cgColor
    view.layer.cornerRadius = 12
    return view
  }()

  // MARK: - Recording state

  private let ciContext = CIContext(options: [
    .cacheIntermediates: true
  ])
  private let outputSize = CGSize(width: 1080, height: 1920)
  private let outputColorSpace = CGColorSpaceCreateDeviceRGB()

  private var assetWriter: AVAssetWriter?
  private var videoWriterInput: AVAssetWriterInput?
  private var audioWriterInput: AVAssetWriterInput?
  private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
  private var writerSessionStartTime: CMTime?
  private var currentRecordingURL: URL?
  private var isRecordingNative = false
  private var isStoppingRecording = false

  private var recordingOverlayCIImage: CIImage?
  private var recordingFrontCameraVisible = true
  private var recordingPipDiameterRatio: CGFloat = 0.31
  private var recordingPipMarginRatio: CGFloat = 0.04
  private var recordingPipTopRatio: CGFloat = 0.065

  // MARK: - Init

  required init(appContext: AppContext? = nil) {
    super.init(appContext: appContext)

    backgroundColor = .black
    clipsToBounds = true

    logoImage = Self.loadLogoImage()
    logoLayer.contents = logoImage?.cgImage
    logoLayer.contentsScale = logoImage?.scale ?? UIScreen.main.scale
    logoLayer.contentsGravity = .resizeAspect
    logoLayer.masksToBounds = false
    logoLayer.shadowColor = UIColor.black.cgColor
    logoLayer.shadowOpacity = 0.45
    logoLayer.shadowRadius = 4
    logoLayer.shadowOffset = CGSize(width: 0, height: 2)

    coverLayer.contentsGravity = .resizeAspectFill
    coverLayer.masksToBounds = true
    coverLayer.borderWidth = 1
    coverLayer.borderColor = UIColor.white.withAlphaComponent(0.65).cgColor

    [topWebsiteLayer, watchingLayer, titleLayer, churchLayer, pastorLayer, bottomWebsiteLayer].forEach {
      $0.contentsScale = UIScreen.main.scale
      $0.foregroundColor = UIColor.white.cgColor
      $0.shadowColor = UIColor.black.cgColor
      $0.shadowOpacity = 0.65
      $0.shadowRadius = 2
      $0.shadowOffset = CGSize(width: 0, height: 1)
      $0.truncationMode = .end
      $0.isWrapped = false
      $0.alignmentMode = .left
    }

    addSubview(safeZoneOverlay)

    [
      logoLayer,
      topWebsiteLayer,
      coverLayer,
      watchingLayer,
      titleLayer,
      churchLayer,
      pastorLayer,
      bottomWebsiteLayer
    ].forEach {
      $0.zPosition = 10_000
      layer.addSublayer($0)
    }
  }

  // MARK: - View lifecycle

  override func didMoveToWindow() {
    super.didMoveToWindow()

    if window != nil {
      startIfPossible()
    } else {
      stopSession()
    }
  }

  override func layoutSubviews() {
    super.layoutSubviews()

    CATransaction.begin()
    CATransaction.setDisableActions(true)

    backPreviewLayer?.frame = bounds

    let width = bounds.width
    let height = bounds.height
    guard width > 0, height > 0 else {
      CATransaction.commit()
      return
    }

    // Front camera: top-right, deliberately clear of the VEA brand at top-left.
    let diameter = min(pipDiameter, max(72, width * 0.42))
    let pipX = max(pipMargin, width - diameter - pipMargin)
    let pipY = max(safeAreaInsets.top + 12, height * 0.055)

    if let frontPreviewLayer {
      frontPreviewLayer.frame = CGRect(x: pipX, y: pipY, width: diameter, height: diameter)
      frontPreviewLayer.cornerRadius = diameter / 2
      frontPreviewLayer.masksToBounds = true
      frontPreviewLayer.borderWidth = 2
      frontPreviewLayer.borderColor = UIColor.white.withAlphaComponent(0.92).cgColor
      frontPreviewLayer.isHidden = !frontCameraVisible
    }

    // Optional safe-zone helper.
    let safeLeft = max(18, width * 0.06)
    let safeRight = max(52, width * tiktokSafeRightRatio)
    let safeTopForSocial = max(safeAreaInsets.top + 8, height * 0.08)
    let safeBottom = max(safeAreaInsets.bottom + 24, height * tiktokSafeBottomRatio)
    safeZoneOverlay.frame = CGRect(
      x: safeLeft,
      y: safeTopForSocial,
      width: max(0, width - safeLeft - safeRight),
      height: max(0, height - safeTopForSocial - safeBottom)
    )

    layoutBrandingLayers(
      in: CGSize(width: width, height: height),
      safeTop: safeAreaInsets.top
    )

    safeZoneOverlay.layer.zPosition = 9_000
    bringSubviewToFront(safeZoneOverlay)

    CATransaction.commit()
  }

  deinit {
    outputSynchronizer?.setDelegate(nil, queue: nil)
    audioOutput?.setSampleBufferDelegate(nil, queue: nil)

    if session.isRunning {
      session.stopRunning()
    }
  }

  // MARK: - Preview branding layout

  private func layoutBrandingLayers(in size: CGSize, safeTop: CGFloat) {
    let w = size.width
    let h = size.height

    logoLayer.isHidden = !logoVisible

    // Reference layout: VEA logo in the upper-left with the website beneath it.
    let logoX = w * 0.022
    let logoY = max(safeTop + 2, h * 0.012)
    let logoW = min(max(w * logoWidthRatio, 82), w * 0.30)
    let logoH = h * 0.105
    logoLayer.frame = CGRect(x: logoX, y: logoY, width: logoW, height: logoH)

    let websiteFont = max(11, w * 0.026)
    topWebsiteLayer.frame = CGRect(x: w * 0.027, y: h * 0.105, width: w * 0.40, height: websiteFont * 1.35)
    setText(
      "www.iglesiavea.com",
      on: topWebsiteLayer,
      font: UIFont(name: "AvenirNext-Regular", size: websiteFont) ?? UIFont.systemFont(ofSize: websiteFont)
    )

    // Lower third copied proportionally from the supplied reference.
    let lowerY = h * 0.742
    let coverSize = w * 0.115
    let coverX = w * 0.140
    let coverY = lowerY + h * 0.010
    coverLayer.frame = CGRect(x: coverX, y: coverY, width: coverSize, height: coverSize)
    coverLayer.cornerRadius = max(2, coverSize * 0.035)
    coverLayer.isHidden = coverImage == nil

    let textX = w * 0.265
    let textWidth = max(0, w - textX - w * 0.035)

    let watchingFontSize = max(11, w * 0.030)
    watchingLayer.frame = CGRect(x: textX, y: lowerY, width: textWidth, height: watchingFontSize * 1.40)
    setText(
      "Estas viendo",
      on: watchingLayer,
      font: UIFont(name: "AvenirNextCondensed-Regular", size: watchingFontSize)
        ?? UIFont.systemFont(ofSize: watchingFontSize, weight: .light)
    )

    let titleFontSize = max(23, w * 0.058)
    titleLayer.frame = CGRect(
      x: textX,
      y: lowerY + watchingFontSize * 1.10,
      width: textWidth,
      height: titleFontSize * 1.18
    )
    setText(
      sermonTitle.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
      on: titleLayer,
      font: UIFont(name: "AvenirNextCondensed-DemiBold", size: titleFontSize)
        ?? UIFont.systemFont(ofSize: titleFontSize, weight: .semibold)
    )

    let metadataFontSize = max(11.5, w * 0.030)
    let metadataStartY = lowerY + watchingFontSize * 1.10 + titleFontSize * 1.02
    let metadataLine = metadataFontSize * 1.20

    churchLayer.frame = CGRect(x: textX, y: metadataStartY, width: textWidth, height: metadataLine)
    pastorLayer.frame = CGRect(x: textX, y: metadataStartY + metadataLine, width: textWidth, height: metadataLine)
    bottomWebsiteLayer.frame = CGRect(x: textX, y: metadataStartY + metadataLine * 2, width: textWidth, height: metadataLine)

    let metadataFont = UIFont(name: "AvenirNextCondensed-Regular", size: metadataFontSize)
      ?? UIFont.systemFont(ofSize: metadataFontSize, weight: .light)

    setText("VEA Comunidad Cristiana", on: churchLayer, font: metadataFont)
    setText("P.S. Mauricio Sánchez Scott", on: pastorLayer, font: metadataFont)
    setText("www.iglesiavea.com", on: bottomWebsiteLayer, font: metadataFont)

    [logoLayer, topWebsiteLayer, coverLayer, watchingLayer, titleLayer, churchLayer, pastorLayer, bottomWebsiteLayer].forEach {
      $0.zPosition = 10_000
    }
  }

  private func setText(_ text: String, on layer: CATextLayer, font: UIFont) {
    layer.string = NSAttributedString(
      string: text,
      attributes: [
        .font: font,
        .foregroundColor: UIColor.white
      ]
    )
  }

  private func loadCoverImageFromCurrentURI() {
    let uri = coverImageUri.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !uri.isEmpty else {
      coverImage = nil
      coverLayer.contents = nil
      coverLayer.isHidden = true
      setNeedsLayout()
      return
    }

    let path: String
    if let url = URL(string: uri), url.isFileURL {
      path = url.path
    } else {
      path = uri.replacingOccurrences(of: "file://", with: "")
    }

    guard let image = UIImage(contentsOfFile: path) else {
      coverImage = nil
      coverLayer.contents = nil
      coverLayer.isHidden = true
      emitError("No pude abrir la portada seleccionada. Intenta elegirla nuevamente desde Fotos.")
      return
    }

    coverImage = image
    coverLayer.contents = image.cgImage
    coverLayer.contentsScale = image.scale
    coverLayer.isHidden = false
    setNeedsLayout()
  }

  // MARK: - Logo resource

  private static func loadLogoImage() -> UIImage? {
    let imageName = "vea-logo"
    let imageExtension = "png"
    let resourceBundleName = "VEACameraNativeResources"

    var candidateBundles: [Bundle] = [
      Bundle.main,
      Bundle(for: VEADualCameraView.self)
    ]

    candidateBundles.append(contentsOf: Bundle.allFrameworks)
    candidateBundles.append(contentsOf: Bundle.allBundles)

    var seenPaths = Set<String>()
    candidateBundles = candidateBundles.filter { bundle in
      let path = bundle.bundlePath
      guard !seenPaths.contains(path) else { return false }
      seenPaths.insert(path)
      return true
    }

    for containerBundle in candidateBundles {
      if let imagePath = containerBundle.path(forResource: imageName, ofType: imageExtension),
         let image = UIImage(contentsOfFile: imagePath) {
        print("[VEACameraNative] ✅ Logo VEA cargado desde: \(imagePath)")
        return image
      }

      if let resourceBundleURL = containerBundle.url(forResource: resourceBundleName, withExtension: "bundle"),
         let resourceBundle = Bundle(url: resourceBundleURL) {
        if let imagePath = resourceBundle.path(forResource: imageName, ofType: imageExtension),
           let image = UIImage(contentsOfFile: imagePath) {
          print("[VEACameraNative] ✅ Logo VEA cargado desde: \(imagePath)")
          return image
        }

        if let image = UIImage(named: imageName, in: resourceBundle, compatibleWith: nil) {
          print("[VEACameraNative] ✅ Logo VEA cargado desde resource bundle")
          return image
        }
      }
    }

    if let image = UIImage(named: imageName) {
      print("[VEACameraNative] ✅ Logo VEA cargado con UIImage(named:)")
      return image
    }

    print("[VEACameraNative] ❌ No se encontró vea-logo.png en ningún bundle")
    return nil
  }

  // MARK: - Session setup

  private func startIfPossible() {
    guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
      emitError("La cámara todavía no tiene permiso. Autorízala y vuelve a abrir la vista.")
      return
    }

    guard AVCaptureMultiCamSession.isMultiCamSupported else {
      emitError("Este iPhone reporta que AVCaptureMultiCamSession no está soportado.")
      return
    }

    sessionQueue.async { [weak self] in
      guard let self else { return }

      if self.session.isRunning {
        return
      }

      if !self.configured {
        guard !self.configuring else { return }
        self.configuring = true
        let success = self.configureSession()
        self.configuring = false
        guard success else { return }
      }

      self.session.startRunning()

      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.onReady([
          "multiCamSupported": true,
          "hardwareCost": Double(self.session.hardwareCost),
          "systemPressureCost": Double(self.session.systemPressureCost)
        ])
      }
    }
  }

  private func stopSession() {
    requestStopRecording()

    sessionQueue.async { [weak self] in
      guard let self, self.session.isRunning else { return }
      self.session.stopRunning()
    }
  }

  private func configureSession() -> Bool {
    session.beginConfiguration()
    defer { session.commitConfiguration() }

    do {
      guard
        let backDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
        let frontDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
      else {
        emitError("No pude localizar simultáneamente la cámara frontal y la trasera.")
        return false
      }

      let backInput = try AVCaptureDeviceInput(device: backDevice)
      let frontInput = try AVCaptureDeviceInput(device: frontDevice)

      guard session.canAddInput(backInput) else {
        emitError("El sistema no permitió agregar la cámara trasera a la sesión MultiCam.")
        return false
      }
      session.addInputWithNoConnections(backInput)

      guard session.canAddInput(frontInput) else {
        session.removeInput(backInput)
        emitError("El sistema no permitió agregar la cámara frontal a la sesión MultiCam.")
        return false
      }
      session.addInputWithNoConnections(frontInput)

      guard
        let backPort = backInput.ports(
          for: .video,
          sourceDeviceType: backDevice.deviceType,
          sourceDevicePosition: .back
        ).first,
        let frontPort = frontInput.ports(
          for: .video,
          sourceDeviceType: frontDevice.deviceType,
          sourceDevicePosition: .front
        ).first
      else {
        emitError("No pude obtener los puertos de video de ambas cámaras.")
        return false
      }

      // Preview layers.
      let backLayer = AVCaptureVideoPreviewLayer(sessionWithNoConnection: session)
      backLayer.videoGravity = .resizeAspectFill

      let frontLayer = AVCaptureVideoPreviewLayer(sessionWithNoConnection: session)
      frontLayer.videoGravity = .resizeAspectFill

      DispatchQueue.main.sync { [weak self] in
        guard let self else { return }

        self.backPreviewLayer?.removeFromSuperlayer()
        self.frontPreviewLayer?.removeFromSuperlayer()

        self.backPreviewLayer = backLayer
        self.frontPreviewLayer = frontLayer

        backLayer.zPosition = 0
        frontLayer.zPosition = 100

        self.layer.insertSublayer(backLayer, at: 0)
        self.layer.insertSublayer(frontLayer, above: backLayer)

        self.safeZoneOverlay.layer.zPosition = 9_000
        [self.logoLayer, self.topWebsiteLayer, self.coverLayer, self.watchingLayer, self.titleLayer, self.churchLayer, self.pastorLayer, self.bottomWebsiteLayer].forEach {
          $0.zPosition = 10_000
        }

        self.bringSubviewToFront(self.safeZoneOverlay)
        self.setNeedsLayout()
        self.layoutIfNeeded()
      }

      let backPreviewConnection = AVCaptureConnection(inputPort: backPort, videoPreviewLayer: backLayer)
      let frontPreviewConnection = AVCaptureConnection(inputPort: frontPort, videoPreviewLayer: frontLayer)

      guard session.canAddConnection(backPreviewConnection), session.canAddConnection(frontPreviewConnection) else {
        emitError("No pude conectar las cámaras a sus vistas de preview.")
        return false
      }

      session.addConnection(backPreviewConnection)
      session.addConnection(frontPreviewConnection)

      configurePortraitOrientation(for: backPreviewConnection)
      configurePortraitOrientation(for: frontPreviewConnection)
      configureFrontMirroring(for: frontPreviewConnection)

      // Raw video outputs used only for the composed MP4 recorder.
      let pixelFormatSettings = [
        kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
      ]
      backVideoOutput.videoSettings = pixelFormatSettings
      frontVideoOutput.videoSettings = pixelFormatSettings
      backVideoOutput.alwaysDiscardsLateVideoFrames = true
      frontVideoOutput.alwaysDiscardsLateVideoFrames = true

      guard session.canAddOutput(backVideoOutput), session.canAddOutput(frontVideoOutput) else {
        emitError("El sistema no permitió preparar las salidas de video para grabación.")
        return false
      }

      session.addOutputWithNoConnections(backVideoOutput)
      session.addOutputWithNoConnections(frontVideoOutput)

      let backDataConnection = AVCaptureConnection(inputPorts: [backPort], output: backVideoOutput)
      let frontDataConnection = AVCaptureConnection(inputPorts: [frontPort], output: frontVideoOutput)

      guard session.canAddConnection(backDataConnection), session.canAddConnection(frontDataConnection) else {
        emitError("No pude conectar ambas cámaras al compositor de grabación.")
        return false
      }

      session.addConnection(backDataConnection)
      session.addConnection(frontDataConnection)

      configurePortraitOrientation(for: backDataConnection)
      configurePortraitOrientation(for: frontDataConnection)
      configureFrontMirroring(for: frontDataConnection)

      let synchronizer = AVCaptureDataOutputSynchronizer(dataOutputs: [backVideoOutput, frontVideoOutput])
      synchronizer.setDelegate(self, queue: recordingQueue)
      outputSynchronizer = synchronizer

      // Microphone. App.jsx asks for permission before mounting this view.
      if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
         let audioDevice = AVCaptureDevice.default(for: .audio) {
        let audioInput = try AVCaptureDeviceInput(device: audioDevice)

        if session.canAddInput(audioInput) {
          session.addInputWithNoConnections(audioInput)

          let newAudioOutput = AVCaptureAudioDataOutput()
          if session.canAddOutput(newAudioOutput),
             let audioPort = audioInput.ports.first(where: { $0.mediaType == .audio }) {
            session.addOutputWithNoConnections(newAudioOutput)

            let audioConnection = AVCaptureConnection(inputPorts: [audioPort], output: newAudioOutput)
            if session.canAddConnection(audioConnection) {
              session.addConnection(audioConnection)
              newAudioOutput.setSampleBufferDelegate(self, queue: recordingQueue)
              audioOutput = newAudioOutput
            }
          }
        }
      }

      configured = true
      return true
    } catch {
      emitError("Error configurando MultiCam: \(error.localizedDescription)")
      return false
    }
  }

  private func configurePortraitOrientation(for connection: AVCaptureConnection) {
    if #available(iOS 17.0, *) {
      if connection.isVideoRotationAngleSupported(90) {
        connection.videoRotationAngle = 90
      }
    } else if connection.isVideoOrientationSupported {
      connection.videoOrientation = .portrait
    }
  }

  private func configureFrontMirroring(for connection: AVCaptureConnection) {
    connection.automaticallyAdjustsVideoMirroring = false
    if connection.isVideoMirroringSupported {
      connection.isVideoMirrored = true
    }
  }

  // MARK: - Recording control

  private func requestStartRecording() {
    sessionQueue.async { [weak self] in
      guard let self else { return }

      guard self.configured, self.session.isRunning else {
        self.emitRecordingError("La sesión MultiCam todavía no está lista para grabar.")
        return
      }

      guard self.audioOutput != nil else {
        self.emitRecordingError("El micrófono no está disponible. Autoriza el micrófono y vuelve a abrir la cámara.")
        return
      }

      self.recordingQueue.async { [weak self] in
        self?.startRecordingLocked()
      }
    }
  }

  private func requestStopRecording() {
    recordingQueue.async { [weak self] in
      self?.stopRecordingLocked()
    }
  }

  private func startRecordingLocked() {
    guard !isRecordingNative, !isStoppingRecording else { return }

    let snapshot = captureRecordingOverlaySnapshot()
    recordingOverlayCIImage = snapshot.overlay
    recordingFrontCameraVisible = snapshot.frontVisible
    recordingPipDiameterRatio = snapshot.pipDiameterRatio
    recordingPipMarginRatio = snapshot.pipMarginRatio
    recordingPipTopRatio = snapshot.pipTopRatio

    do {
      let url = temporaryRecordingURL()
      try? FileManager.default.removeItem(at: url)

      let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
      writer.shouldOptimizeForNetworkUse = true

      let videoSettings: [String: Any] = [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: Int(outputSize.width),
        AVVideoHeightKey: Int(outputSize.height),
        AVVideoCompressionPropertiesKey: [
          AVVideoAverageBitRateKey: 8_000_000,
          AVVideoExpectedSourceFrameRateKey: 30,
          AVVideoMaxKeyFrameIntervalKey: 30,
          AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
        ]
      ]

      let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
      videoInput.expectsMediaDataInRealTime = true

      let adaptor = AVAssetWriterInputPixelBufferAdaptor(
        assetWriterInput: videoInput,
        sourcePixelBufferAttributes: [
          kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
          kCVPixelBufferWidthKey as String: Int(outputSize.width),
          kCVPixelBufferHeightKey as String: Int(outputSize.height),
          kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]
        ]
      )

      let audioSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: 48_000,
        AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: 128_000
      ]
      let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
      audioInput.expectsMediaDataInRealTime = true

      guard writer.canAdd(videoInput), writer.canAdd(audioInput) else {
        emitRecordingError("No pude preparar el codificador MP4 del iPhone.")
        return
      }

      writer.add(videoInput)
      writer.add(audioInput)

      assetWriter = writer
      videoWriterInput = videoInput
      audioWriterInput = audioInput
      pixelBufferAdaptor = adaptor
      writerSessionStartTime = nil
      currentRecordingURL = url
      isRecordingNative = true
      isStoppingRecording = false

      DispatchQueue.main.async { [weak self] in
        self?.onRecordingStarted([
          "recording": true,
          "width": Int(self?.outputSize.width ?? 1080),
          "height": Int(self?.outputSize.height ?? 1920)
        ])
      }
    } catch {
      cleanupWriterState(removeTemporaryFile: true)
      emitRecordingError("No pude iniciar la grabación: \(error.localizedDescription)")
    }
  }

  private func stopRecordingLocked() {
    guard isRecordingNative, !isStoppingRecording else { return }
    isStoppingRecording = true
    isRecordingNative = false

    guard let writer = assetWriter,
          let videoInput = videoWriterInput,
          let audioInput = audioWriterInput,
          let url = currentRecordingURL else {
      cleanupWriterState(removeTemporaryFile: true)
      return
    }

    videoInput.markAsFinished()
    audioInput.markAsFinished()

    writer.finishWriting { [weak self] in
      guard let self else { return }

      if writer.status == .completed {
        self.saveRecordingToPhotos(url: url)
      } else {
        let message = writer.error?.localizedDescription ?? "Error desconocido cerrando el archivo MP4."
        self.recordingQueue.async {
          self.cleanupWriterState(removeTemporaryFile: false)
          self.emitRecordingError("La grabación no pudo finalizar: \(message)")
        }
      }
    }
  }

  private func temporaryRecordingURL() -> URL {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd_HHmmss"
    let fileName = "VEA_\(formatter.string(from: Date())).mp4"
    return FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
  }

  private func cleanupWriterState(removeTemporaryFile: Bool) {
    let url = currentRecordingURL

    assetWriter = nil
    videoWriterInput = nil
    audioWriterInput = nil
    pixelBufferAdaptor = nil
    writerSessionStartTime = nil
    currentRecordingURL = nil
    recordingOverlayCIImage = nil
    isRecordingNative = false
    isStoppingRecording = false

    if removeTemporaryFile, let url {
      try? FileManager.default.removeItem(at: url)
    }
  }

  // MARK: - Synchronized video frames

  func dataOutputSynchronizer(
    _ synchronizer: AVCaptureDataOutputSynchronizer,
    didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection
  ) {
    guard isRecordingNative,
          let writer = assetWriter,
          let videoInput = videoWriterInput,
          let adaptor = pixelBufferAdaptor else {
      return
    }

    guard let backData = synchronizedDataCollection.synchronizedData(for: backVideoOutput)
      as? AVCaptureSynchronizedSampleBufferData,
      !backData.sampleBufferWasDropped else {
      return
    }

    let backSampleBuffer = backData.sampleBuffer
    guard let backPixelBuffer = CMSampleBufferGetImageBuffer(backSampleBuffer) else { return }

    let presentationTime = CMSampleBufferGetPresentationTimeStamp(backSampleBuffer)

    if writerSessionStartTime == nil {
      guard writer.startWriting() else {
        let message = writer.error?.localizedDescription ?? "AVAssetWriter no pudo iniciar."
        cleanupWriterState(removeTemporaryFile: false)
        emitRecordingError(message)
        return
      }

      writer.startSession(atSourceTime: presentationTime)
      writerSessionStartTime = presentationTime
    }

    guard writer.status == .writing, videoInput.isReadyForMoreMediaData else { return }

    var frontPixelBuffer: CVPixelBuffer?
    if recordingFrontCameraVisible,
       let frontData = synchronizedDataCollection.synchronizedData(for: frontVideoOutput)
        as? AVCaptureSynchronizedSampleBufferData,
       !frontData.sampleBufferWasDropped {
      frontPixelBuffer = CMSampleBufferGetImageBuffer(frontData.sampleBuffer)
    }

    guard let pool = adaptor.pixelBufferPool else { return }
    var outputPixelBuffer: CVPixelBuffer?
    let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outputPixelBuffer)
    guard status == kCVReturnSuccess, let outputPixelBuffer else { return }

    autoreleasepool {
      let composition = composeFrame(back: backPixelBuffer, front: frontPixelBuffer)
      ciContext.render(
        composition,
        to: outputPixelBuffer,
        bounds: CGRect(origin: .zero, size: outputSize),
        colorSpace: outputColorSpace
      )
      _ = adaptor.append(outputPixelBuffer, withPresentationTime: presentationTime)
    }
  }

  // MARK: - Audio samples

  func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    guard output === audioOutput,
          isRecordingNative,
          let writer = assetWriter,
          writer.status == .writing,
          let audioInput = audioWriterInput,
          audioInput.isReadyForMoreMediaData,
          let startTime = writerSessionStartTime else {
      return
    }

    let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
    guard CMTimeCompare(pts, startTime) >= 0 else { return }

    _ = audioInput.append(sampleBuffer)
  }

  // MARK: - CoreImage compositor

  private func composeFrame(back: CVPixelBuffer, front: CVPixelBuffer?) -> CIImage {
    let outputRect = CGRect(origin: .zero, size: outputSize)
    let backImage = aspectFill(CIImage(cvPixelBuffer: back), to: outputRect)
    var result = backImage

    if recordingFrontCameraVisible, let front {
      let diameter = outputSize.width * recordingPipDiameterRatio
      let margin = outputSize.width * recordingPipMarginRatio
      let topY = outputSize.height * recordingPipTopRatio

      // CoreImage's Y axis is bottom-up; convert from our UIKit-style top coordinate.
      let pipRect = CGRect(
        x: outputSize.width - diameter - margin,
        y: outputSize.height - topY - diameter,
        width: diameter,
        height: diameter
      )

      let frontImage = aspectFill(CIImage(cvPixelBuffer: front), to: pipRect)
      let transparentCanvas = CIImage(color: CIColor.clear).cropped(to: outputRect)
      let frontCanvas = frontImage.composited(over: transparentCanvas)

      if let radial = CIFilter(name: "CIRadialGradient", parameters: [
        "inputCenter": CIVector(x: pipRect.midX, y: pipRect.midY),
        "inputRadius0": max(0, diameter / 2 - 1.5),
        "inputRadius1": diameter / 2,
        "inputColor0": CIColor.white,
        "inputColor1": CIColor.black
      ])?.outputImage?.cropped(to: outputRect),
         let blend = CIFilter(name: "CIBlendWithMask", parameters: [
          kCIInputImageKey: frontCanvas,
          kCIInputBackgroundImageKey: result,
          kCIInputMaskImageKey: radial
         ])?.outputImage {
        result = blend.cropped(to: outputRect)
      }
    }

    if let overlay = recordingOverlayCIImage {
      result = overlay.composited(over: result).cropped(to: outputRect)
    }

    return result
  }

  private func aspectFill(_ image: CIImage, to targetRect: CGRect) -> CIImage {
    let extent = image.extent
    guard extent.width > 0, extent.height > 0 else {
      return image.cropped(to: targetRect)
    }

    let scale = max(targetRect.width / extent.width, targetRect.height / extent.height)
    let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    let tx = targetRect.midX - scaled.extent.midX
    let ty = targetRect.midY - scaled.extent.midY

    return scaled
      .transformed(by: CGAffineTransform(translationX: tx, y: ty))
      .cropped(to: targetRect)
  }

  // MARK: - Recording overlay snapshot

  private struct RecordingOverlaySnapshot {
    let overlay: CIImage?
    let frontVisible: Bool
    let pipDiameterRatio: CGFloat
    let pipMarginRatio: CGFloat
    let pipTopRatio: CGFloat
  }

  private func captureRecordingOverlaySnapshot() -> RecordingOverlaySnapshot {
    var overlay: CIImage?
    var frontVisible = true
    var diameterRatio: CGFloat = 0.31
    var marginRatio: CGFloat = 0.04
    var topRatio: CGFloat = 0.065

    DispatchQueue.main.sync { [weak self] in
      guard let self else { return }

      frontVisible = self.frontCameraVisible
      let previewWidth = max(self.bounds.width, 1)
      let previewHeight = max(self.bounds.height, 1)

      diameterRatio = min(0.42, max(0.18, self.pipDiameter / previewWidth))
      marginRatio = min(0.12, max(0.015, self.pipMargin / previewWidth))
      topRatio = min(0.20, max(0.025, max(self.safeAreaInsets.top + 12, previewHeight * 0.055) / previewHeight))

      if let image = self.renderRecordingOverlayImage(
        size: self.outputSize,
        includePipBorder: frontVisible,
        pipDiameterRatio: diameterRatio,
        pipMarginRatio: marginRatio,
        pipTopRatio: topRatio
      ),
         let ciImage = CIImage(image: image) {
        overlay = ciImage.cropped(to: CGRect(origin: .zero, size: self.outputSize))
      }
    }

    return RecordingOverlaySnapshot(
      overlay: overlay,
      frontVisible: frontVisible,
      pipDiameterRatio: diameterRatio,
      pipMarginRatio: marginRatio,
      pipTopRatio: topRatio
    )
  }

  private func renderRecordingOverlayImage(
    size: CGSize,
    includePipBorder: Bool,
    pipDiameterRatio: CGFloat,
    pipMarginRatio: CGFloat,
    pipTopRatio: CGFloat
  ) -> UIImage? {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = false

    let renderer = UIGraphicsImageRenderer(size: size, format: format)
    return renderer.image { context in
      let cg = context.cgContext
      cg.clear(CGRect(origin: .zero, size: size))

      let w = size.width
      let h = size.height

      // Top-left VEA brand.
      if logoVisible, let logoImage {
        let logoRect = CGRect(
          x: w * 0.022,
          y: h * 0.012,
          width: w * logoWidthRatio,
          height: h * 0.105
        )
        drawAspectFit(image: logoImage, in: logoRect, context: cg)
      }

      drawText(
        "www.iglesiavea.com",
        in: CGRect(x: w * 0.027, y: h * 0.105, width: w * 0.40, height: h * 0.035),
        font: UIFont(name: "AvenirNext-Regular", size: w * 0.026) ?? UIFont.systemFont(ofSize: w * 0.026),
        color: .white,
        context: cg
      )

      // Lower-third cover.
      let lowerY = h * 0.742
      let coverSize = w * 0.115
      let coverRect = CGRect(x: w * 0.140, y: lowerY + h * 0.010, width: coverSize, height: coverSize)
      if let coverImage {
        drawAspectFill(image: coverImage, in: coverRect, context: cg)
        cg.setStrokeColor(UIColor.white.withAlphaComponent(0.65).cgColor)
        cg.setLineWidth(1.5)
        cg.stroke(coverRect)
      }

      let textX = w * 0.265
      let textWidth = w - textX - w * 0.035
      let watchingFont = w * 0.030
      let titleFont = w * 0.058
      let metadataFontSize = w * 0.030

      drawText(
        "Estas viendo",
        in: CGRect(x: textX, y: lowerY, width: textWidth, height: watchingFont * 1.45),
        font: UIFont(name: "AvenirNextCondensed-Regular", size: watchingFont)
          ?? UIFont.systemFont(ofSize: watchingFont, weight: .light),
        color: .white,
        context: cg
      )

      let title = sermonTitle.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
      drawText(
        title,
        in: CGRect(
          x: textX,
          y: lowerY + watchingFont * 1.10,
          width: textWidth,
          height: titleFont * 1.18
        ),
        font: UIFont(name: "AvenirNextCondensed-DemiBold", size: titleFont)
          ?? UIFont.systemFont(ofSize: titleFont, weight: .semibold),
        color: .white,
        context: cg
      )

      let metadataStartY = lowerY + watchingFont * 1.10 + titleFont * 1.02
      let metadataLine = metadataFontSize * 1.20
      let metadataFont = UIFont(name: "AvenirNextCondensed-Regular", size: metadataFontSize)
        ?? UIFont.systemFont(ofSize: metadataFontSize, weight: .light)

      drawText(
        "VEA Comunidad Cristiana",
        in: CGRect(x: textX, y: metadataStartY, width: textWidth, height: metadataLine),
        font: metadataFont,
        color: .white,
        context: cg
      )
      drawText(
        "P.S. Mauricio Sánchez Scott",
        in: CGRect(x: textX, y: metadataStartY + metadataLine, width: textWidth, height: metadataLine),
        font: metadataFont,
        color: .white,
        context: cg
      )
      drawText(
        "www.iglesiavea.com",
        in: CGRect(x: textX, y: metadataStartY + metadataLine * 2, width: textWidth, height: metadataLine),
        font: metadataFont,
        color: .white,
        context: cg
      )

      // White PiP rim is part of the encoded composition, not the React HUD.
      if includePipBorder {
        let diameter = w * pipDiameterRatio
        let margin = w * pipMarginRatio
        let topY = h * pipTopRatio
        let pipRect = CGRect(x: w - diameter - margin, y: topY, width: diameter, height: diameter)
        cg.setStrokeColor(UIColor.white.withAlphaComponent(0.92).cgColor)
        cg.setLineWidth(max(3, w * 0.004))
        cg.strokeEllipse(in: pipRect.insetBy(dx: 1.5, dy: 1.5))
      }
    }
  }

  private func drawText(
    _ text: String,
    in rect: CGRect,
    font: UIFont,
    color: UIColor,
    context: CGContext
  ) {
    guard !text.isEmpty else { return }

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: 2), blur: 4, color: UIColor.black.withAlphaComponent(0.75).cgColor)

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .left
    paragraph.lineBreakMode = .byTruncatingTail

    let attributes: [NSAttributedString.Key: Any] = [
      .font: font,
      .foregroundColor: color,
      .paragraphStyle: paragraph
    ]

    (text as NSString).draw(in: rect, withAttributes: attributes)
    context.restoreGState()
  }

  private func drawAspectFit(image: UIImage, in rect: CGRect, context: CGContext) {
    guard image.size.width > 0, image.size.height > 0 else { return }

    let scale = min(rect.width / image.size.width, rect.height / image.size.height)
    let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
    let drawRect = CGRect(
      x: rect.midX - drawSize.width / 2,
      y: rect.midY - drawSize.height / 2,
      width: drawSize.width,
      height: drawSize.height
    )

    context.saveGState()
    image.draw(in: drawRect)
    context.restoreGState()
  }

  private func drawAspectFill(image: UIImage, in rect: CGRect, context: CGContext) {
    guard image.size.width > 0, image.size.height > 0 else { return }

    let scale = max(rect.width / image.size.width, rect.height / image.size.height)
    let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
    let drawRect = CGRect(
      x: rect.midX - drawSize.width / 2,
      y: rect.midY - drawSize.height / 2,
      width: drawSize.width,
      height: drawSize.height
    )

    context.saveGState()
    context.clip(to: rect)
    image.draw(in: drawRect)
    context.restoreGState()
  }

  // MARK: - Photos

  private func saveRecordingToPhotos(url: URL) {
    PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
      guard let self else { return }

      guard status == .authorized || status == .limited else {
        self.recordingQueue.async {
          self.cleanupWriterState(removeTemporaryFile: false)
          self.emitRecordingError("El video terminó, pero iOS no permitió guardarlo en Fotos. Activa el permiso de Fotos para VEA Camera.")
        }
        return
      }

      PHPhotoLibrary.shared().performChanges({
        PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
      }) { success, error in
        self.recordingQueue.async {
          if success {
            self.cleanupWriterState(removeTemporaryFile: true)
            DispatchQueue.main.async { [weak self] in
              self?.onRecordingFinished([
                "recording": false,
                "savedToPhotos": true
              ])
            }
          } else {
            let message = error?.localizedDescription ?? "iOS no pudo guardar el video en Fotos."
            self.cleanupWriterState(removeTemporaryFile: false)
            self.emitRecordingError(message)
          }
        }
      }
    }
  }

  // MARK: - Events

  private func emitError(_ message: String) {
    DispatchQueue.main.async { [weak self] in
      self?.onError(["message": message])
    }
  }

  private func emitRecordingError(_ message: String) {
    DispatchQueue.main.async { [weak self] in
      self?.onRecordingError(["message": message])
    }
  }
}
