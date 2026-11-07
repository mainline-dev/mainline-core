# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/remove_unverified_accounts'

describe RemoveUnverifiedAccounts do
  cover 'RemoveUnverifiedAccounts*'

  def days(count)
    count * 24 * 60 * 60
  end

  def signup(email, days_ago:, verified: false, provider: 'email')
    person = Person.create(name: 'Test', email: email)
    person.this.update(created_at: Time.now - days(days_ago), email_verified_at: (Time.now if verified))
    PersonIdentity.create(person_id: person.id, provider: provider, provider_subject: "#{provider}-#{email}", email: email)
    person
  end

  def remove
    RemoveUnverifiedAccounts.call(before: Time.now - days(7))
  end

  it 'removes email signups never verified for over a week, with their identities' do
    bot = signup('bot@acme.co', days_ago: 8)

    assert_equal 1, remove
    assert_nil Person[bot.id]
    assert_empty PersonIdentity.where(person_id: bot.id).all
  end

  it 'keeps the verified, the recent, anyone who joined a team, and anyone who signed in another way' do
    verified = signup('verified@acme.co', days_ago: 30, verified: true)
    recent = signup('recent@acme.co', days_ago: 6)
    invited = signup('invited@acme.co', days_ago: 30)
    team = Team.create(name: 'Acme')
    TeamMembership.create(team_id: team.id, person_id: invited.id, left_at: Time.now)
    oauth = signup('oauth@acme.co', days_ago: 30)
    PersonIdentity.create(person_id: oauth.id, provider: 'github', provider_subject: 'gh-1', email: 'oauth@acme.co')
    github_only = signup('github@acme.co', days_ago: 30, provider: 'github')

    assert_equal 0, remove
    assert_equal 5, Person.where(id: [verified, recent, invited, oauth, github_only].map(&:id)).count
  end
end
