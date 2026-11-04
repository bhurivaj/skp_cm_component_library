# frozen_string_literal: true

# Run (no SketchUp needed): ruby tests/tc_model_update.rb
require 'minitest/autorun'
require_relative '../skp_cm_component_library/model_update'

class TestModelUpdate < Minitest::Test
  M = SkpCm::ComponentLibrary::ModelUpdate
  INDEX = { 'items' => [
    { 'code' => 'VC-4203', 'version' => 'v2' },
    { 'code' => 'BM-4218', 'version' => 'v2' },
    { 'code' => 'WP-5018', 'version' => 'v1' }
  ] }.freeze

  def test_outdated_rules
    defs = [
      ['VC-4203', nil],        # copied from Structure Set: no label → outdated
      ['BM-4218', 'v1'],       # older version
      ['BM-4218#1', 'v1'],     # same code, merged into one entry
      ['WP-5018', 'v1'],       # up to date
      ['Bolt', nil],           # not a library code
      ['vc-4203', nil]         # case differs → not a code
    ]
    assert_equal({ 'VC-4203' => ['VC-4203'], 'BM-4218' => ['BM-4218', 'BM-4218#1'] }, M.outdated(defs, INDEX))
  end

  def test_outdated_empty_without_index
    assert_equal({}, M.outdated([['VC-4203', nil]], nil))
  end

  # Minimal stand-ins for SketchUp definitions (swap only uses these calls)
  class FakeInstance
    attr_accessor :definition, :dc

    def initialize(dc = {})
      @dc = dc
    end

    def set_attribute(dict, key, value)
      raise "unexpected dict #{dict}" unless dict == 'dynamic_attributes'

      @dc[key] = value
    end

    def attribute_dictionary(name)
      name == 'dynamic_attributes' && !@dc.empty? ? @dc : nil
    end
  end

  class FakeDef
    attr_accessor :name, :dc
    attr_reader :instances, :attrs

    def initialize(name, version = nil, instances = 1, dc: {}, instance_dc: {})
      @name = name
      @attrs = { 'version' => version }
      @dc = dc
      @instances = Array.new(instances) { FakeInstance.new(instance_dc.dup).tap { |i| i.definition = self } }
      @valid = true
    end

    def entities
      []
    end

    def attribute_dictionary(name)
      name == 'dynamic_attributes' && !@dc.empty? ? @dc : nil
    end

    def get_attribute(_dict, key)
      @attrs[key]
    end

    def set_attribute(_dict, key, value)
      @attrs[key] = value
    end

    def valid?
      @valid
    end

    def invalidate!
      @valid = false
    end
  end

  class FakeDefinitions
    attr_reader :loads, :removed

    def initialize(defs, load_result)
      @defs = defs
      @load_result = load_result
      @loads = 0
      @removed = []
    end

    def [](name)
      @defs.find { |d| d.valid? && d.name == name }
    end

    def load(_path)
      @loads += 1
      @defs << @load_result unless @defs.include?(@load_result)
      @load_result
    end

    def remove(definition)
      raise 'removed twice' unless definition.valid?

      definition.instances.each { |i| raise 'instance still on removed def' if i.definition == definition }
      definition.invalidate!
      @removed << definition.name
    end
  end

  def model_with(defs, load_result)
    definitions = FakeDefinitions.new(defs, load_result)
    Struct.new(:definitions).new(definitions)
  end

  def test_swap_when_load_returns_an_old_definition
    old = FakeDef.new('VC-4203', nil, 2) # pasted copy, same GUID as the library file
    model = model_with([old], old)
    M.swap(model, 'code' => 'VC-4203', 'version' => 'v2', 'old_names' => ['VC-4203'], 'path' => 'x')
    assert old.valid?
    assert_equal [], model.definitions.removed
    assert_equal 'v2', old.attrs['version']
  end

  def test_swap_merges_hash_copies_into_one_definition
    a = FakeDef.new('BM-4218', 'v1')
    b = FakeDef.new('BM-4218#1', nil)
    fresh = FakeDef.new('BM-4218#2', nil, 0)
    model = model_with([a, b], fresh)
    M.swap(model, 'code' => 'BM-4218', 'version' => 'v2', 'old_names' => %w[BM-4218 BM-4218#1], 'path' => 'x')
    assert_equal %w[BM-4218 BM-4218#1], model.definitions.removed
    assert_equal 'BM-4218', fresh.name
    assert_equal 2, (a.instances + b.instances).count { |i| i.definition == fresh }
  end

  def test_swap_reuses_current_definition_when_already_latest
    current = FakeDef.new('BM-4218', 'v2')
    copy = FakeDef.new('BM-4218#1', nil)
    model = model_with([current, copy], FakeDef.new('BM-4218#2', nil, 0))
    M.swap(model, 'code' => 'BM-4218', 'version' => 'v2', 'old_names' => ['BM-4218#1'], 'path' => 'x')
    assert_equal 0, model.definitions.loads
    assert_equal ['BM-4218#1'], model.definitions.removed
    assert_equal current, copy.instances.first.definition
  end

  OLD_DC = { '_level_access' => 'TEXTBOX', '_width_access' => 'LIST', '_deg_access' => 'NONE', '_old_access' => 'TEXTBOX' }.freeze
  NEW_DC = { '_level_access' => 'TEXTBOX', '_width_access' => 'TEXTBOX', '_deg_access' => 'NONE' }.freeze

  def test_user_inputs_only_editable_keys_present_on_instance
    inst = { 'level' => '70.8', 'width' => '72', 'deg' => '138', 'name' => 'x' }
    assert_equal({ 'level' => '70.8', 'width' => '72' }, M.user_inputs(inst, OLD_DC))
  end

  def test_restorable_keeps_keys_still_editable_in_new_version
    saved = { 'level' => '70.8', 'old' => '1' }
    assert_equal({ 'level' => '70.8' }, M.restorable(saved, NEW_DC))
  end

  def test_swap_restores_component_options_and_redraws
    old = FakeDef.new('VB-3019', 'v1', 2, dc: OLD_DC, instance_dc: { 'level' => '47.2', 'width' => '72', 'deg' => '9' })
    fresh = FakeDef.new('VB-3019#1', nil, 0, dc: NEW_DC)
    model = model_with([old], fresh)
    insts = old.instances.dup
    insts.each { |i| i.dc.replace('level' => 'reset', 'deg' => 'reset') } # what a swap would leave behind
    insts[0].dc.replace('level' => '47.2', 'width' => '72', 'deg' => '9')
    insts[1].dc.replace('level' => '23.6', 'width' => '72', 'deg' => '9')
    redrawn = []
    original = M.method(:dc_redraw)
    M.define_singleton_method(:dc_redraw) { |inst| redrawn << inst; true }
    M.swap(model, 'code' => 'VB-3019', 'version' => 'v2', 'old_names' => ['VB-3019'], 'path' => 'x')
    assert_equal %w[47.2 23.6], insts.map { |i| i.dc['level'] }
    assert_equal insts, redrawn
    assert(insts.all? { |i| i.definition.attrs['version'] == 'v2' })
  ensure
    M.define_singleton_method(:dc_redraw, original) if original
  end
end
