# frozen_string_literal: true

require 'ipaddr'
require 'json'
require 'net/http'
require 'openssl'
require 'resolv'
require 'uri'
require_relative 'https_fetch'
require_relative 'shared_rate_limiter'

# A client's ID metadata document: the JSON an OAuth client publishes at the
# HTTPS address it uses as its client ID, naming the client and listing where
# a sign-in may send the person back to.
#
# Fetching one reaches an address a stranger chose, so: HTTPS on the standard
# port only; every address the name resolves to is checked, and the
# connection goes to an address that was checked, never one that is private,
# local or reserved; one redirect at most, checked the same way; five seconds
# and 10 KB at most. The document must name itself by the address it was
# asked for. It is kept as long as its own cache headers say, up to a day,
# and fetches are limited per client ID.
module ClientMetadata
  MAX_BYTES = 10_240
  MAX_KEPT = 500
  MAX_AGE = 86_400
  REDIRECTS = [301, 302, 303, 307, 308].freeze
  RECOGNISED_HOSTS = %w[claude.ai chatgpt.com].freeze
  LOOPBACK_HOSTS = %w[localhost 127.0.0.1 [::1]].freeze
  # Ranges no document may come from, besides those IPAddr calls private,
  # loopback or link-local: this network, shared address space, protocol
  # assignments, documentation, benchmarking, multicast, reserved, and IPv6's
  # unspecified, translation, discard, documentation and multicast ranges.
  BLOCKED = %w[0.0.0.0/8 100.64.0.0/10 192.0.0.0/24 192.0.2.0/24 198.18.0.0/15 198.51.100.0/24
               203.0.113.0/24 224.0.0.0/4 240.0.0.0/4 ::/128 64:ff9b::/96 100::/64 2001:db8::/32
               ff00::/8].map { |range| IPAddr.new(range) }.freeze
  FAILURES = [Resolv::ResolvError, SocketError, Timeout::Error, SystemCallError, IOError, OpenSSL::SSL::SSLError,
              Net::HTTPBadResponse, Net::ProtocolError, IPAddr::Error].freeze

  Response = Struct.new(:status, :body, :location, :cache_control, keyword_init: true)
  Result = Struct.new(:document, :error)

  LIMITER = SharedRateLimiter.new(name: 'client_metadata', capacity: 20, refill_rate: 20.0 / 3600)

  @kept = {}
  @lock = Mutex.new
  @network = HttpsFetch

  class << self
    # Where documents come from: the internet, or a stand-in in tests.
    attr_accessor :network
  end

  # The document a client ID names, or why there is none: :invalid_client_id,
  # :rate_limited, :blocked_address, :too_many_redirects, :too_large,
  # :fetch_failed or :invalid_document.
  def self.fetch(client_id, network: self.network, limiter: LIMITER, now: Time.now)
    kept = kept(client_id, now)
    return Result.new(kept) if kept

    uri = fetchable(client_id)
    return Result.new(nil, :invalid_client_id) unless uri
    return Result.new(nil, :rate_limited) unless limiter.allow?(client_id)

    answer = get(uri, network, 1)
    return Result.new(nil, answer) if answer.is_a?(Symbol)

    document = parse(answer.body, client_id)
    return Result.new(nil, :invalid_document) unless document

    keep(client_id, document, answer.cache_control, now)
    Result.new(document)
  rescue *FAILURES
    Result.new(nil, :fetch_failed)
  end

  # The address, if it is one a document may be fetched from: HTTPS, on the
  # standard port, with a path and no dot segments, no credentials and no
  # fragment. A missing value, or a field sent twice, which arrives as a list,
  # is refused too: URI.parse raises InvalidURIError for anything not a string.
  def self.fetchable(url)
    uri = URI.parse(url)
    return unless uri.is_a?(URI::HTTPS) && uri.port == 443 && uri.userinfo.nil? && uri.fragment.nil?

    segments = uri.path.split('/')
    uri unless segments.empty? || segments.intersect?(%w[. ..])
  rescue URI::InvalidURIError
    nil
  end

  def self.get(uri, network, redirects_left)
    addresses = network.addresses(uri.host)
    return :fetch_failed if addresses.empty?
    return :blocked_address if addresses.any? { |address| blocked?(address) }

    response = network.get(uri, addresses.first)
    return redirect(uri, response, network, redirects_left) if REDIRECTS.include?(response.status)
    return :fetch_failed unless response.status == 200

    response.body.bytesize > MAX_BYTES ? :too_large : response
  end

  def self.redirect(from, response, network, redirects_left)
    return :too_many_redirects if redirects_left.zero?

    target = fetchable(URI.join(from, response.location.to_s).to_s)
    target ? get(target, network, redirects_left - 1) : :invalid_client_id
  end

  def self.blocked?(address)
    ip = IPAddr.new(address).native
    ip.private? || ip.loopback? || ip.link_local? || BLOCKED.any? { |range| range.include?(ip) }
  end

  def self.parse(body, client_id)
    document = JSON.parse(body)
    return unless document.is_a?(Hash) && document['client_id'] == client_id

    uris = document['redirect_uris']
    document if uris.is_a?(Array) && !uris.empty? && uris.all?(String)
  rescue JSON::ParserError
    nil
  end

  def self.keep(client_id, document, cache_control, now)
    age = cache_control&.slice(/max-age=(\d+)/, 1)
    return unless age

    @lock.synchronize do
      @kept.shift if @kept.size >= MAX_KEPT
      @kept[client_id] = [document, now + [age.to_i, MAX_AGE].min]
    end
  end

  def self.kept(client_id, now)
    document, until_time = @lock.synchronize { @kept[client_id] }
    document if until_time && now < until_time
  end

  def self.forget
    @lock.synchronize { @kept.clear }
  end

  # Whether a sign-in may send the person back to this address: one the
  # document lists, exactly, except that a loopback address may be on any
  # port; and anything but a loopback address on the client ID's own site. A
  # missing address, or one sent twice, is refused as a malformed one is.
  def self.redirect_allowed?(document, redirect_uri)
    given = URI.parse(redirect_uri)
    listed = document.fetch('redirect_uris').any? { |uri| same_redirect?(uri, redirect_uri, given) }
    listed && (loopback?(given) || same_origin?(given, URI.parse(document.fetch('client_id'))))
  rescue URI::InvalidURIError
    false
  end

  # The same address, or the same loopback address on another port. Equal
  # hosts are both loopback or both not, so only the address given is asked.
  def self.same_redirect?(listed, redirect_uri, given)
    return true if listed == redirect_uri

    listed = URI.parse(listed)
    loopback?(given) &&
      [listed.scheme, listed.host, listed.path, listed.query] == [given.scheme, given.host, given.path, given.query]
  end

  def self.loopback?(uri)
    LOOPBACK_HOSTS.include?(uri.host)
  end

  def self.same_origin?(one, other)
    [one.scheme, one.host, one.port] == [other.scheme, other.host, other.port]
  end

  # Whether the client is one of the two whose name the consent page shows.
  def self.recognised?(client_id)
    RECOGNISED_HOSTS.include?(URI.parse(client_id).host)
  rescue URI::InvalidURIError
    false
  end

  private_class_method :fetchable, :get, :redirect, :blocked?, :parse, :keep, :kept, :same_redirect?, :loopback?,
    :same_origin?
end
