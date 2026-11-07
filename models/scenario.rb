# frozen_string_literal: true

class Scenario < Sequel::Model
  many_to_one :story

  def validate
    super
    validates_presence %i[story_id given_text when_text then_text position]
    validates_max_length 100, %i[given_text when_text then_text]
  end
end
