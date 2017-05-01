require 'test_helper'

class TestMemcachedSnappyStore < ActiveSupport::TestCase
  setup do
    @cache = ActiveSupport::Cache.lookup_store(:memcached_snappy_store, support_cas: true)
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

  test "write should allow  the implicit add operation when unless_exist is passed to write" do
    assert_nothing_raised do
      @cache.write('foo', 'bar', unless_exist: true)
    end
  end

  test "should use snappy to write cache entries" do
    # Freezing time so created_at is the same in entry and the entry created
    # internally and assert_equal between the raw data in the cache and the
    # compressed explicitly makes sense
    Timecop.freeze do
      entry_value = { omg: 'data' }
      entry = ActiveSupport::Cache::Entry.new(entry_value)
      key = 'moarponies'
      assert @cache.write(key, entry_value)

      serialized_entry = Marshal.dump(entry)
      serialized_compressed_entry = Snappy.deflate(serialized_entry)
      actual_cache_value = @cache.instance_variable_get(:@data).get(key, false)

      assert_equal serialized_compressed_entry, actual_cache_value
    end
  end

  test "should use snappy to read cache entries" do
    entry_value = { omg: 'data' }
    key = 'ponies'

    @cache.write(key, entry_value)
    cache_entry = ActiveSupport::Cache::Entry.new(entry_value)
    serialized_cached_entry = Marshal.dump(cache_entry)

    Snappy.expects(:inflate).returns(serialized_cached_entry)
    assert_equal entry_value, @cache.read(key)
  end

  test "should skip snappy to reading not found" do
    key = 'ponies2'
    Snappy.expects(:inflate).never
    assert_nil @cache.read(key)
  end

  test "get should work when there is a connection fail" do
    key = 'ponies2'
    @cache.instance_variable_get(:@data).expects(:check_return_code).raises(Memcached::ConnectionFailure).at_least_once
    assert_nil @cache.read(key)
  end

  test "should use snappy to multi read cache entries but not on missing entries" do
    keys = %w(one tow three)
    values = keys.map { |k| k * 10 }
    entries = values.map { |v| ActiveSupport::Cache::Entry.new(v) }

    keys.each_with_index { |k, i| @cache.write(k, values[i]) }

    keys_and_missing = keys << 'missing'

    Snappy.expects(:inflate).times(3).returns(*entries)
    assert_equal values, @cache.read_multi(*keys_and_missing).values
  end

  test "should use snappy to multi read cache entries" do
    keys = %w(one tow three)
    values = keys.map { |k| k * 10 }
    entries = values.map { |v| ActiveSupport::Cache::Entry.new(v) }

    keys.each_with_index { |k, i| @cache.write(k, values[i]) }

    Snappy.expects(:inflate).times(3).returns(*entries)
    assert_equal values, @cache.read_multi(*keys).values
  end

  test "should support raw writes that don't use marshal format" do
    key = 'key'
    @cache.write(key, 'value', raw: true)

    actual_cache_value = @cache.instance_variable_get(:@data).get(key, false)
    assert_equal 'value', Snappy.inflate(actual_cache_value)
  end

  test "cas should use snappy to read and write cache entries" do
    entry_value = { omg: 'data' }
    update_value = 'value'
    key = 'ponies'

    @cache.write(key, entry_value)
    result = @cache.cas(key) do |v|
      assert_equal entry_value, v
      update_value
    end
    assert result
    assert_equal update_value, @cache.read(key)

    actual_cache_value = @cache.instance_variable_get(:@data).get(key, false)
    serialized_entry = Snappy.inflate(actual_cache_value)
    entry = Marshal.load(serialized_entry)
    assert entry.is_a?(ActiveSupport::Cache::Entry)
    assert_equal update_value, entry.value
  end

  test "cas should support raw entries that don't use marshal format" do
    key = 'key'
    @cache.write(key, 'value', raw: true)
    result = @cache.cas(key, raw: true) do |v|
      assert_equal 'value', v
      'new_value'
    end
    assert result
    actual_cache_value = @cache.instance_variable_get(:@data).get(key, false)
    assert_equal 'new_value', Snappy.inflate(actual_cache_value)
  end

  test "cas_multi should use snappy to read and write cache entries" do
    keys = %w(one two three four)
    values = keys.map { |k| k * 10 }
    update_hash = Hash[keys.drop(1).map { |k| [k, k * 11] }]

    keys.zip(values) { |k, v| @cache.write(k, v) }

    result = @cache.cas_multi(*keys) do |hash|
      assert_equal Hash[keys.zip(values)], hash
      update_hash
    end
    assert result
    assert_equal Hash[keys.zip(values)].merge(update_hash), @cache.read_multi(*keys)

    update_hash.each do |key, value|
      actual_cache_value = @cache.instance_variable_get(:@data).get(key, false)
      serialized_entry = Snappy.inflate(actual_cache_value)
      entry = Marshal.load(serialized_entry)
      assert entry.is_a?(ActiveSupport::Cache::Entry)
      assert_equal value, entry.value
    end
  end

  test "cas_multi should support raw entries that don't use marshal format" do
    keys = %w(one two three)
    values = keys.map { |k| k * 10 }
    update_hash = { "two" => "two" * 11 }

    keys.zip(values) { |k, v| @cache.write(k, v) }

    result = @cache.cas_multi(*keys, raw: true) do |hash|
      assert_equal Hash[keys.zip(values)], hash
      update_hash
    end
    assert result
    actual_cache_value = @cache.instance_variable_get(:@data).get("two", false)
    assert_equal update_hash["two"], Snappy.inflate(actual_cache_value)
  end
end
