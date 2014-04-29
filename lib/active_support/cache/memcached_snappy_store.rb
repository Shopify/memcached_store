begin
  require 'snappy'
rescue LoadError => e
  $stderr.puts "You don't have snappy installed in your application. Please add `gem \"snappy\"` to your Gemfile and run bundle install"
  raise e
end

require 'active_support/cache/memcached_store'

module ActiveSupport
  module Cache
    class MemcachedSnappyStore < MemcachedStore
      class UnsupportedOperation < StandardError; end

      def increment(*args)
        raise UnsupportedOperation.new("increment is not supported by: #{self.class.name}")
      end

      def decrement(*args)
        raise UnsupportedOperation.new("decrement is not supported by: #{self.class.name}")
      end

      private
      def serialize_entry(entry, options)
        value = options[:raw] ? entry.value.to_s : Marshal.dump(entry)
        options[:raw] = true
        Snappy.deflate(value)
      end

      def deserialize_entry(compressed_value)
        if compressed_value
          super(Snappy.inflate(compressed_value))
        else
          nil
        end
      end
    end
  end
end
