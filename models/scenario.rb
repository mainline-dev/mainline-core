# frozen_string_literal: true

class Scenario < Sequel::Model
  many_to_one :story

  def validate
    super
    validates_presence %i[story_id given_text when_text then_text position]
    validates_max_length 100, %i[given_text when_text then_text]
    validates_max_length 80, :name, allow_nil: true
  end

  # What a scenario is called. One written before scenarios had names goes by
  # its Then line until someone names it.
  def display_name
    name.to_s.empty? ? then_text : name
  end
end
