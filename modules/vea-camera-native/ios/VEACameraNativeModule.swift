import AVFoundation
import ExpoModulesCore

public class VEACameraNativeModule: Module {
  public func definition() -> ModuleDefinition {
    Name("VEACameraNative")

    Function("isMultiCamSupported") { () -> Bool in
      return AVCaptureMultiCamSession.isMultiCamSupported
    }

    View(VEADualCameraView.self) {
      Events("onReady", "onError")

      Prop("pipDiameter") { (view: VEADualCameraView, value: Double) in
        view.pipDiameter = CGFloat(max(72, min(value, 220)))
      }

      Prop("pipMargin") { (view: VEADualCameraView, value: Double) in
        view.pipMargin = CGFloat(max(8, min(value, 48)))
      }

      Prop("logoText") { (view: VEADualCameraView, value: String) in
        view.logoText = value
      }

      Prop("logoVisible") { (view: VEADualCameraView, value: Bool) in
        view.logoVisible = value
      }
    }
  }
}
