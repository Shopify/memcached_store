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

gem 'minitest', '~> 4.0' if version == "3.2.17"
gem "activesupport", as_version
gem 'memcached', "~> 1.7.2", github: 'fbogsany/memcached', branch: 'multi_cas'
