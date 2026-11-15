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

  # Each team has a coding agent from the start, the actor its agent reads are
  # recorded with, so a read never has to create or change anything.
  def before_create
    self.mcp_actor_id ||= Actor.create(kind: 'system', name: 'Coding agent').id
    super
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
