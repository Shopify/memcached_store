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

      module SnappyCompressor
        def self.compress(source)
          Snappy.deflate(source)
        end

        def self.decompress(source)
          Snappy.inflate(source)
        end
      end

      def increment(*)
        raise UnsupportedOperation, "increment is not supported by: #{self.class.name}"
      end

      def decrement(*)
        raise UnsupportedOperation, "decrement is not supported by: #{self.class.name}"
      end

      # IdentityCache has its own handling for read only.
      def read_only
        false
      end

      def initialize(*addresses, **options)
        options[:codec] ||= ActiveSupport::Cache::MemcachedStore::Codec.new(compressor: SnappyCompressor)
        super(*addresses, **options)
      end
    end
  end
end
