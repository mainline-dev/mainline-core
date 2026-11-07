# models/activity_persona.rb
# frozen_string_literal: true

class ActivityPersona < Sequel::Model(:activity_personas)
  unrestrict_primary_key # composite PK: let us set both columns

  many_to_one :activity
  many_to_one :persona
end
