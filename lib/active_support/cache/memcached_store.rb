# file havily based out off https://github.com/rails/rails/blob/3-2-stable/activesupport/lib/active_support/cache/mem_cache_store.rb
require 'digest/md5'

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

      attr_accessor :read_only, :swallow_exceptions

      def initialize(*addresses)
        addresses = addresses.flatten
        options = addresses.extract_options!
        @swallow_exceptions = true
        @swallow_exceptions = options.delete(:swallow_exceptions) if options.key?(:swallow_exceptions)

        super(options)

        if addresses.first.respond_to?(:get)
          @data = addresses.first
        else
          mem_cache_options = options.dup
          servers = mem_cache_options.delete(:servers)
          UNIVERSAL_OPTIONS.each { |name| mem_cache_options.delete(name) }
          @data = Memcached.new([*addresses, *servers], mem_cache_options)
        end

        extend Strategy::LocalCache
      end

      def logger
        return @logger if defined?(@logger)
        @logger = ::Rails.logger if defined?(::Rails)
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
          instrument(:read_multi, names, options) do
            if raw_values = @data.get(keys_to_names.keys, false)
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

        handle_exceptions(return_value_on_error: false) do
          instrument(:cas, name, options) do
            @data.cas(key, expiration(options), !cas_raw?(options)) do |raw_value|
              entry = deserialize_entry(raw_value)
              value = yield entry.value
              break true if read_only
              serialize_entry(Entry.new(value, options), options).first
            end
          end
          true
        end
      end

      def cas_multi(*names)
        options = names.extract_options!
        return if names.empty?

        options = merged_options(options)
        keys_to_names = Hash[names.map { |name| [normalize_key(name, options), name] }]

        handle_exceptions(return_value_on_error: false) do
          instrument(:cas_multi, names, options) do
            @data.cas(keys_to_names.keys, expiration(options), !cas_raw?(options)) do |raw_values|
              values = {}

              raw_values.each do |key, raw_value|
                entry = deserialize_entry(raw_value)
                values[keys_to_names[key]] = entry.value unless entry.expired?
              end

              values = yield values

              break true if read_only

              serialized_values = values.map do |name, value|
                [normalize_key(name, options), serialize_entry(Entry.new(value, options), options).first]
              end

              Hash[serialized_values]
            end
            true
          end
        end
      end

      def increment(name, amount = 1, options = nil) # :nodoc:
        options = merged_options(options)
        handle_exceptions(return_value_on_error: nil) do
          instrument(:increment, name, amount: amount) do
            @data.incr(normalize_key(name, options), amount)
          end
        end
      end

      def decrement(name, amount = 1, options = nil) # :nodoc:
        options = merged_options(options)
        handle_exceptions(return_value_on_error: nil) do
          instrument(:decrement, name, amount: amount) do
            @data.decr(normalize_key(name, options), amount)
          end
        end
      end

      def clear(options = nil)
        ActiveSupport::Notifications.instrument("cache_clear.active_support", options || {}) do
          @data.flush
        end
      end

      def stats
        ActiveSupport::Notifications.instrument("cache_stats.active_support") do
          @data.stats
        end
      end

      def exist?(*)
        !!super
      end

      def reset #:nodoc:
        handle_exceptions(return_value_on_error: false) do
          @data.reset
        end
      end

      protected

      def read_entry(key, _options) # :nodoc:
        handle_exceptions(return_value_on_error: nil) do
          deserialize_entry(@data.get(escape_key(key), false))
        end
      end

      def write_entry(key, entry, options) # :nodoc:
        return true if read_only
        method = options && options[:unless_exist] ? :add : :set
        expires_in = expiration(options)
        value, raw = serialize_entry(entry, options)
        handle_exceptions(return_value_on_error: false) do
          @data.send(method, escape_key(key), value, expires_in, !raw)
          true
        end
      end

      def delete_entry(key, _options) # :nodoc:
        return true if read_only
        handle_exceptions(return_value_on_error: false, on_miss: true) do
          @data.delete(escape_key(key))
          true
        end
      end

      private

      if ActiveSupport::VERSION::MAJOR < 5
        def normalize_key(key, options)
          escape_key(namespaced_key(key, options))
        end

        def escape_key(key)
          key = key.to_s.dup
          key = key.force_encoding(Encoding::ASCII_8BIT)
          key = key.gsub(ESCAPE_KEY_CHARS) { |match| "%#{match.getbyte(0).to_s(16).upcase}" }
          key = "#{key[0, 213]}:md5:#{Digest::MD5.hexdigest(key)}" if key.size > 250
          key
        end
      else
        def normalize_key(key, options)
          key = super.dup
          key = key.force_encoding(Encoding::ASCII_8BIT)
          key = key.gsub(ESCAPE_KEY_CHARS) { |match| "%#{match.getbyte(0).to_s(16).upcase}" }
          key = "#{key[0, 213]}:md5:#{Digest::MD5.hexdigest(key)}" if key.size > 250
          key
        end

        def escape_key(key)
          key
        end
      end

      def deserialize_entry(raw_value)
        if raw_value
          entry = begin
                      Marshal.load(raw_value)
                    rescue
                      raw_value
                    end
          entry.is_a?(Entry) ? entry : Entry.new(entry)
        end
      end

      def serialize_entry(entry, options)
        entry = entry.value.to_s if options[:raw]
        [entry, options[:raw]]
      end

      def cas_raw?(options)
        options[:raw]
      end

      def expiration(options)
        expires_in = options[:expires_in].to_i
        if expires_in > 0 && !options[:raw]
          # Set the memcache expire a few minutes in the future to support race condition ttls on read
          expires_in += 5.minutes.to_i
        end
        expires_in
      end

      def handle_exceptions(return_value_on_error:, on_miss: return_value_on_error)
        yield
      rescue Memcached::NotFound, Memcached::ConnectionDataExists
        on_miss
      rescue Memcached::Error => e
        raise unless @swallow_exceptions
        logger.warn("memcached error: #{e.class}: #{e.message}") if logger
        return_value_on_error
      end
    end
  end
end
