# lib/record_event.rb
# frozen_string_literal: true

module RecordEvent
  # Call inside a DB.transaction block.
  #
  # Usage:
  #   RecordEvent.call(
  #     actor_id:    person.id,
  #     entity:      persona,          # any Sequel::Model with team_id
  #     action:      'created',
  #     after_state: { name: persona.name, position: persona.position }
  #   )
  #
  def self.entity_type_for(model_class)
    model_class.table_name.to_s.gsub(/s$/, '')
  end

  def self.call(actor_id:, entity:, action:, before_state: {}, after_state: {},
                map_id: nil, correlation_id: nil, team_id: nil)
    Event.create(
      team_id:        team_id || entity.team_id,
      map_id:         map_id || (entity.respond_to?(:map_id) ? entity.map_id : nil),
      actor_id:       actor_id,
      occurred_at:    Time.now,
      entity_type:    entity_type_for(entity.class),
      entity_id:      entity.id,
      action:         action.to_s,
      before_state:   Sequel.pg_jsonb(before_state),
      after_state:    Sequel.pg_jsonb(after_state),
      correlation_id: correlation_id
    )
  end
end
