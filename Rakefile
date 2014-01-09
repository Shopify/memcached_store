#!/usr/bin/env rake
require 'rake'
require 'rake/testtask'
$LOAD_PATH.unshift File.expand_path("../lib", __FILE__)
require "memcached_store/version"

task :default => 'test'

desc 'run test suite with default parser'
Rake::TestTask.new do |t|
  t.libs << "test"
  t.libs << "lib/**/*"
  t.test_files = FileList['test/test*.rb']
  t.verbose = true
end

task :gem => :build
task :build do
  system "gem build memcached_store.gemspec"
end

task :install => :build do
  system "gem install memcached_store-#{MemcachedStore::VERSION}.gem"
end

task :release => :build do
  system "git commit -m'Released version #{MemcachedStore::VERSION}' --allow-empty"
  system "git tag -a v#{MemcachedStore::VERSION} -m 'Tagging #{MemcachedStore::VERSION}'"
  system "git push --tags"
  system "gem push memcached_store-#{MemcachedStore::VERSION}.gem"
  system "rm memcached_store-#{MemcachedStore::VERSION}.gem"
end
