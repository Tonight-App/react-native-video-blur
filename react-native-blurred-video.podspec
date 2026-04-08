require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

Pod::Spec.new do |s|
  s.name         = "react-native-blurred-video"
  s.module_name  = "BlurredVideo"
  s.header_dir   = "BlurredVideo"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = package["repository"]
  s.license      = package["license"]
  s.author       = package["author"]
  s.platforms    = { :ios => "13.0" }
  s.source       = { :git => "#{package["repository"]}.git", :tag => "#{s.version}" }

  s.source_files = [
    "ios/**/*.{swift,h,m,mm}",
    "cpp/**/*.{hpp,cpp}"
  ]

  s.frameworks = "AVFoundation", "UIKit", "CoreImage"

  load 'nitrogen/generated/ios/BlurredVideo+autolinking.rb'
  add_nitrogen_files(s)

  s.dependency "React-Core"
  install_modules_dependencies(s)
end
