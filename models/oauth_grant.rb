# frozen_string_literal: true

class OauthGrant < Sequel::Model
  many_to_one :person
end
