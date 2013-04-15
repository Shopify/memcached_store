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

        value = options[:raw] ? entry.value.to_s : entry
        expires_in = options[:expires_in].to_i
        if expires_in > 0 && !options[:raw]
          # Set the memcache expire a few minutes in the future to support race condition ttls on read
          expires_in += 5.minutes
        end

        serialized_value = Marshal.dump(value)
        serialized_compressed_value = Snappy.deflate(serialized_value)

        response = @data.set(escape_key(key), serialized_compressed_value, expires_in, true)
        response == Response::STORED
      rescue MemCache::MemCacheError => e
        logger.error("MemCacheError (#{e}): #{e.message}") if logger
        false
      end


      def deserialize_entry_with_snappy(*args)
        compressed_value = args.first
        decompressed_value = compressed_value.nil? ? compressed_value : Snappy.inflate(compressed_value)
        args[0] = decompressed_value
        deserialize_entry_without_snappy(*args)
      end

      alias_method_chain :deserialize_entry, :snappy
    end
  end
end
