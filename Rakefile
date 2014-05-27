require 'bundler/gem_tasks'
require 'rake/testtask'

task :default => :test

desc 'run test suite with default parser'
Rake::TestTask.new do |t|
  t.libs << "test"
  t.libs << "lib/**/*"
  t.test_files = FileList['test/test*.rb']
  t.verbose = true
end
