# models/invitation.rb
# frozen_string_literal: true

class Invitation < Sequel::Model
  include EncryptedEmail

  many_to_one :team
end
