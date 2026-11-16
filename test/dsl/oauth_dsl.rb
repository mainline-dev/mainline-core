# frozen_string_literal: true

# A coding agent signing in through /oauth/authorize, as the person's browser
# sees it. Needs the web spec helper and MainlineDSL.
module OauthDsl
  CLAUDE_CODE = 'https://claude.ai/oauth/claude-code-client-metadata'
  # RFC 7636's example: the verifier, and the S256 challenge made from it.
  VERIFIER = 'dBjftJeZ4CVP-mJ92K27uhbUJU1p1r_wW1gFWFOEjXk'
  CHALLENGE = 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM'

  # An app publishes its client metadata document at its client ID.
  def client_publishes(client_id, name:, redirect_uris:)
    driver.publish_client_document(client_id, name: name, redirect_uris: redirect_uris)
  end

  # After a test: documents come from the internet again, none kept.
  def forget_client_documents
    driver.forget_client_documents
  end

  # The app sends the person's browser to sign in, asking for these.
  def start_sign_in(client_id: CLAUDE_CODE, redirect_uri: 'http://localhost:53682/callback', state: 'xyz',
                    challenge: CHALLENGE, method: 'S256', resource: "#{ENV.fetch('BASE_URL')}/mcp", response_type: 'code')
    driver.visit_authorize({ 'response_type' => response_type, 'client_id' => client_id, 'redirect_uri' => redirect_uri,
                             'state' => state, 'code_challenge' => challenge, 'code_challenge_method' => method,
                             'resource' => resource, 'scope' => 'mainline:read' }.compact)
  end

  # What the consent page shows: the app, whether it is recognised or comes
  # with a warning, the site the person goes back to, and each team offered,
  # by name, ticked or not. Nil when no consent page is shown.
  def consent_shown
    driver.consent_shown
  end

  # Approves on the consent page, with the teams given ticked, or as they are.
  def approve_sign_in(teams: nil)
    driver.submit_consent('approve', teams&.map(&:id))
  end

  def deny_sign_in
    driver.submit_consent('deny')
  end

  # Where the browser was sent back to the app: the address, and each
  # parameter. Nil when it was not sent back.
  def sent_back
    driver.sent_back
  end

  # Whether the browser was sent to sign in first.
  def signed_in_first
    driver.sent_to_sign_in?
  end

  # Whether the sign-in was refused on a page of Mainline's own, sending the
  # app nothing.
  def sign_in_refused_on_page?
    driver.sign_in_refused_on_page?
  end

  # The teams, by name, of the last sign-in an app was given, or nil.
  def teams_given_by_last_sign_in
    driver.teams_given_by_last_sign_in
  end
end
