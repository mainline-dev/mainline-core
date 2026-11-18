# frozen_string_literal: true

require 'uri'
require_relative 'client_metadata'
require_relative 'oauth_metadata'

# A coding agent's request to sign in, as /oauth/authorize receives it. The
# app is identified by its client metadata document, and may only send the
# person back to an address that document lists; if either fails, the answer
# is a page, and the app is sent nothing. Anything else wrong goes back to
# the app as an OAuth error. Every answer sent back carries the state the app
# gave and Mainline as the issuer.
module OauthRequest
  SCOPES = %w[mainline:read offline_access].freeze
  # An S256 challenge: a SHA-256 hash in unpadded base64url, 43 characters.
  CHALLENGE = /\A[A-Za-z0-9_-]{43}\z/

  Request = Struct.new(:client_id, :redirect_uri, :state, :challenge, :resource, :name, :recognised, keyword_init: true) do
    # How the consent page names the app: by the name its document gives
    # only when it is one Mainline recognises, otherwise by its site.
    def shown_name
      recognised ? name : URI(client_id).host
    end

    def redirect_site
      URI(redirect_uri).host
    end

    # Where the person's answer is sent on to: the scheme, host and port of
    # the address the app goes back to, the port only when it is unusual.
    def return_origin
      uri = URI(redirect_uri)
      port = ":#{uri.port}" unless uri.port == uri.default_port
      "#{uri.scheme}://#{uri.host}#{port}"
    end
  end

  Outcome = Struct.new(:request, :page, :back)

  def self.check(params, from:)
    document = ClientMetadata.fetch(params['client_id'], from: from).document
    return Outcome.new(nil, "Mainline can't identify the app that sent you here, so it can't sign it in.") unless document

    redirect_uri = params['redirect_uri']
    unless ClientMetadata.redirect_allowed?(document, redirect_uri)
      return Outcome.new(nil, 'The app that sent you here asked to send you back to an address it does not list, ' \
                              'so Mainline will not sign it in.')
    end

    request = Request.new(client_id: params['client_id'], redirect_uri: redirect_uri, state: params['state'],
      challenge: params['code_challenge'], resource: params['resource'], name: document['client_name'].to_s,
      recognised: ClientMetadata.recognised?(params['client_id']))
    error = problem(params)
    error ? Outcome.new(nil, nil, back(request, error: error)) : Outcome.new(request)
  end

  def self.problem(params)
    return 'unsupported_response_type' unless params['response_type'] == 'code'
    return 'invalid_request' unless params['code_challenge_method'] == 'S256' && params['code_challenge'].to_s.match?(CHALLENGE)
    return 'invalid_target' unless params['resource'] == OAuthMetadata.protected_resource[:resource]

    'invalid_scope' unless (params['scope'].to_s.split - SCOPES).empty?
  end

  # The address to send the person back to: the one asked for, keeping what
  # it already asks, with the answer, the state given, and Mainline as issuer.
  def self.back(request, **answer)
    uri = URI(request.redirect_uri)
    query = URI.decode_www_form(uri.query.to_s) + answer.to_a
    query << ['state', request.state] if request.state
    query << ['iss', OAuthMetadata.authorization_server.fetch(:issuer)]
    uri.query = URI.encode_www_form(query)
    uri.to_s
  end

  private_class_method :problem
end
