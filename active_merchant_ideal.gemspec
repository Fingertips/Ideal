# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "active_merchant_ideal/version"

Gem::Specification.new do |s|
  s.name = %q{active_merchant_ideal}
  s.version      = ActiveMerchantIdeal::VERSION
  s.authors      = ["Soemirno Kartosoewito, Matthijs Kadijk, Aloy Duran, Frank Oxener and many others"]
  s.description  = %q{iDEAL payment gateway for ActiveMerchant (see http://www.ideal.nl and http://www.activemerchant.org/)}
  s.summary      = %q{iDEAL gateway for ActiveMerchant}
  s.email        = %q{frank.oxener@gmail.com}

  s.homepage     = %q{http://github.com/dovadi/active_merchant_ideal}

  s.extra_rdoc_files = [
     "LICENSE",
     "README.textile"
   ]

  s.rubyforge_project = "active_merchant_ideal"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  s.add_development_dependency "mocha"
end
