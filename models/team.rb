# models/team.rb
# frozen_string_literal: true

class Team < Sequel::Model
  one_to_many :maps
  one_to_many :team_memberships
  one_to_many :people, through: :team_memberships, class: :Person
  many_to_one :creator, class: :Person

  def validate
    super
    validates_max_length 100, :name
  end

  def suspended?
    !suspended_at.nil?
  end

  # Where to send the account holder of a suspended team: the suspension's
  # link when it is a path on this site, otherwise the account page.
  def suspension_destination
    link = suspended_link.to_s
    link.start_with?('/') && !link.start_with?('//') ? link : "/teams/#{id}/account"
  end
end
