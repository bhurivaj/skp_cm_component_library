# frozen_string_literal: true

# Run (no SketchUp needed): ruby tests/tc_uploader.rb
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative '../skp_cm_component_library/uploader'

class TestUploader < Minitest::Test
  U = SkpCm::ComponentLibrary::Uploader

  def setup
    @dir = Dir.mktmpdir
    { 'components/B.skp' => 's', 'components/A.skp' => 's', 'thumbs/A.png' => 'p', 'index/index.json' => '{}' }.each do |rel, body|
      FileUtils.mkdir_p(File.dirname(File.join(@dir, rel)))
      File.write(File.join(@dir, rel), body)
    end
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def test_plan_order_index_last
    blobs = U.plan(@dir, 'v1').map(&:last)
    assert_equal %w[library/v1/components/A.skp library/v1/components/B.skp library/v1/thumbs/A.png library/index.json], blobs
  end

  def test_content_type
    assert_equal 'application/json', U.content_type('x/index.json')
    assert_equal 'image/png', U.content_type('a.png')
    assert_equal 'application/octet-stream', U.content_type('a.skp')
  end

  def run_upload(replies)
    sent = []
    put = lambda do |blob, _path, sas|
      sent << [blob, sas]
      replies.fetch(blob, [[201, nil]]).shift || [201, nil]
    end
    result = nil
    U.run(U.plan(@dir, 'v1'), 'sig=1', put: put, schedule: ->(&step) { step.call }) { |*r| result = r }
    [sent.map(&:first), result]
  end

  def test_stops_before_index_when_a_file_fails_twice
    sent, result = run_upload('library/v1/components/B.skp' => [[500, 'boom'], [500, 'boom']])
    assert_equal %w[library/v1/components/A.skp library/v1/components/B.skp library/v1/components/B.skp], sent
    assert_equal false, result[0]
    assert_match(%r{library/v1/components/B.skp}, result[1])
    assert_equal 500, result[2]
  end

  def test_retry_once_then_continue
    sent, result = run_upload('library/v1/thumbs/A.png' => [[0, 'network error']])
    assert_equal 'library/index.json', sent.last
    assert_equal 5, sent.size
    assert_equal [true, nil, nil], result
  end

  def test_progress_reported
    seen = []
    U.run(U.plan(@dir, 'v1'), 's', put: ->(*) { [201, nil] }, schedule: ->(&step) { step.call },
                                   on_progress: ->(done, total) { seen << [done, total] }) { |*| nil }
    assert_equal [[1, 4], [2, 4], [3, 4], [4, 4]], seen
  end

  def test_http_put_never_shows_the_sas
    status, message = U.http_put('library/a.json', File.join(@dir, 'index/index.json'), 'sig=SECRET with space')
    assert_equal 0, status
    refute_includes message, 'SECRET'
  end
end
