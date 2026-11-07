# frozen_string_literal: true

require_relative '../model_spec_helper'
require 'sentry-ruby'
require_relative '../../lib/revoke_oauth_token'

describe RevokeOauthToken do
  cover 'RevokeOauthToken*'
  before do
    ENV['GH_OAUTH_CLIENT_ID'] = 'test_id'
    ENV['GH_OAUTH_CLIENT_SECRET'] = 'test_secret'
    @captured = []
  end

  it 'returns nil when token is nil' do
    result = RevokeOauthToken.call('google_oauth2', nil)

    assert_nil result
  end

  it 'reports google revocation errors to Sentry' do
    captured = @captured
    Sentry.stub(:initialized?, true) do
      Sentry.stub(:capture_exception, ->(e) { captured << e }) do
        Net::HTTP.stub(:post_form, ->(*) { raise Net::OpenTimeout, 'timed out' }) do
          result = RevokeOauthToken.call('google_oauth2', 'tok_abc')

          assert_nil result
          assert_equal 1, captured.size
          assert_kind_of Net::OpenTimeout, captured.first
        end
      end
    end
  end

  it 'reports github revocation errors to Sentry' do
    captured = @captured
    Sentry.stub(:initialized?, true) do
      Sentry.stub(:capture_exception, ->(e) { captured << e }) do
        Net::HTTP.stub(:start, ->(*) { raise Net::OpenTimeout, 'timed out' }) do
          result = RevokeOauthToken.call('github', 'tok_abc')

          assert_nil result
          assert_equal 1, captured.size
          assert_kind_of Net::OpenTimeout, captured.first
        end
      end
    end
  end

  it 'posts token to Google revoke endpoint' do
    captured_uri = nil
    captured_params = nil
    fake_response = Net::HTTPSuccess.new('1.1', '200', 'OK')
    Net::HTTP.stub(:post_form, lambda { |uri, params|
      captured_uri = uri
      captured_params = params
      fake_response
    }) do
      result = RevokeOauthToken.call('google_oauth2', 'tok_google')

      assert_equal fake_response, result
    end

    assert_equal URI('https://oauth2.googleapis.com/revoke'), captured_uri
    assert_equal 'tok_google', captured_params['token']
  end

  it 'sends DELETE to GitHub token endpoint with basic auth' do
    captured_req = nil
    fake_response = Net::HTTPSuccess.new('1.1', '204', 'No Content')
    http = Object.new
    http.define_singleton_method(:request) do |req|
      captured_req = req
      fake_response
    end
    Net::HTTP.stub(:start, lambda { |_host, _port, **_kwargs, &blk|
      blk.call(http)
    }) do
      result = RevokeOauthToken.call('github', 'tok_github')

      assert_equal fake_response, result
    end

    assert_equal '/applications/test_id/token', captured_req.path
    assert_equal 'application/json', captured_req.content_type
    assert_equal 'tok_github', JSON.parse(captured_req.body)['access_token']
  end

  it 'does nothing for unknown provider' do
    result = RevokeOauthToken.call('unknown', 'tok_abc')

    assert_nil result
  end

  it 'does not report to Sentry when not initialized' do
    Sentry.stub(:initialized?, false) do
      Net::HTTP.stub(:post_form, ->(*) { raise Net::OpenTimeout, 'timed out' }) do
        result = RevokeOauthToken.call('google_oauth2', 'tok_abc')

        assert_nil result
      end
    end
  end
end
