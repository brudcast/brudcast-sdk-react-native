require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

Pod::Spec.new do |s|
  s.name         = "BrudcastReactNativeInApp"
  s.module_name  = "BrudcastInApp"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = package["homepage"]
  s.license      = { :type => package["license"], :file => "LICENSE" }
  s.authors      = package["author"]

  s.platforms    = { :ios => min_ios_version_supported }
  s.source       = { :git => "https://github.com/brudcast/brudcast-sdk-react-native.git", :tag => "v#{s.version}" }
  s.swift_versions = ["5.9"]

  s.source_files = "ios/**/*.{h,m,mm,swift}"
  s.private_header_files = "ios/**/*.h"
  s.exclude_files = "ios/vendor/**/*.xcprivacy"
  s.resource_bundles = { "BrudcastInApp_Privacy" => ["ios/vendor/BrudcastInApp/PrivacyInfo.xcprivacy"] }
  s.frameworks   = "Foundation", "UIKit", "SwiftUI", "Combine"

  s.dependency "BrudcastReactNative", package["version"]

  install_modules_dependencies(s)
end
