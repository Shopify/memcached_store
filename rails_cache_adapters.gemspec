# -*- encoding: utf-8 -*-

Gem::Specification.new do |gem|
  gem.authors       = ["Camilo Lopez", "Tom Burns"]
  gem.email         = ["camilo@camilolopez.com", "tom.burns@shopify.com"]
  gem.description   = %q{Plugin-able Memcached adapters to add features (compression, safety)}
  gem.summary       = %q{Plugin-able Memcached adapters to add features (compression, safety)}
  gem.homepage      = ""

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "rails_cache_adapters"
  gem.require_paths = ["lib"]
  gem.version       = '0.0.1'
  gem.add_runtime_dependency "activesupport", ">= 3.2"
  gem.add_runtime_dependency "snappy", "0.0.4"
  gem.add_runtime_dependency "memcached"

  gem.add_development_dependency "rake"
  gem.add_development_dependency "minitest"
  gem.add_development_dependency "mocha"
  gem.add_development_dependency "timecop"
end
