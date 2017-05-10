# ActiveSupport MemcachedStore

This gem includes two memcached stores.

### MemcachedStore

ActiveSupport memcached store. This wraps the memcached gem into a ActiveSupport::Cache::Store, so it could be used inside Rails.

### MemcachedSnappyStore

ActiveSupport cache store that adds snappy compression at the cost of making the `incr, decr` operations unavailable.

## Installation

Add this line to your application's Gemfile:

```
gem 'memcached_store'
```

And then execute:

```bash
$ bundle
```

Or install it yourself as:

```bash
$ gem install memcached_store
```

## Usage

In your environment file:

```ruby
# for memcached store
config.cache_store = :memcached_store,

# for snappy store
config.cache_store = :memcached_snappy_store,
  Memcached.new(['memcached1.foo.com', 'memcached2.foo.com'])
```

## Benchmarks

For benchmarks please refer to https://github.com/basecamp/memcached_bench.

## Code status

[![Build Status](https://travis-ci.org/Shopify/memcached_store.svg?branch=master)](https://travis-ci.org/Shopify/memcached_store)

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
