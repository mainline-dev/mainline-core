# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/email_signup'

describe EmailSignup do
  cover 'EmailSignup*'

  def sign_up(name: 'Alice Example', email: 'alice@signup.co', password: 'correct horse battery')
    EmailSignup.call(name: name, email: email, password: password)
  end

  def identities(person)
    PersonIdentity.where(person_id: person.id).all
  end

  it 'makes the person, with an email identity that knows their password and keeps only its digest' do
    result = sign_up
    identity = identities(result.person).first

    assert_nil result.error
    assert_equal ['Alice Example', 'alice@signup.co'], [result.person.name, result.person.email]
    assert_equal ['email', 'alice@signup.co', 1], [identity.provider, identity.email, identities(result.person).size]
    assert_equal BlindIndex.generate_bidx('alice@signup.co', key: Lockbox.master_key), identity.provider_subject
    assert BCrypt::Password.new(identity.password_digest).is_password?('correct horse battery')
    refute_includes identity.password_digest, 'correct horse battery'
    assert_equal EmailSignup::COST, BCrypt::Password.new(identity.password_digest).cost
  end

  it 'takes the shortest and longest names, passwords and addresses it allows' do
    longest_email = "#{'a' * 244}@signup.co"

    made = [sign_up(name: 'Al', email: 'a@signup.co', password: 'p' * 12),
            sign_up(name: 'A' * 100, email: longest_email, password: 'p' * 70)]

    assert_equal [nil, nil], made.map(&:error)
    assert_equal 254, longest_email.length
  end

  it 'refuses details that will not do, saying what is wrong, and makes nobody' do
    refused = { name: ['A', 'A' * 101], email: ['', 'alice', 'alice@signup', 'a b@signup.co', "#{'a' * 245}@signup.co"],
                password: ['p' * 11, 'p' * 71] }.flat_map { |field, values|
      values.map { |value| sign_up(field => value) }
    }
    said = refused.map(&:error)

    assert_equal [nil], refused.map(&:person).uniq
    assert(said.all? { |error| error.is_a?(String) && !error.empty? })
    assert_equal 7, said.uniq.size
    assert_equal 0, Person.count
  end

  it 'says what is wrong with the name before the address, and with the address before the password' do
    everything_wrong = sign_up(name: 'A', email: 'alice', password: 'short')
    address_and_password = sign_up(email: 'alice', password: 'short')

    assert_equal sign_up(name: 'A').error, everything_wrong.error
    assert_equal sign_up(email: 'alice').error, address_and_password.error
  end

  it 'refuses an address someone already has, and makes no second person' do
    sign_up

    again = sign_up(name: 'Another Alice')

    assert_equal [nil, 1], [again.person, Person.count]
    refute_empty again.error.to_s
    refute_equal sign_up(email: 'alice').error, again.error
  end

  it 'says what is wrong with a password by itself, for changing one later' do
    assert_equal [nil, nil], [EmailSignup.password_error('p' * 12), EmailSignup.password_error('p' * 70)]
    assert_equal sign_up(password: 'p' * 11).error, EmailSignup.password_error('p' * 11)
    assert_equal sign_up(password: 'p' * 71).error, EmailSignup.password_error('p' * 71)
    refute_equal EmailSignup.password_error('p' * 11), EmailSignup.password_error('p' * 71)
  end
end
