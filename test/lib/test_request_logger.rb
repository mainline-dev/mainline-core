# frozen_string_literal: true

require_relative '../coverage_helper'
ENV['MT_NO_PLUGINS'] = '1'
gem 'minitest'
require 'minitest/global_expectations/autorun'
require_relative '../../lib/request_logger'

describe RequestLogger do
  let(:output) { StringIO.new }
  let(:app) { ->(_env) { [200, { 'content-length' => '5' }, ['hello']] } }
  let(:logger) { RequestLogger.new(app, output) }
  let(:env) do
    { 'REQUEST_METHOD' => 'GET',
      'PATH_INFO'      => '/test',
      'QUERY_STRING'   => '',
      'REMOTE_ADDR'    => '127.0.0.1',
      'rack.input'     => StringIO.new }
  end

  it 'logs request with hash headers' do
    logger.call(env)

    assert_includes output.string, 'GET /test'
    assert_includes output.string, '200'
  end

  it 'skips logging for /up health check' do
    env['PATH_INFO'] = '/up'
    logger.call(env)

    assert_empty output.string
  end

  it 'logs referer and user agent' do
    env['HTTP_REFERER'] = 'https://example.com/page'
    env['HTTP_USER_AGENT'] = 'Mozilla/5.0'
    logger.call(env)

    assert_includes output.string, '"https://example.com/page"'
    assert_includes output.string, '"Mozilla/5.0"'
  end

  it 'logs dashes when referer and user agent are absent' do
    logger.call(env)

    assert_includes output.string, '"-" "-"'
  end

  it 'does not crash when headers are an array' do
    broken_app = ->(_env) { [200, [%w[content-length 5]], ['hello']] }
    mw = RequestLogger.new(broken_app, output)

    status, headers, _body = mw.call(env)

    assert_equal 200, status
    assert_kind_of Array, headers
    assert_includes output.string, 'GET /test'
  end
end
