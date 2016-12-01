# encoding: utf-8
lib = File.expand_path('../lib/', __FILE__)
$LOAD_PATH.unshift lib unless $LOAD_PATH.include?(lib)
require "memcached_store/version"

Gem::Specification.new do |gem|
  gem.name = "memcached_store"
  gem.authors = ["Camilo Lopez", "Tom Burns", "Arthur Neves", "Francis Bogsanyi"]
  gem.email = ["camilo@camilolopez.com", "tom.burns@shopify.com", "arthurnn@gmail.com", "francis.bogsanyi@shopify.com"]
  gem.summary = gem.description = 'Plugin-able Memcached adapters to add features (compression, safety)'
  gem.homepage = "https://github.com/Shopify/memcached_store/"
  gem.license = "MIT"

  gem.version = MemcachedStore::VERSION
  gem.files = Dir["lib/**/*.rb", "README.md", "LICENSE"]
  gem.require_paths = ["lib"]

  gem.required_ruby_version = ">= 2.2.0"

  gem.add_runtime_dependency "activesupport", ">= 4"
  gem.add_runtime_dependency "memcached", "~> 1.8.0"

  gem.add_development_dependency "rake"
end
