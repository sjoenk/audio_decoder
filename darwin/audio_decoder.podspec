#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint audio_decoder.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'audio_decoder'
  s.version          = '0.7.0'
  s.summary          = 'A lightweight Flutter plugin for converting, trimming, and analyzing audio files.'
  s.description      = <<-DESC
A lightweight Flutter plugin for converting, trimming, and analyzing audio files using native platform APIs.
                       DESC
  s.homepage         = 'https://github.com/sjoenk/audio_decoder'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Silversoft' => 'info@silversoft.nl' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'

  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'
  s.ios.deployment_target = '13.0'
  s.osx.deployment_target = '10.15'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
