# file havily based out off https://github.com/rails/rails/blob/3-2-stable/activesupport/lib/active_support/cache/mem_cache_store.rb
require 'digest/md5'
require 'msgpack'

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
      FATAL_EXCEPTIONS = [ Memcached::ABadKeyWasProvidedOrCharactersOutOfRange,
        Memcached::AKeyLengthOfZeroWasProvided,
        Memcached::ConnectionBindFailure,
        Memcached::ConnectionDataDoesNotExist,
        Memcached::ConnectionFailure,
        Memcached::ConnectionSocketCreateFailure,
        Memcached::CouldNotOpenUnixSocket,
        Memcached::NoServersDefined,
        Memcached::TheHostTransportProtocolDoesNotMatchThatOfTheClient
      ]

      if defined?(::Rails) && ::Rails.env.test?
        NONFATAL_EXCEPTIONS = []
      else
        NONFATAL_EXCEPTIONS = Memcached::EXCEPTIONS - FATAL_EXCEPTIONS
      end

      ESCAPE_KEY_CHARS = /[\x00-\x20%\x7F-\xFF]/n

      def initialize(*addresses)
        addresses = addresses.flatten
        options = addresses.extract_options!
        super(options)

        if addresses.first.respond_to?(:get)
          @data = addresses.first
        else
          mem_cache_options = options.dup
          UNIVERSAL_OPTIONS.each{|name| mem_cache_options.delete(name)}
          mem_cache_options.delete(:use_msgpack)
          @data = Memcached::Rails.new(*(addresses + [mem_cache_options]))
        end

        extend Strategy::LocalCache
      end

      def read_multi(*names)
        options = names.extract_options!
        options = merged_options(options)
        keys_to_names = Hash[names.map{|name| [escape_key(namespaced_key(name, options)), name]}]
        values = {}

        instrument(:read_multi, names, options) do
          if raw_values = @data.get_multi(keys_to_names.keys, :raw => true)
            raw_values.each do |key, value|
              entry = deserialize_entry(value, options)
              values[keys_to_names[key]] = entry.value unless entry.expired?
            end
          end
        end
        values
      rescue *NONFATAL_EXCEPTIONS => e
        @data.log_exception(e)
        {}
      end

      def cas(name, options = nil)
        options = merged_options(options)
        key = namespaced_key(name, options)

        instrument(:cas, name, options) do
          @data.cas(key, expiration(options), cas_raw?(options)) do |raw_value|
            entry = deserialize_entry(raw_value, options)
            value = yield entry.value
            serialize_entry(Entry.new(value, options), options).first
          end
        end
      rescue *NONFATAL_EXCEPTIONS => e
        @data.log_exception(e)
        false
      end

      def cas_multi(*names)
        options = names.extract_options!
        options = merged_options(options)
        keys_to_names = Hash[names.map{|name| [escape_key(namespaced_key(name, options)), name]}]

        instrument(:cas_multi, names, options) do
          @data.cas(keys_to_names.keys, expiration(options), cas_raw?(options)) do |raw_values|
            values = {}
            raw_values.each do |key, raw_value|
              entry = deserialize_entry(raw_value, options)
              values[keys_to_names[key]] = entry.value unless entry.expired?
            end
            values = yield values
            Hash[values.map{|name, value| [escape_key(namespaced_key(name, options)), serialize_entry(Entry.new(value, options), options).first]}]
          end
        end
      rescue *NONFATAL_EXCEPTIONS => e
        @data.log_exception(e)
        false
      end

      def increment(name, amount = 1, options = nil) # :nodoc:
        options = merged_options(options)
        instrument(:increment, name, :amount => amount) do
          @data.incr(escape_key(namespaced_key(name, options)), amount)
        end
      rescue *NONFATAL_EXCEPTIONS => e
        @data.log_exception(e)
        nil
      end

      def decrement(name, amount = 1, options = nil) # :nodoc:
        options = merged_options(options)
        instrument(:decrement, name, :amount => amount) do
          @data.decr(escape_key(namespaced_key(name, options)), amount)
        end
      rescue *NONFATAL_EXCEPTIONS => e
        @data.log_exception(e)
        nil
      end

      def clear(options = nil)
        instrument(:clear, options) { @data.flush_all }
      end

      def stats
        instrument(:stats) { @data.stats }
      end

      def exist?(*args)
        !!super
      end

      def reset #:nodoc:
        @data.reset
      rescue *NONFATAL_EXCEPTIONS => e
        @data.log_exception(e)
        false
      end

      protected
        def read_entry(key, options) # :nodoc:
          deserialize_entry(@data.get(escape_key(key), true), options)
        rescue *NONFATAL_EXCEPTIONS => e
          @data.log_exception(e)
          nil
        end

        def write_entry(key, entry, options) # :nodoc:
          method = options && options[:unless_exist] ? :add : :set
          expires_in = expiration(options)
          value, raw = serialize_entry(entry, options)
          @data.send(method, escape_key(key), value, expires_in, raw)
        rescue *NONFATAL_EXCEPTIONS => e
          @data.log_exception(e)
          false
        end

        def delete_entry(key, options) # :nodoc:
          @data.delete(escape_key(key))
          true
        rescue *NONFATAL_EXCEPTIONS => e
          @data.log_exception(e)
          false
        end

      private

        def escape_key(key)
          key = key.to_s.dup
          key = key.force_encoding(Encoding::ASCII_8BIT)
          key = key.gsub(ESCAPE_KEY_CHARS){ |match| "%#{match.getbyte(0).to_s(16).upcase}" }
          key = "#{key[0, 213]}:md5:#{Digest::MD5.hexdigest(key)}" if key.size > 250
          key
        end

        def deserialize_entry(raw_value, options)
          if raw_value
            entry = deserialize(raw_value, options) rescue raw_value
            if entry.is_a?(Entry)
              entry
            elsif entry.is_a?(Hash)
              e = Entry.new(entry["value"], expires_in: entry["expires_in"], compress: entry["compress"])
              e.instance_variable_set(:@created_at, entry["created_at"])
              e
            else
              Entry.new(entry)
            end
          else
            nil
          end
        end

        def deserialize(data, options)
          if data.nil? || options[:raw]
            data
          elsif options[:use_msgpack]
            data = MessagePack.unpack(data) if b = data.unpack("C").first and b == 0x83 or b == 0x84
            data
          else
            Marshal.load(data)
          end
        end

        def serialize_entry(entry, options)
          if options[:raw]
            [entry.value.to_s, true]
          elsif options[:use_msgpack]
            [MessagePack.pack(entry), true]
          else
            [entry, false]
          end
        end

        def cas_raw?(options)
          options[:raw] || options[:use_msgpack]
        end

        def expiration(options)
          expires_in = options[:expires_in].to_i
          if expires_in > 0 && !options[:raw]
            # Set the memcache expire a few minutes in the future to support race condition ttls on read
            expires_in += 5.minutes
          end
          expires_in
        end

    end
  end
end
