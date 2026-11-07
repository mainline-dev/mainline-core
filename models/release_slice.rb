# frozen_string_literal: true

class ReleaseSlice < Sequel::Model
  many_to_one :map
  many_to_one :team
  one_to_many :stories

  def validate
    super
    validates_presence [:name, :map_id, :team_id]
    validates_max_length 100, :name
  end
end
