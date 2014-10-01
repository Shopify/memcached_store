require 'test_helper'

class TestMemcachedStore < ActiveSupport::TestCase
  setup do
    @cache = ActiveSupport::Cache.lookup_store(:memcached_store, expires_in: 60, support_cas: true)
    @cache.clear

    # Enable ActiveSupport notifications. Can be disabled in Rails 5.
    Thread.current[:instrument_cache_store] = true
  end

  def test_write_not_found
    expect_not_found
    assert_equal false, @cache.write('not_exist', 1)
  end

  def test_fetch_not_found
    expect_not_found
    assert_equal nil, @cache.fetch('not_exist')
  end

  def test_should_read_and_write_strings
    assert @cache.write('foo', 'bar')
    assert_equal 'bar', @cache.read('foo')
  end

  def test_should_overwrite
    @cache.write('foo', 'bar')
    @cache.write('foo', 'baz')
    assert_equal 'baz', @cache.read('foo')
  end

  def test_fetch_without_cache_miss
    @cache.write('foo', 'bar')
    @cache.expects(:write).never
    assert_equal 'bar', @cache.fetch('foo') { 'baz' }
  end

  def test_fetch_with_cache_miss
    @cache.expects(:write).with('foo', 'baz', @cache.options)
    assert_equal 'baz', @cache.fetch('foo') { 'baz' }
  end

  def test_fetch_with_forced_cache_miss
    @cache.write('foo', 'bar')
    @cache.expects(:read).never
    @cache.expects(:write).with('foo', 'bar', @cache.options.merge(:force => true))
    @cache.fetch('foo', :force => true) { 'bar' }
  end

  def test_fetch_with_cached_nil
    @cache.write('foo', nil)
    @cache.expects(:write).never
    assert_nil @cache.fetch('foo') { 'baz' }
  end

  def test_cas
    @cache.write('foo', nil)
    assert @cache.cas('foo') {|value| assert_nil value; 'bar' }
    assert_equal 'bar', @cache.read('foo')
  end

  def test_cas_with_cache_miss
    refute @cache.cas('not_exist') {|value| flunk }
  end

  def test_cas_with_conflict
    @cache.write('foo', 'bar')
    refute @cache.cas('foo') {|value|
      @cache.write('foo', 'baz')
      'biz'
    }
    assert_equal 'baz', @cache.read('foo')
  end

  def test_cas_multi_with_empty_set
    refute @cache.cas_multi() {|hash| flunk }
  end

  def test_cas_multi
    @cache.write('foo', 'bar')
    @cache.write('fud', 'biz')
    assert @cache.cas_multi('foo', 'fud') {|hash| assert_equal({"foo" => "bar", "fud" => "biz"}, hash); {"foo" => "baz", "fud" => "buz"} }
    assert_equal({"foo" => "baz", "fud" => "buz"}, @cache.read_multi('foo', 'fud'))
  end

  def test_cas_multi_with_altered_key
    @cache.write('foo', 'baz')
    assert @cache.cas_multi('foo') {|hash| {'fu' => 'baz'}}
    assert_nil @cache.read('fu')
    assert_equal 'baz', @cache.read('foo')
  end

  def test_cas_multi_with_cache_miss
    assert @cache.cas_multi('not_exist') {|hash| assert hash.empty?; {} }
  end

  def test_cas_multi_with_partial_miss
    @cache.write('foo', 'baz')
    assert @cache.cas_multi('foo', 'bar') {|hash| assert_equal({"foo" => "baz"}, hash); {} }
    assert_equal 'baz', @cache.read('foo')
  end

  def test_cas_multi_with_partial_update
    @cache.write('foo', 'bar')
    @cache.write('fud', 'biz')
    assert @cache.cas_multi('foo', 'fud') {|hash| assert_equal({"foo" => "bar", "fud" => "biz"}, hash); {"foo" => "baz"} }
    assert_equal({"foo" => "baz", "fud" => "biz"}, @cache.read_multi('foo', 'fud'))
  end

  def test_cas_multi_with_partial_conflict
    @cache.write('foo', 'bar')
    @cache.write('fud', 'biz')
    result = @cache.cas_multi('foo', 'fud') do |hash|
      assert_equal({"foo" => "bar", "fud" => "biz"}, hash)
      @cache.write('foo', 'bad')
      {"foo" => "baz", "fud" => "buz"}
    end
    assert result
    assert_equal({"foo" => "bad", "fud" => "buz"}, @cache.read_multi('foo', 'fud'))
  end

  def test_should_read_and_write_hash
    assert @cache.write('foo', {:a => "b"})
    assert_equal({:a => "b"}, @cache.read('foo'))
  end

  def test_should_read_and_write_integer
    assert @cache.write('foo', 1)
    assert_equal 1, @cache.read('foo')
  end

  def test_should_read_and_write_nil
    assert @cache.write('foo', nil)
    assert_equal nil, @cache.read('foo')
  end

  def test_should_read_and_write_false
    assert @cache.write('foo', false)
    assert_equal false, @cache.read('foo')
  end

  def test_read_multi
    @cache.write('foo', 'bar')
    @cache.write('fu', 'baz')
    @cache.write('fud', 'biz')
    assert_equal({"foo" => "bar", "fu" => "baz"}, @cache.read_multi('foo', 'fu'))
  end

  def test_read_multi_with_expires
    time = Time.now
    @cache.write('foo', 'bar', :expires_in => 10)
    @cache.write('fu', 'baz')
    @cache.write('fud', 'biz')
    Time.stubs(:now).returns(time + 11)
    assert_equal({"fu" => "baz"}, @cache.read_multi('foo', 'fu'))
  end

  def test_read_multi
    @cache.write('foo', 'bar')
    @cache.write('fu', 'baz')
    @cache.write('fud', 'biz')
    assert_equal({"foo" => "bar", "fu" => "baz"}, @cache.read_multi('foo', 'fu'))
  end

  def test_read_multi_not_found
    expect_not_found
    assert_equal({}, @cache.read_multi('foe', 'fue'))
  end

  def test_read_multi_with_expires
    @cache.write('foo', 'bar', :expires_in => 0.001)
    @cache.write('fu', 'baz')
    @cache.write('fud', 'biz')
    sleep(0.002)
    assert_equal({"fu" => "baz"}, @cache.read_multi('foo', 'fu'))
  end

  def test_read_and_write_compressed_small_data
    @cache.write('foo', 'bar', :compress => true)
    assert_equal 'bar', @cache.read('foo')
  end

  def test_read_and_write_compressed_large_data
    @cache.write('foo', 'bar', :compress => true, :compress_threshold => 2)
    assert_equal 'bar', @cache.read('foo')
  end

  def test_read_and_write_compressed_nil
    @cache.write('foo', nil, :compress => true)
    assert_nil @cache.read('foo')
  end

  def test_cache_key
    obj = Object.new
    def obj.cache_key
      :foo
    end
    @cache.write(obj, "bar")
    assert_equal "bar", @cache.read("foo")
  end

  def test_param_as_cache_key
    obj = Object.new
    def obj.to_param
      "foo"
    end
    @cache.write(obj, "bar")
    assert_equal "bar", @cache.read("foo")
  end

  def test_array_as_cache_key
    @cache.write([:fu, "foo"], "bar")
    assert_equal "bar", @cache.read("fu/foo")
  end

  def test_hash_as_cache_key
    @cache.write({:foo => 1, :fu => 2}, "bar")
    assert_equal "bar", @cache.read("foo=1/fu=2")
  end

  def test_keys_are_case_sensitive
    @cache.write("foo", "bar")
    assert_nil @cache.read("FOO")
  end

  def test_exist
    @cache.write('foo', 'bar')
    assert_equal true, @cache.exist?('foo')
    assert_equal false, @cache.exist?('bar')
  end

  def test_nil_exist
    @cache.write('foo', nil)
    assert @cache.exist?('foo')
  end

  def test_delete
    @cache.write('foo', 'bar')
    assert @cache.exist?('foo')
    assert @cache.delete('foo')
    assert !@cache.exist?('foo')

    assert @cache.delete('foo')
  end

  def test_original_store_objects_should_not_be_immutable
    bar = 'bar'
    @cache.write('foo', bar)
    assert_nothing_raised { bar.gsub!(/.*/, 'baz') }
  end

  def test_expires_in
    time = Time.local(2008, 4, 24)
    Time.stubs(:now).returns(time)

    @cache.write('foo', 'bar')
    assert_equal 'bar', @cache.read('foo')

    Time.stubs(:now).returns(time + 30)
    assert_equal 'bar', @cache.read('foo')

    Time.stubs(:now).returns(time + 61)
    assert_nil @cache.read('foo')
  end

  def test_race_condition_protection
    time = Time.now
    @cache.write('foo', 'bar', :expires_in => 60)
    Time.stubs(:now).returns(time + 61)
    result = @cache.fetch('foo', :race_condition_ttl => 10) do
      assert_equal 'bar', @cache.read('foo')
      "baz"
    end
    assert_equal "baz", result
  end

  def test_race_condition_protection_is_limited
    time = Time.now
    @cache.write('foo', 'bar', :expires_in => 60)
    Time.stubs(:now).returns(time + 71)
    result = @cache.fetch('foo', :race_condition_ttl => 10) do
      assert_equal nil, @cache.read('foo')
      "baz"
    end
    assert_equal "baz", result
  end

  def test_race_condition_protection_is_safe
    time = Time.now
    @cache.write('foo', 'bar', :expires_in => 60)
    Time.stubs(:now).returns(time + 61)
    begin
      @cache.fetch('foo', :race_condition_ttl => 10) do
        assert_equal 'bar', @cache.read('foo')
        raise ArgumentError.new
      end
    rescue ArgumentError
    end
    assert_equal "bar", @cache.read('foo')
    Time.stubs(:now).returns(time + 91)
    assert_nil @cache.read('foo')
  end

  def test_crazy_key_characters
    crazy_key = "#/:*(<+=> )&$%@?;'\"\'`~-"
    assert @cache.write(crazy_key, "1", :raw => true)
    assert_equal "1", @cache.read(crazy_key)
    assert_equal "1", @cache.fetch(crazy_key)
    assert @cache.delete(crazy_key)
    assert_equal "2", @cache.fetch(crazy_key, :raw => true) { "2" }
    assert_equal 3, @cache.increment(crazy_key)
    assert_equal 2, @cache.decrement(crazy_key)
  end

  def test_really_long_keys
    key = ""
    900.times{key << "x"}
    assert @cache.write(key, "bar")
    assert_equal "bar", @cache.read(key)
    assert_equal "bar", @cache.fetch(key)
    assert_nil @cache.read("#{key}x")
    assert_equal({key => "bar"}, @cache.read_multi(key))
    assert @cache.delete(key)
  end

  def test_increment
    @cache.write('foo', 1, :raw => true)
    assert_equal 1, @cache.read('foo').to_i
    assert_equal 2, @cache.increment('foo')
    assert_equal 2, @cache.read('foo').to_i
    assert_equal 3, @cache.increment('foo')
    assert_equal 3, @cache.read('foo').to_i
    assert_nil @cache.increment('bar')
  end

  def test_increment_not_found
    expect_not_found
    assert_equal nil, @cache.increment('not_exist')
  end

  def test_decrement
    @cache.write('foo', 3, :raw => true)
    assert_equal 3, @cache.read('foo').to_i
    assert_equal 2, @cache.decrement('foo')
    assert_equal 2, @cache.read('foo').to_i
    assert_equal 1, @cache.decrement('foo')
    assert_equal 1, @cache.read('foo').to_i
    assert_nil @cache.decrement('bar')
  end

  def test_decrement_not_found
    expect_not_found
    assert_equal nil, @cache.decrement('not_exist')
  end

  def test_common_utf8_values
    key = "\xC3\xBCmlaut".force_encoding(Encoding::UTF_8)
    assert @cache.write(key, "1", :raw => true)
    assert_equal "1", @cache.read(key)
    assert_equal "1", @cache.fetch(key)
    assert @cache.delete(key)
    assert_equal "2", @cache.fetch(key, :raw => true) { "2" }
    assert_equal 3, @cache.increment(key)
    assert_equal 2, @cache.decrement(key)
  end

  def test_retains_encoding
    key = "\xC3\xBCmlaut".force_encoding(Encoding::UTF_8)
    assert @cache.write(key, "1", :raw => true)
    assert_equal Encoding::UTF_8, key.encoding
  end

  def test_initialize_accepts_a_list_of_servers_in_options
    options = {servers: ["localhost:21211"]}
    cache = ActiveSupport::Cache.lookup_store(:memcached_store, options)
    assert_equal 21211, cache.instance_variable_get(:@data).servers.first.port
  end

  def test_multiple_servers
    options = {servers: ["localhost:21211", "localhost:11211"]}
    cache = ActiveSupport::Cache.lookup_store(:memcached_store, options)
    assert_equal [21211, 11211], cache.instance_variable_get(:@data).servers.map(&:port)
  end

  def test_namespace_without_servers
    options = {namespace: 'foo:'}
    cache = ActiveSupport::Cache.lookup_store(:memcached_store, options)
    client = cache.instance_variable_get(:@data)
    assert_equal [11211], client.servers.map(&:port)
    assert_equal "", client.prefix_key, "should not send the namespace to the client"
    assert_equal "foo::key", cache.send(:namespaced_key, "key", cache.options)
  end
  
  def test_reset
    client = @cache.instance_variable_get(:@data)
    client.expects(:reset).once
    @cache.reset
  end

  def test_write_to_read_only_memcached_store_should_not_write
    with_read_only(@cache) do
      assert @cache.write("walrus", "awesome"), "Writing to a disabled memcached
      store should return truthy to make clients not care"

      assert_nil @cache.read("walrus"), "Key should have nil value in disabled cache"
    end
  end

  def test_delete_with_read_only_memcached_store_should_not_delete
    assert @cache.write("walrus", "big")

    with_read_only(@cache) do
      assert @cache.delete("walrus"), "Should return truthy when deleted to not raise in client"
    end

    assert_equal "big", @cache.read("walrus"), "Cache entry should not have been deleted from read only client"
  end

  def test_cas_with_read_only_memcached_store_should_not_s
    called_block = false
    @cache.write('walrus', 'slimy')

    with_read_only(@cache) do
      assert(@cache.cas('walrus') { |value| 
        assert_equal 'slimy', value
        called_block = true
        'full'
      })
    end

    assert_equal 'slimy', @cache.read('walrus')
    assert called_block, "CAS with read only should have called the inner block with an assertion"
  end

  def test_cas_multi_with_read_only_memcached_store_should_not_s
    called_block = false

    @cache.write('walrus', 'cool')
    @cache.write('narwhal', 'horn')

    with_read_only(@cache) do
      assert(@cache.cas_multi('walrus', 'narwhal') {
        called_block = true
        { "walrus" => "not cool", "narwhal" => "not with horns" }
      })
    end

    assert_equal 'cool', @cache.read('walrus')
    assert_equal 'horn', @cache.read('narwhal')
    assert called_block, "CAS with read only should have called the inner block with an assertion"
  end

  def test_write_with_read_only_should_not_send_activesupport_notification
    assert_notifications(/cache/, 0) do
      with_read_only(@cache) do
        assert @cache.write("walrus", "bestest")
      end
    end
  end

  def test_delete_with_read_only_should_not_send_activesupport_notification
    assert_notifications(/cache/, 0) do
      with_read_only(@cache) do
        assert @cache.delete("walrus")
      end
    end
  end

  def test_fetch_with_expires_in_with_read_only_should_not_send_activesupport_notification
    expires_in = 10
    @cache.fetch("walrus", expires_in: expires_in) { "yo" }

    Timecop.travel(Time.now + expires_in + 1) do
      assert_notifications(/cache_write/, 0) do
        with_read_only(@cache) do
          @cache.fetch("walrus") { "no" }
        end
      end
    end
  end

  def test_fetch_with_expired_entry_with_read_only_should_return_nil_and_not_delete_from_cache
    expires_in = 10
    @cache.fetch("walrus", expires_in: expires_in) { "yo" }

    Timecop.travel(Time.now + expires_in + 1) do
      with_read_only(@cache) do
        value = @cache.fetch("walrus", expires_in: expires_in) { "no" }

        assert_equal "no", value
        refute @cache.fetch("walrus"), "Client should return nil for expired key"
        assert_equal "yo", @cache.instance_variable_get(:@data).get("walrus").value
      end
    end
  end

  def test_fetch_with_expired_entry_and_race_condition_ttl_with_read_only_should_return_nil_and_not_delete_from_cache
    expires_in = 10
    race_condition_ttl = 10
    @cache.fetch("walrus", expires_in: expires_in) { "yo" }

    Timecop.travel(Time.now + expires_in + 1) do
      with_read_only(@cache) do
        value = @cache.fetch("walrus", expires_in: expires_in, race_condition_ttl: race_condition_ttl) { "no" }

        assert_equal "no", value
        assert_equal "no", @cache.fetch("walrus") { "no" }
        refute @cache.fetch("walrus")

        assert_equal "yo", @cache.instance_variable_get(:@data).get("walrus").value
      end
    end
  end

  def test_read_with_expired_with_read_only_entry_should_return_nil_and_not_delete_from_cache
    expires_in = 10
    @cache.fetch("walrus", expires_in: expires_in) { "yo" }

    Timecop.travel(Time.now + expires_in + 1) do
      with_read_only(@cache) do
        refute @cache.read("walrus")

        assert_equal "yo", @cache.instance_variable_get(:@data).get("walrus").value
      end
    end
  end

  def test_read_multi_with_expired_entry_should_return_nil_and_not_delete_from_cache
    expires_in = 10
    @cache.fetch("walrus", expires_in: expires_in) { "yo" }
    @cache.fetch("narwhal", expires_in: expires_in) { "yiir" }

    Timecop.travel(Time.now + expires_in + 1) do
      with_read_only(@cache) do
        assert_predicate @cache.read_multi("walrus", "narwhal"), :empty?

        assert_equal "yo", @cache.instance_variable_get(:@data).get("walrus").value
        assert_equal "yiir", @cache.instance_variable_get(:@data).get("narwhal").value
      end
    end
  end

  def test_fetch_with_race_condition_ttl_with_read_only_should_not_send_activesupport_notification
    expires_in = 10
    race_condition_ttl = 10
    @cache.fetch("walrus", expires_in: expires_in) { "yo" }

    Timecop.travel(Time.now + expires_in + 1) do
      assert_notifications(/cache_write/, 0) do
        with_read_only(@cache) do
          @cache.fetch("walrus", expires_in: expires_in, race_condition_ttl: race_condition_ttl) { "no" }
        end
      end
    end
  end

  def test_cas_with_read_only_should_send_activesupport_notification
    @cache.write("walrus", "yes")

    with_read_only(@cache) do
      assert_notifications(/cache_cas/, 1) do
        assert(@cache.cas("walrus") { |value| "no" })
      end
    end

    assert_equal "yes", @cache.fetch("walrus")
  end

  def test_cas_multi_with_read_only_should_send_activesupport_notification
    @cache.write("walrus", "yes")
    @cache.write("narwhal", "yes")

    with_read_only(@cache) do
      assert_notifications(/cache_cas/, 1) do
        assert(@cache.cas_multi("walrus", "narwhal") { |*values|
          { "walrus" => "no", "narwhal" => "no" }
        })
      end
    end

    assert_equal "yes", @cache.fetch("walrus")
    assert_equal "yes", @cache.fetch("narwhal")
  end

  private

  def assert_notifications(pattern, num)
    count = 0
    subscriber = ActiveSupport::Notifications.subscribe(pattern) do |name, start, finish, id, payload|
      count += 1
    end

    yield

    assert_equal num, count, "Expected #{num} notifications for #{pattern}, but got #{count}"
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  def with_read_only(client)
    previous, client.read_only = client.read_only, true
    yield
  ensure
    client.read_only = previous
  end

  def expect_not_found
    @cache.instance_variable_get(:@data).expects(:check_return_code).raises(Memcached::NotFound)
  end
end
