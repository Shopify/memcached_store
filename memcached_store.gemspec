# encoding: utf-8
lib = File.expand_path('../lib/', __FILE__)
$:.unshift lib unless $:.include?(lib)
require "memcached_store/version"

Gem::Specification.new do |gem|
  gem.authors       = ["Camilo Lopez", "Tom Burns", "Arthur Neves"]
  gem.email         = ["camilo@camilolopez.com", "tom.burns@shopify.com", "arthurnn@gmail.com"]
  gem.summary = gem.description   = %q{Plugin-able Memcached adapters to add features (compression, safety)}
  gem.homepage      = "https://github.com/Shopify/memcached_store/"

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "memcached_store"
  gem.require_paths = ["lib"]
  gem.version       = MemcachedStore::VERSION
  gem.add_runtime_dependency "activesupport", ">=  3.2"
  gem.add_runtime_dependency "snappy", "0.0.4"
  gem.add_development_dependency "i18n"
  gem.add_development_dependency "rake"
  gem.add_development_dependency "minitest"
  gem.add_development_dependency "mocha"
  gem.add_development_dependency "timecop"
  gem.add_development_dependency "memcached"
  gem.add_development_dependency "memcache-client"
end
