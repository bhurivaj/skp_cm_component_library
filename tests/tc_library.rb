# frozen_string_literal: true

# Run (no SketchUp needed): ruby tests/tc_library.rb
require 'minitest/autorun'
require 'tmpdir'
require 'json'
require_relative '../skp_cm_component_library/library'

class TestLibrary < Minitest::Test
  L = SkpCm::ComponentLibrary::Library
  INDEX = { 'schema' => 2, 'published_at' => 'x', 'categories' => ['col'],
            'items' => [{ 'code' => 'VC-4203', 'name' => 'เสา', 'category' => 'col', 'file' => 'VC-4203',
                          'version' => '20261101-105100' }] }.freeze

  class FakeDefinitions
    def [](_name)
      nil
    end
  end

  class FakeModel
    def definitions
      FakeDefinitions.new
    end
  end

  def setup
    @root = Dir.mktmpdir
    @gets = []
    root = @root
    gets = @gets
    L.define_singleton_method(:cache_root) { root }
    L.define_singleton_method(:http_get) { |url, &done| gets << [url, done] }
    L.instance_variable_set(:@loading, nil)
    L.index = nil
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def test_parse_index_ok
    assert_equal '20261101-105100', L.parse_index(JSON.generate(INDEX))['items'][0]['version']
  end

  def test_parse_index_rejects_bad_input
    bad_item = ->(patch) { JSON.generate(INDEX.merge('items' => [INDEX['items'][0].merge(patch)])) }
    ['not json', JSON.generate(INDEX.merge('schema' => 1)), JSON.generate(INDEX.reject { |k, _| k == 'items' }),
     '[]', bad_item.call('file' => '../x'), bad_item.call('version' => nil), bad_item.call('code' => 5),
     JSON.generate(INDEX.merge('categories' => 'col'))].each do |text|
      assert_raises(L::Error, text) { L.parse_index(text) }
    end
  end

  def test_stale_dirs_lists_other_publish_folders
    %w[20261101-105100 20261001-090000].each { |d| FileUtils.mkdir_p(File.join(@root, d)) }
    File.write(File.join(@root, 'index.json'), '{}')
    assert_equal [File.join(@root, '20261001-090000')], L.stale_dirs(@root, ['20261101-105100'])
  end

  def test_load_index_offline_without_cache_reports_error
    calls = []
    L.load_index { |*args| calls << args }
    @gets.first[1].call(nil, nil, 'network error')
    assert_equal 1, calls.size
    index, error, offline = calls.first
    assert_nil index
    assert_match(/network error/, error)
    assert_equal true, offline
  end

  def test_load_index_offline_uses_cache
    File.write(File.join(@root, 'index.json'), JSON.generate(INDEX))
    calls = []
    L.load_index { |*args| calls << args }
    @gets.first[1].call(nil, nil, 'network error')
    assert_equal [[INDEX, nil, false], [INDEX, nil, true]], calls
  end

  def test_load_index_new_publish_saves_cache_and_removes_old_folders
    FileUtils.mkdir_p(File.join(@root, '20261001-090000'))
    calls = []
    L.load_index { |*args| calls << args }
    @gets.first[1].call(200, JSON.generate(INDEX), nil)
    assert_equal [[INDEX, nil, false]], calls
    assert_equal INDEX, JSON.parse(File.read(File.join(@root, 'index.json')))
    refute File.exist?(File.join(@root, '20261001-090000'))
    assert_equal INDEX, L.index
  end

  def test_place_ignores_second_click_while_downloading
    L.index = INDEX
    downloads = []
    L.define_singleton_method(:download) { |url, path, &done| downloads << url }
    results = []
    2.times { L.place('VC-4203', FakeModel.new) { |*r| results << r } }
    assert_equal ['https://sketchup.blob.core.windows.net/component-library/library/20261101-105100/components/VC-4203.skp'],
                 downloads
    assert_empty results
  end

  def test_load_index_reports_even_if_cache_cannot_be_written
    File.write(File.join(@root, 'blocker'), 'x')
    blocked = File.join(@root, 'blocker', 'sub') # parent is a file → mkdir fails
    L.define_singleton_method(:cache_root) { blocked }
    calls = []
    L.load_index { |*args| calls << args }
    @gets.first[1].call(200, JSON.generate(INDEX), nil)
    assert_equal [[INDEX, nil, false]], calls
  end

  def test_late_download_does_not_place_into_another_model
    L.index = INDEX
    finish = nil
    L.define_singleton_method(:download) { |_url, _path, &done| finish = done }
    model = FakeModel.new
    L.define_singleton_method(:active_model) { :other_window }
    results = []
    L.place('VC-4203', model) { |*r| results << r }
    finish.call(true, nil)
    assert_equal false, results.first[0]
    assert_match(/คลิกอีกครั้ง/, results.first[1])
  end

  def test_place_unknown_code_reports_error
    L.index = INDEX
    results = []
    L.place('NOPE', FakeModel.new) { |*r| results << r }
    assert_equal false, results.first[0]
  end

  def test_update_downloads_everything_before_touching_the_model
    L.index = INDEX.merge('items' => INDEX['items'] + [{ 'code' => 'BM-4218', 'name' => 'คาน', 'category' => 'Beam',
                                                          'file' => 'BM-4218', 'version' => 'v9' }])
    finishers = {}
    L.define_singleton_method(:download) { |url, _path, &done| finishers[url] = done }
    applied = []
    SkpCm::ComponentLibrary::ModelUpdate.define_singleton_method(:apply) { |_m, updates| applied << updates }
    model = FakeModel.new
    L.define_singleton_method(:active_model) { model }
    results = []
    L.update({ 'VC-4203' => ['VC-4203'], 'BM-4218' => ['BM-4218'] }, model) { |*r| results << r }
    assert_equal 2, finishers.size
    finishers.values[0].call(true, nil)
    finishers.values[1].call(false, 'HTTP 404')
    assert_empty applied
    assert_equal false, results.first[0]
    assert_match(/BM-4218/, results.first[1])
  end

  def test_update_applies_after_all_downloads
    L.index = INDEX
    L.define_singleton_method(:download) { |_url, _path, &done| done.call(true, nil) }
    applied = []
    SkpCm::ComponentLibrary::ModelUpdate.define_singleton_method(:apply) { |_m, updates| applied << updates }
    model = FakeModel.new
    L.define_singleton_method(:active_model) { model }
    results = []
    L.update({ 'VC-4203' => ['VC-4203', 'VC-4203#1'] }, model) { |*r| results << r }
    assert_equal [[{ 'code' => 'VC-4203', 'version' => '20261101-105100', 'old_names' => ['VC-4203', 'VC-4203#1'],
                     'path' => File.join(@root, '20261101-105100', 'components', 'VC-4203.skp') }]], applied
    assert_equal [[true, nil]], results
  end

  def test_changes_marks_new_and_updated
    seen = { 'VC-4203' => 'old' }
    index = INDEX.merge('items' => INDEX['items'] + [{ 'code' => 'BM-1', 'file' => 'BM-1', 'version' => 'v' }])
    assert_equal({ 'VC-4203' => 'updated', 'BM-1' => 'new' }, L.changes(index, seen))
    assert_equal({}, L.changes(INDEX, 'VC-4203' => '20261101-105100'))
  end

  def test_first_run_has_no_badges_and_saves_seen
    assert_equal({}, L.seen_changes(INDEX))
    assert_equal({ 'VC-4203' => '20261101-105100' }, JSON.parse(File.read(File.join(@root, 'seen.json'))))
  end

  def test_ack_saves_current_versions
    File.write(File.join(@root, 'seen.json'), '{}')
    assert_equal({ 'VC-4203' => 'new' }, L.seen_changes(INDEX))
    L.ack(INDEX)
    assert_equal({}, L.seen_changes(INDEX))
  end

  def test_seen_changes_never_raises
    File.write(File.join(@root, 'seen.json'), '[1,2]')
    assert_equal({}, L.seen_changes(INDEX))
    L.define_singleton_method(:cache_root) { '/dev/null/nope' }
    assert_equal({}, L.seen_changes(INDEX))
  end
end
