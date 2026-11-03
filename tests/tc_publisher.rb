# frozen_string_literal: true

# Run (no SketchUp needed): ruby tests/tc_publisher.rb
require 'minitest/autorun'
require 'tmpdir'
require_relative '../skp_cm_component_library/publisher'

class TestPublisher < Minitest::Test
  P = SkpCm::ComponentLibrary::Publisher
  LIST = {
    'items' => {
      'VC-4203' => { 'name' => 'เสา', 'category' => 'col' },
      'BM-4206' => { 'name' => 'คาน', 'category' => 'Beam' },
      'PLY-1' => { 'name' => 'ไม้อัด', 'category' => 'Material' }
    },
    'categories' => %w[col Beam Material]
  }.freeze

  def test_select_keeps_only_code_names_and_prefers_no_hash
    r = P.select(['VC-4203#1', 'VC-4203', 'Bolt part', 'vc-4206', 'BM-4206#3'], LIST)
    assert_equal({ 'VC-4203' => 'VC-4203', 'BM-4206' => 'BM-4206#3' }, r['chosen'])
    assert_equal ['VC-4203'], r['duplicates']
    assert_equal({ 'Material' => ['PLY-1'] }, r['missing'])
  end

  def test_select_is_case_sensitive
    expected = { 'col' => ['VC-4203'], 'Beam' => ['BM-4206'], 'Material' => ['PLY-1'] }
    assert_equal expected, P.select(['vc-4203'], LIST)['missing']
  end

  class FakeDefinition
    def initialize(ok)
      @ok = ok
    end

    def save_as(path)
      File.write(path, 'skp') if @ok
      @ok
    end

    def refresh_thumbnail; end

    def save_thumbnail(path)
      File.write(path, 'png') if @ok
      @ok
    end
  end

  def test_write_returns_codes_that_failed_to_save
    model = Struct.new(:definitions).new('VC-4203' => FakeDefinition.new(true), 'BM-4206#3' => FakeDefinition.new(false))
    Dir.mktmpdir do |dir|
      failed = P.write(model, { 'VC-4203' => 'VC-4203', 'BM-4206' => 'BM-4206#3' }, dir)
      assert_equal ['BM-4206'], failed
      assert File.exist?(File.join(dir, 'components', 'VC-4203.skp'))
    end
  end

  def test_index_shape
    i = P.index(LIST, %w[BM-4206 VC-4203], '20261101-105100', '2026-11-01T10:51:00+07:00')
    assert_equal 2, i['schema']
    refute i.key?('publish_id')
    assert_equal '2026-11-01T10:51:00+07:00', i['published_at']
    assert_equal %w[col Beam], i['categories']
    assert_equal({ 'code' => 'VC-4203', 'name' => 'เสา', 'category' => 'col', 'file' => 'VC-4203',
                   'version' => '20261101-105100' }, i['items'].first)
    assert_equal 2, i['items'].size
  end

  def test_index_merges_previous_versions
    previous = { 'schema' => 2, 'items' => [
      { 'code' => 'VC-4203', 'name' => 'เสาเก่า', 'category' => 'col', 'file' => 'VC-4203', 'version' => 'old1' },
      { 'code' => 'BM-4206', 'name' => 'คาน', 'category' => 'Beam', 'file' => 'BM-4206', 'version' => 'old2' },
      { 'code' => 'GONE-1', 'name' => 'ไม่มีใน CSV', 'category' => 'Misc', 'file' => 'GONE-1', 'version' => 'old3' }
    ] }
    i = P.index(LIST, %w[BM-4206], 'new', 't', previous)
    versions = i['items'].map { |it| [it['code'], it['version'], it['name']] }
    assert_equal [%w[VC-4203 old1 เสา], %w[BM-4206 new คาน], ['GONE-1', 'old3', 'ไม่มีใน CSV']], versions
    assert_equal %w[col Beam Misc], i['categories']
  end

  def test_structure_set_detected_by_file_name
    assert P.structure_set?('/x/Sketch Up Materials/CM Structure Set.skp')
    refute P.structure_set?('/x/CM Structure Set copy.skp')
    refute P.structure_set?('')
  end

  def test_selected_codes
    r = P.selected_codes(['VC-4203#2', 'VC-4203', 'Bolt', 'BM-4206'], LIST)
    assert_equal %w[VC-4203 BM-4206], r['codes']
    assert_equal ['Bolt'], r['unknown']
  end
end
