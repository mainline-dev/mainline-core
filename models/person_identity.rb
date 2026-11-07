# frozen_string_literal: true

class PersonIdentity < Sequel::Model
  include EncryptedEmail

  many_to_one :person
end
