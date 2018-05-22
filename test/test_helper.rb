require 'minitest/autorun'
require 'mocha/setup'
require 'timecop'

require 'active_support'

ActiveSupport.test_order = :random if ActiveSupport.respond_to?(:test_order)

require 'active_support/test_case'

require_relative 'support/rails'

require 'memcached_store'
