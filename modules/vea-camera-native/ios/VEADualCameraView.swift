import AVFoundation
import ExpoModulesCore
import UIKit

final class VEADualCameraView: ExpoView {
  let onReady = EventDispatcher()
  let onError = EventDispatcher()

  var pipDiameter: CGFloat = 132 {
    didSet { setNeedsLayout() }
  }

  var pipMargin: CGFloat = 18 {
    didSet { setNeedsLayout() }
  }

  // MARK: - VEA logo / TikTok safe-zone preset

  var logoVisible: Bool = true {
    didSet { logoLayer.isHidden = !logoVisible }
  }

  /// Width of the logo container as a percentage of the preview width.
  /// 0.34 works well with the supplied square PNG, which has transparent padding.
  var logoWidthRatio: CGFloat = 0.34 {
    didSet { setNeedsLayout() }
  }

  /// Conservative VEA preset for TikTok's right-side UI rail.
  /// TikTok's official safe zone varies by caption length and add-ons, so this is configurable.
  var tiktokSafeRightRatio: CGFloat = 0.16 {
    didSet { setNeedsLayout() }
  }

  /// Conservative VEA preset for TikTok's lower caption/navigation UI.
  var tiktokSafeBottomRatio: CGFloat = 0.18 {
    didSet { setNeedsLayout() }
  }

  /// Development-only guide. Set true from React Native to visualize the working safe zone.
  var showTikTokSafeZone: Bool = false {
    didSet { safeZoneOverlay.isHidden = !showTikTokSafeZone }
  }

  private let session = AVCaptureMultiCamSession()
  private let sessionQueue = DispatchQueue(label: "org.vea.camera.multicam.session", qos: .userInitiated)

  private var backPreviewLayer: AVCaptureVideoPreviewLayer?
  private var frontPreviewLayer: AVCaptureVideoPreviewLayer?
  private var configured = false
  private var configuring = false

  // Render the watermark as a CALayer, just like the AVCapture preview layers.
  // This guarantees that its z-order is respected above both camera layers.
  private let logoLayer: CALayer = {
    let layer = CALayer()
    layer.contentsGravity = .resizeAspect
    layer.masksToBounds = false
    layer.shadowColor = UIColor.black.cgColor
    layer.shadowOpacity = 0.34
    layer.shadowRadius = 6
    layer.shadowOffset = CGSize(width: 0, height: 2)
    layer.zPosition = 10_000
    return layer
  }()

  private var didLogLogoFrame = false

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

  required init(appContext: AppContext? = nil) {
    super.init(appContext: appContext)
    backgroundColor = .black
    clipsToBounds = true

    if let logoImage = Self.loadLogoImage() {
      logoLayer.contents = logoImage.cgImage
      logoLayer.contentsScale = logoImage.scale
    }

    addSubview(safeZoneOverlay)
    layer.addSublayer(logoLayer)
  }

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

    backPreviewLayer?.frame = bounds

    let diameter = min(pipDiameter, max(72, bounds.width * 0.42))
    let safeTop = safeAreaInsets.top
    let pipX = max(pipMargin, bounds.width - diameter - pipMargin)
    let pipY = safeTop + 74

    if let frontPreviewLayer {
      frontPreviewLayer.frame = CGRect(x: pipX, y: pipY, width: diameter, height: diameter)
      frontPreviewLayer.cornerRadius = diameter / 2
      frontPreviewLayer.masksToBounds = true
      frontPreviewLayer.borderWidth = 2
      frontPreviewLayer.borderColor = UIColor.white.withAlphaComponent(0.88).cgColor
    }

    // TikTok does not publish one immutable safe-zone rectangle for every post;
    // it changes with caption length and extra UI. These insets are therefore a
    // conservative, configurable VEA preset for 9:16 content.
    let safeLeft = max(18, bounds.width * 0.06)
    let safeRight = max(52, bounds.width * tiktokSafeRightRatio)
    let safeTopForSocial = max(safeAreaInsets.top + 8, bounds.height * 0.08)
    let safeBottom = max(safeAreaInsets.bottom + 24, bounds.height * tiktokSafeBottomRatio)

    let safeWidth = max(0, bounds.width - safeLeft - safeRight)
    let safeHeight = max(0, bounds.height - safeTopForSocial - safeBottom)
    let safeFrame = CGRect(
      x: safeLeft,
      y: safeTopForSocial,
      width: safeWidth,
      height: safeHeight
    )
    safeZoneOverlay.frame = safeFrame

    // The supplied logo PNG is square with transparent padding, so its container
    // is intentionally a little larger than the visible mark.
    let requestedLogoWidth = bounds.width * logoWidthRatio
    let logoWidth = min(max(requestedLogoWidth, 108), 168)
    let logoHeight = logoWidth

