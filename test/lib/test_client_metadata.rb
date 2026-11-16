# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/client_metadata'

# Stand-ins for the network and the fetch limit, so no test reaches the internet.
module ClientMetadataDoubles
  CLAUDE_CODE = 'https://claude.ai/oauth/claude-code-client-metadata'

  # The internet as the fetcher sees it: what each name resolves to, and what
  # each URL answers, fetched from the address given.
  class FakeNetwork
    Response = ClientMetadata::Response

    attr_reader :connected

    def initialize
      @names = Hash.new { |_, host| raise Resolv::ResolvError, host }
      @pages = {}
      @connected = []
    end

    def resolve(host, *addresses)
      @names[host] = addresses
    end

    def page(url, status: 200, body: '', location: nil, cache_control: nil)
      @pages[url] = Response.new(status: status, body: body, location: location, cache_control: cache_control)
    end

    def slow(url)
      @pages[url] = :slow
    end

    def addresses(host)
      @names[host]
    end

    def get(uri, address)
      @connected << [uri.to_s, address]
      page = @pages.fetch(uri.to_s)
      raise Net::ReadTimeout if page == :slow

      page
    end
  end

  class FakeLimiter
    attr_reader :asked

    def initialize(allowed)
      @allowed = allowed
      @asked = []
    end

    def allow?(key)
      @asked << key
      @allowed
    end
  end
end

