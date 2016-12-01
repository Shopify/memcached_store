source 'https://rubygems.org'

# Specify your gem's dependencies in rails_cache_adapters.gemspec
gemspec

version = ENV["AS_VERSION"] || "5.0.0"
as_version = case version
when "master"
  { github: "rails/rails" }
else
  "~> #{version}"
end

gem "activesupport", as_version

group :test do
  gem "mocha"
  gem "timecop"
  gem "snappy"
end
