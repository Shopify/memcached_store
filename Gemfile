source 'https://rubygems.org'

# Specify your gem's dependencies in rails_cache_adapters.gemspec
gemspec

version = ENV["AS_VERSION"] || "3.2.16"
as_version = case version
when "master"
  {:github => "rails/rails"}
else
  "~> #{version}"
end

gem 'minitest', '~> 4.0'
gem "activesupport", as_version