describe ClientMetadata do
  cover 'ClientMetadata*'

  def document(client_id = ClientMetadataDoubles::CLAUDE_CODE, **fields)
    JSON.generate({ client_id: client_id, client_name: 'Claude Code',
                    redirect_uris: ['http://localhost/callback', 'http://127.0.0.1/callback'] }.merge(fields))
  end

  def fetch(client_id = ClientMetadataDoubles::CLAUDE_CODE, limiter: ClientMetadataDoubles::FakeLimiter.new(true), now: @now)
    ClientMetadata.fetch(client_id, network: @net, limiter: limiter, now: now)
  end

  after { ClientMetadata.forget }

  before do
    ClientMetadata.forget
    @now = Time.now
    @net = ClientMetadataDoubles::FakeNetwork.new
    @net.resolve('claude.ai', '160.79.104.10')
  end

  describe 'fetching a document' do
    it 'gives back the document a client ID names' do
      @net.page(ClientMetadataDoubles::CLAUDE_CODE, body: document)

      result = fetch

      assert_nil result.error
      assert_equal 'Claude Code', result.document['client_name']
    end

    it 'connects to the address it checked' do
      @net.page(ClientMetadataDoubles::CLAUDE_CODE, body: document)

      fetch

      assert_equal [[ClientMetadataDoubles::CLAUDE_CODE, '160.79.104.10']], @net.connected
    end

    it 'takes only an HTTPS address on the standard port, with a path and no fragment' do
      ['http://claude.ai/oauth/doc', 'https://claude.ai:8443/oauth/doc', 'https://claude.ai',
       'https://claude.ai/', 'https://claude.ai/oauth/doc#part', 'https://user@claude.ai/oauth/doc',
       'https://claude.ai/oauth/../doc', 'https://claude.ai/./oauth/doc', 'http://claude.ai:443/oauth/doc', nil,
       'not a url', ''].each do |client_id|
        assert_equal :invalid_client_id, fetch(client_id).error, client_id
      end
      assert_empty @net.connected
    end

    it 'refuses an address that resolves anywhere private, local or reserved' do
      ['10.0.0.5', '127.0.0.1', '169.254.169.254', '192.168.1.1', '172.16.0.1', '100.64.0.1', '0.0.0.0',
       '224.0.0.1', '::1', 'fd00::1', 'fe80::1', '::ffff:10.0.0.1', '::ffff:100.64.0.1', '::'].each do |address|
        @net.resolve('claude.ai', '160.79.104.10', address)

        assert_equal :blocked_address, fetch.error, address
      end
      assert_empty @net.connected
    end

    it 'refuses a name that does not resolve, or resolves to nothing' do
      assert_equal :fetch_failed, fetch('https://nowhere.example/doc').error

      @net.resolve('empty.example')

      assert_equal :fetch_failed, fetch('https://empty.example/doc').error
    end

    it 'follows a redirect given as a path on the same site' do
      @net.page(ClientMetadataDoubles::CLAUDE_CODE, status: 308, location: '/oauth/moved')
      @net.page('https://claude.ai/oauth/moved', body: document)

      assert_nil fetch.error
      assert_equal 'https://claude.ai/oauth/moved', @net.connected.last.first
    end

    it 'follows one redirect, checking where it leads' do
      moved = 'https://cdn.claude.ai/doc'
      @net.resolve('cdn.claude.ai', '160.79.104.11')
      @net.page(ClientMetadataDoubles::CLAUDE_CODE, status: 301, location: moved)
      @net.page(moved, body: document)

      assert_nil fetch.error
      assert_equal [[ClientMetadataDoubles::CLAUDE_CODE, '160.79.104.10'], [moved, '160.79.104.11']], @net.connected
    end

    it 'refuses a redirect to a private address, and a second redirect' do
      @net.resolve('inside.claude.ai', '10.0.0.5')
      @net.page(ClientMetadataDoubles::CLAUDE_CODE, status: 302, location: 'https://inside.claude.ai/doc')

      assert_equal :blocked_address, fetch.error

      @net.resolve('cdn.claude.ai', '160.79.104.11')
      @net.page(ClientMetadataDoubles::CLAUDE_CODE, status: 302, location: 'https://cdn.claude.ai/doc')
      @net.page('https://cdn.claude.ai/doc', status: 302, location: 'https://cdn.claude.ai/other')

      assert_equal :too_many_redirects, fetch.error
    end

    it 'gives up on a redirect that says nowhere' do
      @net.page(ClientMetadataDoubles::CLAUDE_CODE, status: 302)

      assert_equal :too_many_redirects, fetch.error
    end

    it 'refuses a redirect to an address it would not fetch first' do
      @net.page(ClientMetadataDoubles::CLAUDE_CODE, status: 302, location: 'http://claude.ai/doc')

      assert_equal :invalid_client_id, fetch.error
    end

    it 'refuses a document over 10 KB' do
      @net.page(ClientMetadataDoubles::CLAUDE_CODE, body: document(padding: 'x' * ClientMetadata::MAX_BYTES))

      assert_equal :too_large, fetch.error
    end

    it 'gives up on a server that is too slow or answers with an error' do
      @net.slow(ClientMetadataDoubles::CLAUDE_CODE)

      assert_equal :fetch_failed, fetch.error

      @net.page(ClientMetadataDoubles::CLAUDE_CODE, status: 500, body: document)

      assert_equal :fetch_failed, fetch.error
    end

    it 'refuses a document that names another client, or is not a document' do
      [document('https://claude.ai/oauth/someone-else'), 'not json', '[]', document(redirect_uris: []),
       JSON.generate(redirect_uris: ['http://localhost/callback']),
       JSON.generate(client_id: ClientMetadataDoubles::CLAUDE_CODE),
       document(redirect_uris: ['https://claude.ai/cb', 7]), document(redirect_uris: 'https://claude.ai/cb')].each do |body|
        @net.page(ClientMetadataDoubles::CLAUDE_CODE, body: body)

        assert_equal :invalid_document, fetch.error, body
      end
    end

    it 'checks the client ID against the address it was asked for, not where it was sent' do
      moved = 'https://cdn.claude.ai/doc'
      @net.resolve('cdn.claude.ai', '160.79.104.11')
      @net.page(ClientMetadataDoubles::CLAUDE_CODE, status: 301, location: moved)
      @net.page(moved, body: document(moved))

      assert_equal :invalid_document, fetch.error
    end
  end

  describe 'keeping a document' do
    it 'keeps it as long as its own cache headers say, then fetches it again' do
      @net.page(ClientMetadataDoubles::CLAUDE_CODE, body: document, cache_control: 'public, max-age=300')

      fetch

      assert_equal 'Claude Code', fetch(now: @now + 299).document['client_name']
      assert_equal 1, @net.connected.size

      fetch(now: @now + 301)

      assert_equal 2, @net.connected.size
    end

    it 'keeps one a day at most, whatever its headers say' do
      @net.page(ClientMetadataDoubles::CLAUDE_CODE, body: document, cache_control: 'max-age=31536000')

      fetch
      fetch(now: @now + 86_399)
      fetch(now: @now + 86_401)

      assert_equal 2, @net.connected.size
    end

    it 'keeps so many documents at most, letting the oldest go' do
      ids = Array.new(ClientMetadata::MAX_KEPT + 1) { |n| "https://claude.ai/oauth/client-#{n}" }
      ids.each do |id|
        @net.page(id, body: document(id), cache_control: 'max-age=300')
        fetch(id)
      end
      fetch(ids.last)
      fetch(ids[1])
      fetch(ids.first)

      assert_equal ids.size + 1, @net.connected.size
    end

    it 'does not keep one whose headers do not say how long' do
      @net.page(ClientMetadataDoubles::CLAUDE_CODE, body: document, cache_control: 'no-store')

      fetch
      fetch

      assert_equal 2, @net.connected.size
    end

    it 'does not keep a refusal' do
      @net.page(ClientMetadataDoubles::CLAUDE_CODE, status: 500)
      fetch
      @net.page(ClientMetadataDoubles::CLAUDE_CODE, body: document, cache_control: 'max-age=300')

      assert_nil fetch.error
    end

    it 'stops fetching a client ID that is asked for too often, but still gives one it kept' do
      @net.page(ClientMetadataDoubles::CLAUDE_CODE, body: document, cache_control: 'max-age=300')

      limiter = ClientMetadataDoubles::FakeLimiter.new(false)

      assert_equal :rate_limited, fetch(limiter: limiter).error
      assert_equal [ClientMetadataDoubles::CLAUDE_CODE], limiter.asked
      assert_empty @net.connected

      fetch

      assert_nil fetch(limiter: ClientMetadataDoubles::FakeLimiter.new(false)).error
    end
  end

  describe 'redirect addresses' do
    def doc(*uris)
      { 'client_id' => ClientMetadataDoubles::CLAUDE_CODE, 'redirect_uris' => uris }
    end

    it 'takes any one of those the document lists' do
      assert ClientMetadata.redirect_allowed?(doc('https://claude.ai/one', 'https://claude.ai/two'), 'https://claude.ai/two')
    end

    it 'takes one the document lists, exactly' do
      assert ClientMetadata.redirect_allowed?(doc('https://claude.ai/api/mcp/auth_callback'),
        'https://claude.ai/api/mcp/auth_callback')
      refute ClientMetadata.redirect_allowed?(doc('https://claude.ai/api/mcp/auth_callback'),
        'https://claude.ai/api/mcp/auth_callback?x=1')
      refute ClientMetadata.redirect_allowed?(doc('https://claude.ai/api/mcp/auth_callback'), 'https://claude.ai/other')
    end

    it 'ignores the port on a loopback address, and only there' do
      assert ClientMetadata.redirect_allowed?(doc('http://localhost/callback'), 'http://localhost:53682/callback')
      assert ClientMetadata.redirect_allowed?(doc('http://127.0.0.1/callback'), 'http://127.0.0.1:4000/callback')
      assert ClientMetadata.redirect_allowed?(doc('http://[::1]/callback'), 'http://[::1]:4000/callback')
      refute ClientMetadata.redirect_allowed?(doc('http://localhost/callback'), 'http://localhost:53682/other')
      refute ClientMetadata.redirect_allowed?(doc('http://localhost/callback'), 'http://localhost:53682/callback?x=1')
      refute ClientMetadata.redirect_allowed?(doc('https://claude.ai/callback'), 'https://claude.ai:8443/callback')
      refute ClientMetadata.redirect_allowed?(doc('https://claude.ai/callback'), 'https://claude.ai:443/callback')
      refute ClientMetadata.redirect_allowed?(doc('http://localhost/callback?x=1'), 'http://localhost:4000/callback')
    end

    it 'refuses one on another site, even when the document lists it' do
      refute ClientMetadata.redirect_allowed?(doc('https://evil.example/callback'), 'https://evil.example/callback')
    end

    it 'refuses one that is not an address' do
      refute ClientMetadata.redirect_allowed?(doc('http://localhost/callback'), 'not a url')
      refute ClientMetadata.redirect_allowed?(doc('http://localhost/callback'), nil)
    end
  end

  it 'recognises the documents of claude.ai and chatgpt.com, and no others' do
    assert ClientMetadata.recognised?(ClientMetadataDoubles::CLAUDE_CODE)
    assert ClientMetadata.recognised?('https://chatgpt.com/oauth/client.json')
    refute ClientMetadata.recognised?('https://claude.ai.evil.example/doc')
    refute ClientMetadata.recognised?('https://evil.example/claude.ai')
    refute ClientMetadata.recognised?('not a url')
  end
end
