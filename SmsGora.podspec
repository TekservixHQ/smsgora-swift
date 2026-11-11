Pod::Spec.new do |s|
  s.name             = 'SmsGora'
  s.version          = '1.0.1'
  s.summary          = 'SMS Gora SMS Gateway: official Swift client by Tekservix'
  s.description      = 'SMS Gora SMS Gateway: official Swift client by Tekservix. Send and receive SMS through your own Android phones, check delivery, read incoming SMS and verify signed webhooks. Requires a Tekservix account with SMS Gora.'
  s.homepage         = 'https://tekservix.com/smsgora'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Tekservix' => 'support@tekservix.com' }
  s.source           = { :git => 'https://github.com/TekservixHQ/smsgora-swift.git', :tag => "v#{s.version}" }
  s.documentation_url = 'https://tekservix.com/smsgora/docs/'
  s.swift_versions   = ['5.7', '5.8', '5.9', '5.10', '6.0']
  s.ios.deployment_target     = '13.0'
  s.osx.deployment_target     = '10.15'
  s.tvos.deployment_target    = '13.0'
  s.watchos.deployment_target = '6.0'
  s.source_files     = 'Sources/SmsGora/**/*.swift'
  s.frameworks       = 'Foundation'
end
