module MemcachedStore
  class Railtie < Rails::Railtie
    initializer 'memcached_store.configuration' do
      ActiveSupport.on_load(:memcached_store) do
        ActiveSupport::Cache::MemcachedStore.logger ||= Rails.logger
      end
    end
  end
end
