# models/event.rb
# frozen_string_literal: true

class Event < Sequel::Model
  # event_no is GENERATED ALWAYS AS IDENTITY -- Postgres generates it on insert.
  # Sequel sees NOT NULL + no default, so auto_validations rejects nil values.
  # Remove event_no from the auto-validation not-null list.
  @auto_validate_not_null_columns -= [:event_no] if @auto_validate_not_null_columns

  many_to_one :team
  many_to_one :actor, class: :Actor, key: :actor_id

  # Events are append-only. No updates, no deletes.
  # The DB trigger enforces this too, but fail fast in Ruby.
  def before_update
    raise Sequel::Error, 'Events are append-only'
  end

  def before_destroy
    raise Sequel::Error, 'Events are append-only'
  end
end
