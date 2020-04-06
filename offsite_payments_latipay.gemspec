$:.push File.expand_path("../lib", __FILE__)
require 'offsite_payments/version'

Gem::Specification.new do |s|
  s.platform     = Gem::Platform::RUBY
  s.name         = 'offsite_payments_latipay'
  s.version      = OffsitePayments::Integration::Latipay::VERSION
  s.date         = '2020-02-21'
  s.summary      = 'Latipay integration for the activemerchant offsite_payments gem.'
  s.description  = 'This gem extends the activemerchant offsite_payments gem ' \
                   'providing integration of Latipay.'
  s.license      = 'MIT'

  s.author = 'Zheng Jing'
  s.email = 'zheng.jing@sealink.com.au'
  s.homepage = 'https://github.com/sealink/offsite_payments_latipay'

  s.files = Dir['CHANGELOG', 'README.md', 'LICENSE', 'lib/**/*']
  s.require_path = 'lib'

  s.add_dependency('offsite_payments')

  s.add_development_dependency('bundler')
  s.add_development_dependency('rake')
  s.add_development_dependency('money')
  s.add_development_dependency('test-unit', '~> 3.0')
end
