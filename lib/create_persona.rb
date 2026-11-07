# frozen_string_literal: true

require_relative 'record_event'

module CreatePersona
  Result = Struct.new(:success?, :errors, :persona, keyword_init: true)

  def self.call(map:, team:, actor:, name:, description:)
    errors = validate(name)
    return Result.new(success?: false, errors: errors) unless errors.empty?

    persona = nil
    DB.transaction do
      position = (Persona.where(map_id: map.id).max(:position) || 0) + 1000
      persona = Persona.create(map_id: map.id, team_id: team.id, name: name, description: description, position: position)
      RecordEvent.call(
        actor_id:    actor.id,
        entity:      persona,
        action:      'created',
        after_state: { name: persona.name, position: persona.position }
      )
    end

    Result.new(success?: true, errors: [], persona: persona)
  end

  def self.validate(name)
    errors = []
    errors << 'Name is required' unless name
    errors << 'Name must be 100 characters or fewer' if name && name.length > 100
    errors
  end
  private_class_method :validate
end
