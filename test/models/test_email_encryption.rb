# test/models/test_email_encryption.rb
# frozen_string_literal: true

require_relative '../model_spec_helper'

describe 'Email encryption' do
  cover 'EncryptedEmail*'
  describe Person do
    it 'encrypts email at rest' do
      person = Person.create(name: 'Alice', email: 'alice@acme.co')
      raw = DB[:people].where(id: person.id).first

      refute_equal 'alice@acme.co', raw[:email_ciphertext]
      refute_nil raw[:email_ciphertext]
    end

    it 'decrypts email on read' do
      person = Person.create(name: 'Alice', email: 'alice@acme.co')

      assert_equal 'alice@acme.co', person.email
      assert_equal 'alice@acme.co', Person[person.id].email
    end

    it 'finds by email via blind index' do
      person = Person.create(name: 'Alice', email: 'alice@acme.co')
      found = Person.find_by_email('alice@acme.co')

      assert_equal person.id, found.id
    end

    it 'returns nil for unknown email' do
      assert_nil Person.find_by_email('nobody@acme.co')
    end

    it 'enforces unique email via blind index' do
      Person.create(name: 'Alice', email: 'alice@acme.co')

      assert_raises(Sequel::UniqueConstraintViolation, Sequel::ValidationFailed) do
        Person.create(name: 'Also Alice', email: 'alice@acme.co')
      end
    end
  end

  describe Invitation do
    before do
      @team = Team.create(name: 'Test')
      SetTeamContext.call(@team.id)
      @person = Person.create(name: 'Alice', email: 'alice@acme.co')
    end

    it 'encrypts email at rest' do
      inv = Invitation.create(
        team_id: @team.id, email: 'bob@acme.co',
        token: SecureRandom.urlsafe_base64(32),
        invited_by: @person.id, expires_at: Time.now + 86_400
      )
      raw = DB[:invitations].where(id: inv.id).first

      refute_equal 'bob@acme.co', raw[:email_ciphertext]
      refute_nil raw[:email_ciphertext]
    end

    it 'decrypts email on read' do
      inv = Invitation.create(
        team_id: @team.id, email: 'bob@acme.co',
        token: SecureRandom.urlsafe_base64(32),
        invited_by: @person.id, expires_at: Time.now + 86_400
      )

      assert_equal 'bob@acme.co', inv.email
    end

    it 'finds by email via blind index' do
      inv = Invitation.create(
        team_id: @team.id, email: 'bob@acme.co',
        token: SecureRandom.urlsafe_base64(32),
        invited_by: @person.id, expires_at: Time.now + 86_400
      )
      found = Invitation.find_by_email('bob@acme.co')

      assert_equal inv.id, found.id
    end
  end

  describe PersonIdentity do
    it 'encrypts email at rest' do
      person = Person.create(name: 'Alice', email: 'alice@acme.co')
      identity = PersonIdentity.create(
        person_id: person.id, provider: 'google',
        provider_subject: '123', email: 'alice@acme.co'
      )
      raw = DB[:person_identities].where(id: identity.id).first

      refute_equal 'alice@acme.co', raw[:email_ciphertext]
      refute_nil raw[:email_ciphertext]
    end

    it 'decrypts email on read' do
      person = Person.create(name: 'Alice', email: 'alice@acme.co')
      identity = PersonIdentity.create(
        person_id: person.id, provider: 'google',
        provider_subject: '123', email: 'alice@acme.co'
      )

      assert_equal 'alice@acme.co', identity.email
    end
  end
end
