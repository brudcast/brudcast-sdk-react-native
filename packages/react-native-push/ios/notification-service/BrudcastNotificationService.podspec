require "json"

package = JSON.parse(File.read(File.join(__dir__, "..", "..", "package.json")))

Pod::Spec.new do |s|
  s.name         = "BrudcastNotificationService"
  s.version      = package["version"]
  s.summary      = "Brudcast for a notification service extension: notification images and push_received."
  s.homepage     = package["homepage"]
  s.license      = package["license"]
  s.authors      = package["author"]

  s.platforms    = { :ios => "15.1" }
  s.source       = { :git => "https://github.com/brudcast/brudcast-sdk-react-native.git", :tag => "v#{s.version}" }
  s.swift_versions = ["5.9"]

  s.source_files = "BrudcastNotificationService/**/*.swift"
  s.resource_bundles = { "BrudcastNotificationService_Privacy" => ["BrudcastNotificationService/PrivacyInfo.xcprivacy"] }
  s.frameworks   = "Foundation", "UserNotifications", "CryptoKit"
end
