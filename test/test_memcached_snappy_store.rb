require 'test_helper'

class TestMemcachedSnappyStore < ActiveSupport::TestCase

  setup do
     @cache = ActiveSupport::Cache.lookup_store(:memcached_snappy_store)
     @cache.clear
  end

  test "test should not allow increment" do
    assert_raise(ActiveSupport::Cache::MemcachedSnappyStore::UnsupportedOperation) do
      @cache.increment('foo')
    end
  end

  test "should not allow decrement" do
    assert_raise(ActiveSupport::Cache::MemcachedSnappyStore::UnsupportedOperation) do
      @cache.decrement('foo')
    end
  end

  test "write should not allow  the implicit add operation when unless_exist is passed to write" do
    assert_raise(ActiveSupport::Cache::MemcachedSnappyStore::UnsupportedOperation) do
      @cache.write('foo', 'bar', :unless_exist => true)
    end
  end

  test "should use snappy to write cache entries" do
    # Freezing time so created_at is the same in entry and the entry created
    # internally and assert_equal between the raw data in the cache and the
    # compressed explicitly makes sense
    Timecop.freeze do
      entry_value = { :omg => 'data' }
      entry = ActiveSupport::Cache::Entry.new(entry_value)
      key = 'moarponies'
      assert @cache.write(key, entry_value)

      serialized_entry = Marshal.dump(entry)
      serialized_compressed_entry = Snappy.deflate(serialized_entry)
      actual_cache_value = @cache.instance_variable_get(:@data).get(key, true)

      assert_equal serialized_compressed_entry, actual_cache_value
    end
  end

  test "should use snappy to read cache entries" do
    entry_value = { :omg => 'data' }
    key = 'ponies'

    @cache.write(key, entry_value)
    cache_entry = ActiveSupport::Cache::Entry.new(entry_value)
    serialized_cached_entry =  Marshal.dump(cache_entry)

    Snappy.expects(:inflate).returns(serialized_cached_entry)
    assert_equal entry_value, @cache.read(key)
  end

  test "should skip snappy to reading not found" do
    key = 'ponies2'
    Snappy.expects(:inflate).never
    assert_nil @cache.read(key)
  end

  test "should use snappy to multi read cache entries but not on missing entries" do
    keys = %w{ one tow three }
    values = keys.map{ |k| k * 10 }
    entries = values.map{ |v| ActiveSupport::Cache::Entry.new(v) }

    keys.each_with_index{ |k, i| @cache.write(k, values[i]) }

    keys_and_missing = keys << 'missing'

    Snappy.expects(:inflate).times(3).returns(*entries)
    assert_equal values, @cache.read_multi(*keys_and_missing).values
  end

  test "should use snappy to multi read cache entries" do
    keys = %w{ one tow three }
    values = keys.map{ |k| k * 10 }
    entries = values.map{ |v| ActiveSupport::Cache::Entry.new(v) }

    keys.each_with_index{ |k, i| @cache.write(k, values[i]) }

    Snappy.expects(:inflate).times(3).returns(*entries)
    assert_equal values, @cache.read_multi(*keys).values
  end

  test "should support raw writes that don't use marshal format" do
    key = 'key'
    @cache.write(key, 'value', :raw => true)

    actual_cache_value = @cache.instance_variable_get(:@data).get(key, true)
    assert_equal 'value', Snappy.inflate(actual_cache_value)
  end
end
