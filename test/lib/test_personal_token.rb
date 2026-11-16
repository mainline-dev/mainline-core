# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../../lib/personal_token'

describe PersonalToken do
  cover 'PersonalToken*'

  it 'makes a token that says what it is, with a random part and a checksum after it' do
    token = PersonalToken.generate

    assert_match(/\Amainline_pat_[0-9A-Za-z]{38}\z/, token)
    assert PersonalToken.well_formed?(token)
  end

  it 'makes a different token each time' do
    refute_equal PersonalToken.generate, PersonalToken.generate
  end

  it 'knows a token whose checksum does not match is not one of its own' do
    token = PersonalToken.generate
    changed = token[0...-7] + (token[-7] == 'a' ? 'b' : 'a') + token[-6..]

    refute PersonalToken.well_formed?(changed)
  end

  it 'knows anything else is not one of its own' do
    token = PersonalToken.generate

    refute PersonalToken.well_formed?(token.sub('mainline_pat_', 'mainline_xyz_'))
    refute PersonalToken.well_formed?("#{token}0")
    refute PersonalToken.well_formed?(token[0...-1])
    refute PersonalToken.well_formed?(token.sub(/\Amainline_pat_./, 'mainline_pat_-'))
    refute PersonalToken.well_formed?(nil)
  end

  it 'ends a token with a checksum anyone can compute from its random part' do
    token = PersonalToken.generate

    assert_equal '2wjyrI', PersonalToken.checksum('0' * 32)
    assert_equal '1uMZOC', PersonalToken.checksum('aB3dE5gH7jK9mN1pQ3sT5vW7yZ9bC2eF')
    assert_equal PersonalToken.checksum(token[13, 32]), token[-6..]
  end

  it 'knows a token is not its own without the prefix, or with a stray character, even when the checksum fits' do
    stray = "-#{'a' * 31}"

    refute PersonalToken.well_formed?(PersonalToken.generate.delete_prefix('mainline_pat_'))
    refute PersonalToken.well_formed?("mainline_pat_#{stray}#{PersonalToken.checksum(stray)}")
    refute PersonalToken.well_formed?('mainline_pat_')
  end

  it 'keeps a token only as a SHA-256 digest' do
    assert_equal Digest::SHA256.hexdigest('mainline_pat_x'), PersonalToken.digest('mainline_pat_x')
  end
end