    logoLayer.frame = CGRect(
      x: max(safeFrame.minX, safeFrame.maxX - logoWidth),
      y: max(safeFrame.minY, safeFrame.maxY - logoHeight),
      width: logoWidth,
      height: logoHeight
    )
    logoLayer.zPosition = 10_000

    if !didLogLogoFrame, logoLayer.contents != nil {
      didLogLogoFrame = true
      print("[VEACameraNative] 🖼️ Logo frame: \(logoLayer.frame) | view bounds: \(bounds)")
    }

    bringSubviewToFront(safeZoneOverlay)
    safeZoneOverlay.layer.zPosition = 9_000
  }

  deinit {
    if session.isRunning {
      session.stopRunning()
    }
  }

  private static func loadLogoImage() -> UIImage? {
    let imageName = "vea-logo"
    let imageExtension = "png"
    let resourceBundleName = "VEACameraNativeResources"

    // CocoaPods can place resources either directly in the application bundle
    // or inside the resource bundle generated by `s.resource_bundles`.
    // Search both locations explicitly instead of relying on Bundle(for:) alone.
    var candidateBundles: [Bundle] = [
      Bundle.main,
      Bundle(for: VEADualCameraView.self)
    ]

    candidateBundles.append(contentsOf: Bundle.allFrameworks)
    candidateBundles.append(contentsOf: Bundle.allBundles)

    // Remove duplicated bundle paths while preserving the search order.
    var seenPaths = Set<String>()
    candidateBundles = candidateBundles.filter { bundle in
      let path = bundle.bundlePath
      guard !seenPaths.contains(path) else { return false }
      seenPaths.insert(path)
      return true
    }

    for containerBundle in candidateBundles {
      // 1) PNG copied directly into a bundle (s.resources).
      if let imagePath = containerBundle.path(
        forResource: imageName,
        ofType: imageExtension
      ),
        let image = UIImage(contentsOfFile: imagePath) {
        print("[VEACameraNative] ✅ Logo VEA cargado desde: \(imagePath)")
        return image
      }

      // 2) PNG stored inside VEACameraNativeResources.bundle.
      if let resourceBundleURL = containerBundle.url(
        forResource: resourceBundleName,
        withExtension: "bundle"
      ),
        let resourceBundle = Bundle(url: resourceBundleURL) {

        if let imagePath = resourceBundle.path(
          forResource: imageName,
          ofType: imageExtension
        ),
          let image = UIImage(contentsOfFile: imagePath) {
          print("[VEACameraNative] ✅ Logo VEA cargado desde: \(imagePath)")
          return image
        }

        if let image = UIImage(
          named: imageName,
          in: resourceBundle,
          compatibleWith: nil
        ) {
          print("[VEACameraNative] ✅ Logo VEA cargado desde resource bundle")
          return image
        }
      }
    }

    // Final UIKit fallback.
    if let image = UIImage(named: imageName) {
      print("[VEACameraNative] ✅ Logo VEA cargado con UIImage(named:)")
      return image
    }

    print("[VEACameraNative] ❌ No se encontró vea-logo.png en ningún bundle")
    return nil
  }

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
        let backDevice = AVCaptureDevice.default(
          .builtInWideAngleCamera,
          for: .video,
          position: .back
        ),
        let frontDevice = AVCaptureDevice.default(
          .builtInWideAngleCamera,
          for: .video,
          position: .front
        )
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

        // Keep UI overlays deterministically above AVCaptureVideoPreviewLayer.
        self.safeZoneOverlay.layer.zPosition = 9_000
        self.logoLayer.zPosition = 10_000

        self.bringSubviewToFront(self.safeZoneOverlay)
        self.setNeedsLayout()
        self.layoutIfNeeded()
      }

      let backConnection = AVCaptureConnection(inputPort: backPort, videoPreviewLayer: backLayer)
      let frontConnection = AVCaptureConnection(inputPort: frontPort, videoPreviewLayer: frontLayer)

      guard session.canAddConnection(backConnection), session.canAddConnection(frontConnection) else {
        emitError("No pude conectar las cámaras a sus vistas de preview.")
        return false
      }

      session.addConnection(backConnection)
      session.addConnection(frontConnection)

      configurePortraitOrientation(for: backConnection)
      configurePortraitOrientation(for: frontConnection)

      frontConnection.automaticallyAdjustsVideoMirroring = false
      if frontConnection.isVideoMirroringSupported {
        frontConnection.isVideoMirrored = true
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

  private func emitError(_ message: String) {
    DispatchQueue.main.async { [weak self] in
      self?.onError(["message": message])
    }
  }
}
