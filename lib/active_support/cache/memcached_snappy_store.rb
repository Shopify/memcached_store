module ActiveSupport
  module Cache
    class MemcachedSnappyStore < Cache::MemCacheStore
      class UnsupportedOperation < StandardError; end

      def increment(*args)
        raise UnsupportedOperation.new("increment is not supported by: #{self.class.name}")
      end

      def decrement(*args)
        raise UnsupportedOperation.new("decrement is not supported by: #{self.class.name}")
      end

      protected

      def write_entry(key, entry, options)
        # normally unless_exist would make this method use add,  add will not make sense on compressed entries
        raise UnsupportedOperation.new("unless_exist would try to use the unsupported add method") if options && options[:unless_exist]

        serialized_value = options[:raw] ? entry.value.to_s : Marshal.dump(entry)
        expires_in = options[:expires_in].to_i
        if expires_in > 0 && !options[:raw]
          # Set the memcache expire a few minutes in the future to support race condition ttls on read
          expires_in += 5.minutes
        end

        serialized_compressed_value = Snappy.deflate(serialized_value)

        response = @data.set(escape_key(key), serialized_compressed_value, expires_in, false)
      end

      def read_entry(key, options)
        deserialize_entry(@data.get(escape_key(key), false))
      end

      def deserialize_entry(compressed_value)
        decompressed_value = compressed_value.nil? ? compressed_value : Snappy.inflate(compressed_value)
        super(decompressed_value)
      rescue Snappy::Error
        nil
      end
    end
  end
end
