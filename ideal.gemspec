# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "ideal/version"

Gem::Specification.new do |s|
  s.name = %q{ideal}
  s.version      = Ideal::VERSION
  s.authors      = ["Soemirno Kartosoewito", "Matthijs Kadijk", "Eloy Duran", "Manfred Stienstra", "Frank Oxener"]
  s.description  = %q{iDEAL payment gateway (see http://www.ideal.nl and http://www.activemerchant.org/)}
  s.summary      = %q{iDEAL payment gateway}
  s.email        = %q{manfred@fngtps.com}

  s.homepage     = %q{http://github.com/Fingertips/ideal}

  s.extra_rdoc_files = [
     "LICENSE",
     "README.textile"
   ]

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  s.add_development_dependency "mocha"
end
