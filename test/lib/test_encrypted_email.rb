# frozen_string_literal: true

require_relative '../model_spec_helper'

describe EncryptedEmail do
  cover 'EncryptedEmail*'
  before do
    @person = Person.create(name: 'Alice', email: 'alice@test.co')
  end

  it 'encrypts email into ciphertext column' do
    raw = DB[:people].where(id: @person.id).first

    refute_equal 'alice@test.co', raw[:email_ciphertext]
    refute_nil raw[:email_ciphertext]
  end

  it 'decrypts email on read' do
    assert_equal 'alice@test.co', Person[@person.id].email
  end

  it 'generates blind index for lookup' do
    raw = DB[:people].where(id: @person.id).first

    refute_nil raw[:email_bidx]
  end

  it 'finds record by email via blind index' do
    found = Person.find_by_email('alice@test.co')

    assert_equal @person.id, found.id
  end

  it 'returns nil for unknown email' do
    assert_nil Person.find_by_email('nobody@test.co')
  end

  it 'skips blind index when column is absent' do
    identity = PersonIdentity.create(
      person_id: @person.id, provider: 'google',
      provider_subject: '123', email: 'alice@test.co'
    )

    assert_equal 'alice@test.co', identity.email
    refute_respond_to PersonIdentity, :find_by_email
  end

  it 'round-trips email update' do
    @person.email = 'new@test.co'
    @person.save_changes

    assert_equal 'new@test.co', Person[@person.id].email
    assert_equal @person.id, Person.find_by_email('new@test.co').id
    assert_nil Person.find_by_email('alice@test.co')
  end
end
