Pod::Spec.new do |s|
  s.name           = 'VEACameraNative'
  s.version        = '0.1.0'
  s.summary        = 'VEA Camera native MultiCam module'
  s.description    = 'Native AVCaptureMultiCamSession preview for VEA Camera.'
  s.author         = 'VEA'
  s.homepage       = 'https://expo.dev'
  s.license        = { :type => 'MIT' }
  s.platforms      = { :ios => '16.4' }
  s.swift_version  = '5.9'
  s.source         = { :git => 'https://github.com/expo/expo.git' }
  s.static_framework = true

  s.dependency 'ExpoModulesCore'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'SWIFT_COMPILATION_MODE' => 'wholemodule'
  }

  s.source_files = '**/*.{h,m,mm,swift,hpp,cpp}'
end
