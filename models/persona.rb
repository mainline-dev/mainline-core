# models/persona.rb
# frozen_string_literal: true

class Persona < Sequel::Model
  many_to_one :map
  many_to_one :team
  many_to_many :activities, join_table: :activity_personas

  def validate
    super
    validates_presence [:name, :map_id, :team_id]
    validates_max_length 100, :name
  end
end
