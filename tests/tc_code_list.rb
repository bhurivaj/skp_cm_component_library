# frozen_string_literal: true

# Run (no SketchUp needed): ruby tests/tc_code_list.rb
require 'minitest/autorun'
require_relative '../skp_cm_component_library/code_list'

class TestCodeList < Minitest::Test
  L = SkpCm::ComponentLibrary::CodeList
  CSV_TEXT = "Material Code List,,,\n,,,\nNo.,Categories,Code,List\n" \
             "1,col,VC-4203,\"เสา Ø1-1/4\"\" 0.3 m\"\n2,col,,ว่าง\n3,Beam,BM-4206,คาน\n"

  def test_parse_finds_header_row_and_reads_rows
    r = L.parse(CSV_TEXT.b)
    assert_equal({ 'name' => 'เสา Ø1-1/4" 0.3 m', 'category' => 'col' }, r['items']['VC-4203'])
    assert_equal %w[VC-4203 BM-4206], r['items'].keys
    assert_equal %w[col Beam], r['categories']
  end

  def test_parse_strips_bom
    assert L.parse("\xEF\xBB\xBF".b + CSV_TEXT.b)['items'].key?('VC-4203')
  end

  def test_parse_rejects_non_utf8
    e = assert_raises(L::Error) { L.parse("No.,Categories,Code\n1,\xE0\xB9,X\n".b) }
    assert_match(/CSV UTF-8/, e.message)
  end

  def test_parse_rejects_missing_header
    assert_raises(L::Error) { L.parse("a,b\n1,2\n".b) }
  end

  def test_base_name
    assert_equal 'VC-4203', L.base_name('VC-4203#2 ')
    assert_equal 'VC-4203', L.base_name(' VC-4203')
  end

  def test_file_name
    assert_equal 'WP-5018.W', L.file_name('WP-5018.W')
    assert_equal 'A_B_C', L.file_name('A/B C')
  end
end
