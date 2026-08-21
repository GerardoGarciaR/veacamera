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

  var logoText: String = "VEA" {
    didSet { logoLabel.text = logoText }
  }

  var logoVisible: Bool = true {
    didSet { logoLabel.isHidden = !logoVisible }
  }

  private let session = AVCaptureMultiCamSession()
  private let sessionQueue = DispatchQueue(label: "org.vea.camera.multicam.session", qos: .userInitiated)

  private var backPreviewLayer: AVCaptureVideoPreviewLayer?
  private var frontPreviewLayer: AVCaptureVideoPreviewLayer?
  private var configured = false
  private var configuring = false

  private let logoLabel: UILabel = {
    let label = UILabel()
    label.text = "VEA"
    label.textColor = .white
    label.font = .systemFont(ofSize: 25, weight: .black)
    label.layer.shadowColor = UIColor.black.cgColor
    label.layer.shadowOpacity = 0.5
    label.layer.shadowRadius = 5
    label.layer.shadowOffset = CGSize(width: 0, height: 2)
    return label
  }()

  required init(appContext: AppContext? = nil) {
    super.init(appContext: appContext)
    backgroundColor = .black
    clipsToBounds = true
    addSubview(logoLabel)
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
    let x = max(pipMargin, bounds.width - diameter - pipMargin)
    let y = safeTop + 74

    if let frontPreviewLayer {
      frontPreviewLayer.frame = CGRect(x: x, y: y, width: diameter, height: diameter)
      frontPreviewLayer.cornerRadius = diameter / 2
      frontPreviewLayer.masksToBounds = true
      frontPreviewLayer.borderWidth = 2
      frontPreviewLayer.borderColor = UIColor.white.withAlphaComponent(0.88).cgColor
    }

    let logoSize = logoLabel.sizeThatFits(CGSize(width: 180, height: 54))
    logoLabel.frame = CGRect(
      x: pipMargin,
      y: safeTop + 78,
      width: max(logoSize.width, 60),
      height: 38
    )
  }

  deinit {
    if session.isRunning {
      session.stopRunning()
    }
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

        self.layer.insertSublayer(backLayer, at: 0)
        self.layer.insertSublayer(frontLayer, above: backLayer)
        self.bringSubviewToFront(self.logoLabel)
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
