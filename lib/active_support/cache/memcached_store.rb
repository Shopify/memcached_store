# file havily based out off https://github.com/rails/rails/blob/3-2-stable/activesupport/lib/active_support/cache/mem_cache_store.rb
require 'digest/md5'
require 'delegate'

module ActiveSupport
  module Cache
    # A cache store implementation which stores data in Memcached:
    # http://memcached.org/
    #
    # MemcachedStore uses memcached gem as backend to connect to Memcached server.
    #
    # MemcachedStore implements the Strategy::LocalCache strategy which implements
    # an in-memory cache inside of a block.
    class MemcachedStore < Store
      ESCAPE_KEY_CHARS = /[\x00-\x20%\x7F-\xFF]/n

      class Codec
        # use dalli compatible flags
        SERIALIZED_FLAG = 0x1
        COMPRESSED_FLAG = 0x2

        # Older versions of this gem would use 0 for the flags whether or not
        # the value was marshal dumped. By setting this flag, we can tell if
        # it were set with an older version for backwards compatible decoding.
        RAW_FLAG = 0x10

        def initialize(serializer: Marshal, compressor: nil)
          @serializer = serializer
          @compressor = compressor
        end

        def encode(_key, value, flags)
          unless value.is_a?(String)
            flags |= SERIALIZED_FLAG
            value = @serializer.dump(value)
          end
          if @compressor
            flags |= COMPRESSED_FLAG
            value = @compressor.compress(value)
          end
          flags |= RAW_FLAG if flags == 0
          [value, flags]
        end

        def decode(_key, value, flags)
          if (flags & COMPRESSED_FLAG) != 0
            value = @compressor.decompress(value)
          end

          if (flags & SERIALIZED_FLAG) != 0
            @serializer.load(value)
          elsif flags == 0 # legacy cache value
            @serializer.load(value) rescue value
          else
            value
          end
        end
      end

      attr_accessor :read_only, :swallow_exceptions

      prepend(Strategy::LocalCache)

      def initialize(*addresses, **options)
        addresses = addresses.flatten
        options[:codec] ||= Codec.new
        @swallow_exceptions = true
        @swallow_exceptions = options.delete(:swallow_exceptions) if options.key?(:swallow_exceptions)

        if options.key?(:coder)
          raise ArgumentError, "ActiveSupport::Cache::MemcachedStore doesn't support custom coders"
        end

        # We don't use a coder, so we set it to nil so Active Support don't think we're using
        # a deprecated one.
        super(options.merge(coder: nil))

        if addresses.first.is_a?(Memcached)
          @connection = addresses.first
          raise "Memcached::Rails is no longer supported, "\
                "use a Memcached instance instead" if @connection.is_a?(Memcached::Rails)
        else
          mem_cache_options = options.dup
          servers = mem_cache_options.delete(:servers)
          UNIVERSAL_OPTIONS.each { |name| mem_cache_options.delete(name) }
          @connection = Memcached.new([*addresses, *servers], mem_cache_options)
        end
      end

      def append(name, value, options = nil)

        return true if read_only
        options = merged_options(options)
        normalized_key = normalize_key(name, options)

        handle_exceptions(return_value_on_error: nil, on_miss: false, miss_exceptions: [Memcached::NotStored]) do
          instrument(:append, normalized_key) do
            @connection.append(normalized_key, value)
          end
          true
        end
      end

      def write(*)
        return true if read_only
        super
      end

      def delete(*)
        return true if read_only
        super
      end

      def read_multi(*names)
        options = names.extract_options!
        return {} if names.empty?

        options = merged_options(options)
        keys_to_names = Hash[names.map { |name| [normalize_key(name, options), name] }]
        values = {}

        handle_exceptions(return_value_on_error: {}) do
          instrument(:read_multi, keys_to_names, options) do
            if raw_values = @connection.get(keys_to_names.keys)
              raw_values.each do |key, value|
                entry = deserialize_entry(value)
                values[keys_to_names[key]] = entry.value unless entry.expired?
              end
            end
          end
          values
        end
      end

      def cas(name, options = nil)
        options = merged_options(options)
        key = normalize_key(name, options)
        payload = nil

        success = handle_exceptions(return_value_on_error: false) do
          instrument(:cas, key, options) do
            @connection.cas(key, expiration(options)) do |raw_value|
              entry = deserialize_entry(raw_value)
              value = yield entry.value
              break true if read_only
              payload = serialize_entry(Entry.new(value, **options), options)
            end
          end
          true
        end

        if success
          local_cache.write_entry(key, payload) if local_cache
        else
          local_cache.delete_entry(key) if local_cache
        end

        success
      end

      def cas_multi(*names, **options)
        return if names.empty?

        options = merged_options(options)
        keys_to_names = Hash[names.map { |name| [normalize_key(name, options), name] }]

        sent_payloads = nil

        handle_exceptions(return_value_on_error: false) do
          instrument(:cas_multi, keys_to_names, options) do
            written_payloads = @connection.cas(keys_to_names.keys, expiration(options)) do |raw_values|
              values = {}

              raw_values.each do |key, raw_value|
                entry = deserialize_entry(raw_value)
                values[keys_to_names[key]] = entry.value unless entry.expired?
              end

              values = yield values

              break true if read_only

              serialized_values = values.map do |name, value|
                [normalize_key(name, options), serialize_entry(Entry.new(value, **options), options)]
              end

              sent_payloads = Hash[serialized_values]
            end

            if local_cache && sent_payloads
              sent_payloads.each_key do |key|
                if written_payloads.key?(key)
                  local_cache.write_entry(key, written_payloads[key])
                else
                  local_cache.delete_entry(key)
                end
              end
            end

            true
          end
        end
      end

      def increment(name, amount = 1, options = nil) # :nodoc:
        options = merged_options(options)
        key = normalize_key(name, options)
        handle_exceptions(return_value_on_error: nil) do
          instrument(:increment, key, amount: amount) do
            @connection.incr(key, amount)
          end
        end
      end

      def decrement(name, amount = 1, options = nil) # :nodoc:
        options = merged_options(options)
        key = normalize_key(name, options)
        handle_exceptions(return_value_on_error: nil) do
          instrument(:decrement, key, amount: amount) do
            @connection.decr(key, amount)
          end
        end
      end

      def clear(options = nil)
        ActiveSupport::Notifications.instrument("cache_clear.active_support", options || {}) do
          @connection.flush
        end
      end

      def stats
        ActiveSupport::Notifications.instrument("cache_stats.active_support") do
          @connection.stats
        end
      end

      def exist?(*)
        !!super
      end

      def reset #:nodoc:
        handle_exceptions(return_value_on_error: false) do
          @connection.reset
        end
      end

      private

      if private_method_defined?(:read_serialized_entry)
        class DupLocalStore < DelegateClass(Strategy::LocalCache::LocalStore)
          def write_entry(_key, entry)
            if entry.is_a?(Entry)
              entry.dup_value!
            end
            super
          end

          def fetch_entry(key)
            entry = super do
              new_entry = yield
              if entry.is_a?(Entry)
                new_entry.dup_value!
              end
              new_entry
            end
            entry = entry.dup

            if entry.is_a?(Entry)
              entry.dup_value!
            end

            entry
          end
        end

        module DupLocalCache
          private

          def local_cache
            if local_cache = super
              DupLocalStore.new(local_cache)
            end
          end
        end

        prepend DupLocalCache

        def read_entry(key, **options) # :nodoc:
          deserialize_entry(read_serialized_entry(key, **options))
        end

        def read_serialized_entry(key, **)
          handle_exceptions(return_value_on_error: nil) do
            @connection.get(key)
          end
        end

        def write_entry(key, entry, **options) # :nodoc:
          return true if read_only

          write_serialized_entry(key, serialize_entry(entry, **options), **options)
        end

        def write_serialized_entry(key, value, **options)
          method = options && options[:unless_exist] ? :add : :set
          expires_in = expiration(options)
          handle_exceptions(return_value_on_error: false) do
            @connection.send(method, key, value, expires_in)
            true
          end
        end
      else
        def read_entry(key, _options) # :nodoc:
          handle_exceptions(return_value_on_error: nil) do
            deserialize_entry(@connection.get(key))
          end
        end

        def write_entry(key, entry, options) # :nodoc:
          return true if read_only
          method = options && options[:unless_exist] ? :add : :set
          expires_in = expiration(options)
          value = serialize_entry(entry, options)
          handle_exceptions(return_value_on_error: false) do
            @connection.send(method, key, value, expires_in)
            true
          end
        end
      end

      def delete_entry(key, _options = nil) # :nodoc:
        return true if read_only
        handle_exceptions(return_value_on_error: false, on_miss: true) do
          @connection.delete(key)
          true
        end
      end

      private

      def normalize_key(key, options)
        key = super.dup
        key = key.force_encoding(Encoding::ASCII_8BIT)
        key = key.gsub(ESCAPE_KEY_CHARS) { |match| "%#{match.getbyte(0).to_s(16).upcase}" }
        key = "#{key[0, 213]}:md5:#{ActiveSupport::Digest.hash(key)}" if key.size > 250
        key
      end

      def deserialize_entry(value)
        unless value.nil?
          value.is_a?(Entry) ? value : Entry.new(value, compress: false)
        end
      end

      def serialize_entry(entry, options = nil)
        if options && options[:raw]
          entry.value.to_s
        else
          entry
        end
      end

      def expiration(options)
        expires_in = options[:expires_in].to_i
        if expires_in > 0 && options[:race_condition_ttl] && !options[:raw]
          expires_in += options[:race_condition_ttl].to_i
        end
        expires_in
      end

      def handle_exceptions(return_value_on_error:, on_miss: return_value_on_error, miss_exceptions: [])
        yield
      rescue Memcached::NotFound, Memcached::ConnectionDataExists, *miss_exceptions
        on_miss
      rescue Memcached::Error => e
        log_warning(e)
        raise unless @swallow_exceptions
        return_value_on_error
      end

      def log_warning(err)
        return unless logger
        return if err.is_a?(Memcached::NotStored) && @swallow_exceptions

        logger.warn(
          "[MEMCACHED_ERROR] swallowed=#{@swallow_exceptions}" \
          " exception_class=#{err.class} exception_message=#{err.message}"
        )
      end

      ActiveSupport.run_load_hooks(:memcached_store)
    end
  end
end
