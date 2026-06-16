Pod::Spec.new do |s|
  s.name             = 'refresh_rate'
  s.version          = '1.0.2'
  s.summary          = 'Control display refresh rates in Flutter.'
  s.description      = <<-DESC
Cross-platform Flutter plugin to query and control display refresh rates.
                       DESC
  s.homepage         = 'https://qoder.in'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Qoder' => 'dev@qoder.in' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'
  s.platform         = :osx, '10.14'
  s.swift_version    = '5.0'
end
