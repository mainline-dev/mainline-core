# models/person.rb
# frozen_string_literal: true

class Person < Sequel::Model
  include EncryptedEmail

  many_to_one :actor
  one_to_many :team_memberships

  def before_validation
    self.actor_id ||= Actor.create(kind: 'person', name: name).id if new?
    super
  end
end
