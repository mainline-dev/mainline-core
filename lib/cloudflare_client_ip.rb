# frozen_string_literal: true

require 'ipaddr'
require 'rack'

# Behind Cloudflare, the proxy in front of the app reports Cloudflare's server
# as the visitor. Cloudflare passes the visitor's own address in
# CF-Connecting-IP. This believes that header only when the request really
# came from one of Cloudflare's servers, and then makes it the address the rest
# of the app sees: rate limits and the request log count visitors, not
# Cloudflare servers. Anyone reaching the app another way is seen as themselves.
class CloudflareClientIp
  # Cloudflare's published ranges, https://www.cloudflare.com/ips (checked 2026-11-04).
  RANGES = %w[
    173.245.48.0/20 103.21.244.0/22 103.22.200.0/22 103.31.4.0/22 141.101.64.0/18 108.162.192.0/18
    190.93.240.0/20 188.114.96.0/20 197.234.240.0/22 198.41.128.0/17 162.158.0.0/15 104.16.0.0/13
    104.24.0.0/14 172.64.0.0/13 131.0.72.0/22
    2400:cb00::/32 2606:4700::/32 2803:f800::/32 2405:b500::/32 2405:8100::/32 2a06:98c0::/29 2c0f:f248::/32
  ].map { |range| IPAddr.new(range) }.freeze
  ADDRESS = /\A[\h:.]+\z/

  def initialize(app)
    @app = app
  end

  def call(env)
    visitor = env['HTTP_CF_CONNECTING_IP'].to_s
    env['HTTP_X_FORWARDED_FOR'] = visitor if address?(visitor) && cloudflare?(Rack::Request.new(env).ip)
    @app.call(env)
  end

  private

  def address?(value)
    value.match?(ADDRESS) && IPAddr.new(value) && true
  rescue IPAddr::Error
    false
  end

  def cloudflare?(ip)
    address = IPAddr.new(ip.to_s)
    RANGES.any? { |range| range.include?(address) }
  rescue IPAddr::Error
    false
  end
end
