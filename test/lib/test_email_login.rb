# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/email_login'
require_relative '../../lib/email_signup'

describe EmailLogin do
  cover 'EmailLogin*'

  before do
    # Someone else with a password of their own, so only Alice's counts for her.
    EmailSignup.call(name: 'Carla Example', email: 'carla@login.co', password: 'another horse battery')
    @alice = EmailSignup.call(name: 'Alice Example', email: 'alice@login.co', password: 'correct horse battery').person
    @bob = Person.create(name: 'Bob', email: 'bob@login.co')
  end

  def sign_in(email, password)
    EmailLogin.person(email: email, password: password)&.id
  end

  def link_for(person)
    SignedState.generate("magic:#{person.id}")
  end

  it 'signs a person in with their address, however it is typed, and their password' do
    as_given = sign_in('alice@login.co', 'correct horse battery')
    loosely_typed = sign_in('  Alice@Login.co ', 'correct horse battery')

    assert_equal [@alice.id, @alice.id], [as_given, loosely_typed]
  end

  it 'signs nobody in with a wrong password, an unknown or missing address, or no password' do
    tried = [['alice@login.co', 'wrong horse battery'], ['carol@login.co', 'correct horse battery'],
             ['', 'correct horse battery'], [nil, 'correct horse battery'], ['alice@login.co', nil]]

    assert_equal [nil], tried.map { |email, password| sign_in(email, password) }.uniq
  end

  it 'signs nobody in by password who has only signed in another way' do
    PersonIdentity.create(person_id: @bob.id, provider: 'google', provider_subject: 'g-1', email: 'bob@login.co')
    PersonIdentity.create(person_id: @bob.id, provider: 'email', provider_subject: 'e-1', email: 'bob@login.co')

    assert_nil sign_in('bob@login.co', '')
  end

  it 'knows whose a login link is, and nobody for anything else' do
    others = [SignedState.generate("verify:#{@alice.id}"), SignedState.generate('magic:00000000-0000-4000-8000-000000000000'),
              'not-a-link', '']

    assert_equal @alice.id, EmailLogin.person_for_link(link_for(@alice)).id
    assert_equal [nil], others.map { |token| EmailLogin.person_for_link(token) }.uniq
  end

  it 'signs its person in with a login link once' do
    link = link_for(@alice)

    first = EmailLogin.use_link(link)
    again = EmailLogin.use_link(link)

    assert_equal [@alice.id, nil], [first.id, again]
    assert_equal Digest::SHA256.hexdigest(link), @alice.refresh.last_magic_token_hash
  end

  it 'signs nobody in with a link another request used after this one read its person' do
    link = link_for(@alice)
    read_before_it_was_used = EmailLogin.person_for_link(link)

    EmailLogin.use_link(link)

    assert_nil EmailLogin.claim(read_before_it_was_used, link)
  end

  it 'signs nobody in with a link that is not one, and remembers nothing' do
    assert_nil EmailLogin.use_link('not-a-link')
    assert_nil @alice.refresh.last_magic_token_hash
  end
end
