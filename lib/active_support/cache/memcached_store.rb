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

      def self.build_memcached(*addresses)
        Memcached::Rails.new(*addresses)
      end

      def initialize(*addresses)
        addresses = addresses.flatten
        options = addresses.extract_options!
        super(options)

        if addresses.first.respond_to?(:get)
          @data = addresses.first
        else
          mem_cache_options = options.dup
          UNIVERSAL_OPTIONS.each{|name| mem_cache_options.delete(name)}
          @data = self.class.build_memcached(*(addresses + [mem_cache_options]))
        end

        extend Strategy::LocalCache
      end

      def read_multi(*names)
        options = names.extract_options!
        options = merged_options(options)
        keys_to_names = Hash[names.map{|name| [escape_key(namespaced_key(name, options)), name]}]
        raw_values = @data.get_multi(keys_to_names.keys, :raw => true)
        values = {}
        raw_values.each do |key, value|
          entry = deserialize_entry(value)
          values[keys_to_names[key]] = entry.value unless entry.expired?
        end
        values
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
        @data.flush_all
      end

      def stats
        @data.stats
      end

      def exist?(*args)
        !!super
      end

      protected
        def read_entry(key, options) # :nodoc:
          deserialize_entry(@data.get(escape_key(key), true))
        rescue *NONFATAL_EXCEPTIONS => e
          @data.log_exception(e)
          nil
        end

        def write_entry(key, entry, options) # :nodoc:
          method = options && options[:unless_exist] ? :add : :set
          value = options[:raw] ? entry.value.to_s : entry
          expires_in = options[:expires_in].to_i
          if expires_in > 0 && !options[:raw]
            # Set the memcache expire a few minutes in the future to support race condition ttls on read
            expires_in += 5.minutes
          end
          @data.send(method, escape_key(key), value, expires_in, options[:raw])
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

        def deserialize_entry(raw_value)
          if raw_value
            entry = Marshal.load(raw_value) rescue raw_value
            entry.is_a?(Entry) ? entry : Entry.new(entry)
          else
            nil
          end
        end

    end
  end
end
