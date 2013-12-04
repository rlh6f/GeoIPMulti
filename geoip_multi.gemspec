Gem::Specification.new do |s|
  s.name        = 'geoip_multi'
  s.version     = '0.1.0'
  s.date        = '2013-12-03'
  s.add_runtime_dependency "geoip", [">=1.3.3"]
  s.summary     = "Extension of geoip"
  s.description = "==Extends native ruby geoip gem. Adds support for netmask() and range_by_ip() methods to the GeoIP class and creates a new class GeoIPMulti that performs lookups on multiple GeoIP databases with a single lookup() method"
  s.authors     = ["Ryan Harris"]
  s.email       = 'rubygems.rharris@neverbox.com'
  s.files       = ["lib/geoip_multi.rb"]
  s.homepage    = 'http://github.com/rlh6f/GeoIPMulti'
  s.license       = 'GPL'
end