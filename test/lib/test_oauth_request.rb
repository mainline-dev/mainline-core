# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../dsl/client_documents'
require_relative '../../lib/oauth_request'

describe OauthRequest do
  cover 'OauthRequest*'

  before do
    @documents = ClientDocuments.new
    ClientMetadata.network = @documents
    @client = 'https://claude.ai/oauth/claude-code-client-metadata'
    publish(@client, 'Claude Code', ['http://localhost/callback'])
  end

  after do
    ClientMetadata.network = HttpsFetch
    ClientMetadata.forget
    ClientMetadata::LIMITER.reset
  end

  def publish(client_id, name, redirect_uris)
    @documents.publish(client_id, JSON.generate(client_id: client_id, client_name: name, redirect_uris: redirect_uris))
  end

  def params(**changes)
    { 'response_type' => 'code', 'client_id' => @client, 'redirect_uri' => 'http://localhost:4000/callback',
      'state' => 'abc', 'code_challenge' => 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
      'code_challenge_method' => 'S256', 'resource' => "#{ENV.fetch('BASE_URL')}/mcp", 'scope' => 'mainline:read' }
      .merge(changes.transform_keys(&:to_s)).compact
  end

  def sent_back(outcome)
    uri = URI(outcome.back)
    [uri.to_s.split('?').first, URI.decode_www_form(uri.query).to_h]
  end

  describe 'a request it can answer' do
    it 'takes a request from an app it can identify, to an address the app lists' do
      request = OauthRequest.check(params).request

      assert_equal [@client, 'http://localhost:4000/callback', 'abc'], [request.client_id, request.redirect_uri, request.state]
      assert_equal ['E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM', "#{ENV.fetch('BASE_URL')}/mcp"], [request.challenge, request.resource]
    end

    it 'names a recognised app by its name, and any other by its site' do
      publish('https://agent.example/client.json', 'Claude', ['https://agent.example/callback'])
      other = OauthRequest.check(params(client_id: 'https://agent.example/client.json',
        redirect_uri: 'https://agent.example/callback')).request

      assert_equal ['Claude Code', true], [OauthRequest.check(params).request.shown_name, OauthRequest.check(params).request.recognised]
      assert_equal ['agent.example', false, 'agent.example'], [other.shown_name, other.recognised, other.redirect_site]
    end

    it 'takes a request for offline access as well, or for no scope at all' do
      refute_nil OauthRequest.check(params(scope: 'mainline:read offline_access')).request
      refute_nil OauthRequest.check(params(scope: nil)).request
    end
  end

  describe 'a request it answers on a page' do
    it 'is from an app it cannot identify' do
      outcome = OauthRequest.check(params(client_id: 'https://nowhere.example/client.json'))

      assert_nil outcome.back
      refute_nil outcome.page
    end

    it 'asks to send the person back to an address the app does not list' do
      outcome = OauthRequest.check(params(redirect_uri: 'http://localhost:4000/elsewhere'))

      assert_nil outcome.back
      refute_nil outcome.page
    end
  end

  describe 'a request it sends back refused' do
    it 'asks for anything but a code' do
      assert_equal 'unsupported_response_type', sent_back(OauthRequest.check(params(response_type: 'token'))).last['error']
    end

    it 'comes without an S256 challenge, or with one that is not one' do
      [{ code_challenge: nil }, { code_challenge_method: 'plain' }, { code_challenge_method: nil },
       { code_challenge: 'short' }, { code_challenge: "#{'a' * 43}!" }].each do |change|
        assert_equal 'invalid_request', sent_back(OauthRequest.check(params(**change))).last['error'], change.inspect
      end
    end

    it 'asks for anything but this install\'s MCP endpoint' do
      assert_equal 'invalid_target', sent_back(OauthRequest.check(params(resource: 'https://elsewhere.example/mcp'))).last['error']
      assert_equal 'invalid_target', sent_back(OauthRequest.check(params(resource: nil))).last['error']
    end

    it 'asks for a scope it does not offer' do
      assert_equal 'invalid_scope', sent_back(OauthRequest.check(params(scope: 'mainline:read mainline:write'))).last['error']
    end
  end

  describe 'sending the person back' do
    it 'sends them to the address asked for, with the answer, the state, and Mainline as issuer' do
      outcome = OauthRequest.check(params(response_type: 'token'))

      assert_instance_of String, outcome.back
      assert_equal ['http://localhost:4000/callback',
                    { 'error' => 'unsupported_response_type', 'state' => 'abc', 'iss' => ENV.fetch('BASE_URL') }],
        sent_back(outcome)
    end

    it 'keeps what the address already asks, and leaves out a state that was not given' do
      publish(@client, 'Claude Code', ['http://localhost/callback?from=agent'])
      request = OauthRequest.check(params(redirect_uri: 'http://localhost:9/callback?from=agent', state: nil)).request

      uri = URI(OauthRequest.back(request, code: 'xyz'))

      assert_equal [%w[from agent], %w[code xyz], ['iss', ENV.fetch('BASE_URL')]], URI.decode_www_form(uri.query)
    end
  end
end
