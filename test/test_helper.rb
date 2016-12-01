require 'minitest/autorun'
require 'mocha/setup'
require 'timecop'

require 'active_support'

ActiveSupport.test_order = :random if ActiveSupport.respond_to?(:test_order)

require 'active_support/test_case'

require 'memcached_store'

class Rails
  def self.logger
    @logger ||= Logger.new("/dev/null")
  end

  def self.env
    Struct.new("Env") do
      def self.test?
        true
      end
    end
  end
end
