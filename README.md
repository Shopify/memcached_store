# MemcachedSnappyStore

ActiveSupport cache store that adds snappy compression at the cost of making the ```incr, decr, add``` operations unavailable. 

## Installation

Add this line to your application's Gemfile:

    gem 'memcached_snappy_store'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install memcached_snappy_store

## Usage

In your environment file:

```ruby

  config.cache_store = :memcached_snappy_store,  
    Memcached::Rails.new(:servers => ['memcached1.foo.com', 'memcached2.foo.com']) 

```

## Code status

[![Build Status](https://travis-ci.org/Shopify/rails_cache_adapters.png)](https://travis-ci.org/Shopify/rails_cache_adapters)

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
