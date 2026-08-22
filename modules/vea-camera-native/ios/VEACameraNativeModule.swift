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

      Prop("logoVisible") { (view: VEADualCameraView, value: Bool) in
        view.logoVisible = value
      }

      Prop("logoWidthRatio") { (view: VEADualCameraView, value: Double) in
        view.logoWidthRatio = CGFloat(max(0.18, min(value, 0.45)))
      }

      Prop("tiktokSafeRightRatio") { (view: VEADualCameraView, value: Double) in
        view.tiktokSafeRightRatio = CGFloat(max(0.08, min(value, 0.32)))
      }

      Prop("tiktokSafeBottomRatio") { (view: VEADualCameraView, value: Double) in
        view.tiktokSafeBottomRatio = CGFloat(max(0.08, min(value, 0.32)))
      }

      Prop("showTikTokSafeZone") { (view: VEADualCameraView, value: Bool) in
        view.showTikTokSafeZone = value
      }
    }
  }
}
