module RailsCacheAdapters
  class MemcachedSafety < Memcached::Rails

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

    NONFATAL_EXCEPTIONS = Memcached::EXCEPTIONS - FATAL_EXCEPTIONS

    if ::Rails.env.test?
      NONFATAL_EXCEPTIONS = []
    end

    SIZE_LIMIT = 2 * 1024 * 1024

    def exist_with_rescue?(*args)
      exist_without_rescue?(*args)
    rescue *NONFATAL_EXCEPTIONS
    end
    alias_method :exist_without_rescue?, :exist?
    alias_method :exist?, :exist_with_rescue?

    def cas_with_rescue(*args)
      cas_without_rescue(*args)
    rescue *NONFATAL_EXCEPTIONS
      false
    end
    alias_method_chain :cas, :rescue

    def get_multi_with_rescue(*args)
      get_multi_without_rescue(*args)
    rescue *NONFATAL_EXCEPTIONS
      {}
    end
    alias_method_chain :get_multi, :rescue

    def set_with_rescue(*args)
      set_without_rescue(*args)
    rescue *NONFATAL_EXCEPTIONS
      false
    end
    alias_method_chain :set, :rescue

    def add_with_rescue(*args)
      add_without_rescue(*args)
    rescue *NONFATAL_EXCEPTIONS
      @string_return_types? "NOT STORED\r\n" : true
    end
    alias_method_chain :add, :rescue

    %w{get delete incr decr append prepend}.each do |meth|
      class_eval <<-ENV
        def #{meth}_with_rescue(*args)
          #{meth}_without_rescue(*args)
        rescue *NONFATAL_EXCEPTIONS
        end
        alias_method_chain :#{meth}, :rescue
      ENV
    end
  end
end
