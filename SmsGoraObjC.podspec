Pod::Spec.new do |s|
  s.name             = 'SmsGoraObjC'
  s.version          = '1.0.0'
  s.summary          = 'SMS Gora SMS Gateway: official Objective-C client by Tekservix'
  s.description      = 'SMS Gora SMS Gateway: official Objective-C client by Tekservix. Send and receive SMS through your own Android phones, check delivery, read incoming SMS and verify signed webhooks. No dependencies beyond Foundation. Requires a Tekservix account with SMS Gora.'
  s.homepage         = 'https://tekservix.com/smsgora/'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Tekservix' => 'support@tekservix.com' }
  s.source           = { :git => 'https://github.com/TekservixHQ/smsgora-swift.git', :tag => "objc-v#{s.version}" }
  s.documentation_url = 'https://tekservix.com/smsgora/docs/'
  s.ios.deployment_target     = '12.0'
  s.osx.deployment_target     = '10.13'
  s.tvos.deployment_target    = '12.0'
  s.watchos.deployment_target = '4.0'
  s.requires_arc     = true
  s.source_files     = 'ObjC/SmsGoraObjC/**/*.{h,m}'
  s.public_header_files = 'ObjC/SmsGoraObjC/**/*.h'
  s.frameworks       = 'Foundation'

  s.test_spec 'Tests' do |t|
    t.source_files = 'ObjC/Tests/**/*.m'
    t.frameworks = 'XCTest'
    t.platforms = { :ios => '12.0', :osx => '10.13' }
  end
end
