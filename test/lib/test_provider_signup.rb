# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/provider_signup'

describe ProviderSignup do
  cover 'ProviderSignup*'

  def pending
    { 'name' => 'Alice Example', 'email' => 'alice@provider.co', 'provider' => 'github', 'uid' => 'gh-42',
      'oauth_token' => 'the-providers-own-token' }
  end

  def unreadable
    [SignedState.generate('oauth-verify:not base64, not json!'),
     SignedState.generate("oauth-verify:#{Base64.urlsafe_encode64('not json')}")]
  end

  # Links of another kind, and text that only starts like one of these links
  # or has had its signature changed.
  def not_such_links
    genuine = ProviderSignup.link_token(pending)
    [SignedState.generate('verify:00000000-0000-4000-8000-000000000000'), 'oauth-verify:eyJuYW1lIjoiQSJ9',
     "#{genuine[0..-2]}#{genuine[-1] == '0' ? '1' : '0'}", 'not-a-link', '']
  end

  it "carries a pending sign-up in its link, without the provider's own token" do
    token = ProviderSignup.link_token(pending)

    assert ProviderSignup.link?(token)
    assert_equal pending.except('oauth_token'), ProviderSignup.pending_from(token)
  end

  it 'carries what a pending sign-up has, in a link with no padding, whatever the length of the name' do
    tokens = %w[A Al Ali].map { |name| ProviderSignup.link_token(pending.merge('name' => name).except('uid')) }
    carried = tokens.map { |token| ProviderSignup.pending_from(token).values_at('name', 'uid') }

    assert_equal [['A', nil], ['Al', nil], ['Ali', nil]], carried
    assert(tokens.none? { |token| token.include?('=') })
  end

  it 'knows its own links from links of another kind and from anything that is no link' do
    its_own = unreadable.map { |token| ProviderSignup.link?(token) }
    others = not_such_links.map { |token| ProviderSignup.link?(token) }

    assert_equal [[true, true], [false, false, false, false, false]], [its_own, others]
  end

  it 'reads no pending sign-up from a link it cannot read, or from anything that is not such a link' do
    read = (unreadable + not_such_links).map { |token| ProviderSignup.pending_from(token) }

    assert_equal [nil], read.uniq
  end

  it 'makes the person with their address already verified, and the identity their provider knows them by' do
    now = Time.utc(2030, 1, 7, 9)

    person = ProviderSignup.create(pending, email: 'alice@work.co', now: now)
    identities = PersonIdentity.where(person_id: person.id).all.map { |identity|
      [identity.provider, identity.provider_subject, identity.email, identity.password_digest]
    }

    assert_equal ['Alice Example', 'alice@work.co', now], [person.name, person.email, person.refresh.email_verified_at]
    assert_equal [['github', 'gh-42', 'alice@work.co', nil]], identities
  end
end
