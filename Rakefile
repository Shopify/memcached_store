require 'bundler/gem_tasks'
require 'rake/testtask'

$LOAD_PATH.unshift File.expand_path("../lib", __FILE__)
require "memcached_store/version"

task default: :test

desc 'run test suite with default parser'
Rake::TestTask.new do |t|
  t.libs << "test"
  t.libs << "lib/**/*"
  t.test_files = FileList['test/test*.rb']
  t.verbose = true
end

task tag: :build do
  system "git commit -m'Released version #{MemcachedStore::VERSION}' --allow-empty"
  system "git tag -a v#{MemcachedStore::VERSION} -m 'Tagging #{MemcachedStore::VERSION}'"
  system "git push --tags"
end
