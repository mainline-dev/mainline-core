# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../../lib/csrf_check'

describe CsrfCheck do
  cover 'CsrfCheck*'

  after { CsrfCheck.in_tests = false }

  it 'checks every request outside tests, whatever the test switch says' do
    [false, true].each do |switch|
      CsrfCheck.in_tests = switch

      assert CsrfCheck.on?('RACK_ENV' => 'production'), "switch #{switch}"
      assert CsrfCheck.on?('RACK_ENV' => 'development'), "switch #{switch}"
      assert CsrfCheck.on?({}), "switch #{switch}"
    end
  end

  it 'is off in tests until a test turns it on' do
    refute CsrfCheck.on?('RACK_ENV' => 'test')

    CsrfCheck.in_tests = true

    assert CsrfCheck.on?('RACK_ENV' => 'test')
  end

  it 'looks at the environment the app runs in by default' do
    CsrfCheck.in_tests = false

    refute_predicate CsrfCheck, :on?
  end

  it 'skips the paths machines call, and the sign-in providers coming back' do
    %w[/mcp /mcp/00000000-0000-4000-8000-000000000000 /oauth/token /oauth/revoke /api/teams/x/deploys
       /webhooks/github /.well-known/oauth-authorization-server /auth/github/callback].each do |path|
      assert CsrfCheck.skips?(path), "#{path} is skipped"
    end
  end

  it 'checks the forms people post, including the one that connects a coding agent' do
    %w[/oauth/authorize /login /forgot-password /mcp-server /teams].each do |path|
      refute CsrfCheck.skips?(path), "#{path} is checked"
    end
  end
end
