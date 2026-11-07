# frozen_string_literal: true

require_relative '../model_spec_helper'
require 'rack'
require_relative '../../lib/cloudflare_client_ip'

describe CloudflareClientIp do
  # The address the app sees for a request, after the middleware.
  def ip_seen(env)
    seen = nil
    app = CloudflareClientIp.new(lambda { |e|
      seen = Rack::Request.new(e).ip
      [200, {}, []]
    })
    app.call(Rack::MockRequest.env_for('/', env))
    seen
  end

  def through_proxy(peer, visitor)
    { 'REMOTE_ADDR' => '172.18.0.5', 'HTTP_X_FORWARDED_FOR' => peer, 'HTTP_CF_CONNECTING_IP' => visitor }
  end

  it "takes the visitor's address from Cloudflare" do
    assert_equal '203.0.113.7', ip_seen(through_proxy('162.158.95.101', '203.0.113.7'))
    assert_equal '2001:db8::7', ip_seen(through_proxy('2606:4700::1', '2001:db8::7'))
  end

  it 'ignores the header from anywhere but Cloudflare' do
    assert_equal '198.51.100.9', ip_seen(through_proxy('198.51.100.9', '203.0.113.7'))
  end

  it 'ignores a header that is not an address' do
    assert_equal '162.158.95.101', ip_seen(through_proxy('162.158.95.101', '203.0.113.7, 10.0.0.1'))
    assert_equal '162.158.95.101', ip_seen(through_proxy('162.158.95.101', ''))
  end

  it 'leaves a request that came straight to the app alone' do
    assert_equal '127.0.0.1', ip_seen('REMOTE_ADDR' => '127.0.0.1', 'HTTP_CF_CONNECTING_IP' => '203.0.113.7')
  end
end
