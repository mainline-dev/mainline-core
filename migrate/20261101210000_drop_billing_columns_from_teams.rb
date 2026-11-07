# frozen_string_literal: true

# Billing has no place in core. Earlier migrations left plan and limit
# columns on teams; hosted billing keeps its own records and has already
# dropped them where it runs, so this only clears them where it does not.
Sequel.migration do
  up do
    run <<~SQL
      ALTER TABLE teams
        DROP COLUMN IF EXISTS billing_state,
        DROP COLUMN IF EXISTS paddle_subscription_id,
        DROP COLUMN IF EXISTS trial_ends_at,
        DROP COLUMN IF EXISTS person_cap,
        DROP COLUMN IF EXISTS map_pack_count,
        DROP COLUMN IF EXISTS member_limit,
        DROP COLUMN IF EXISTS map_limit
    SQL
  end

  down do
    # Core never used these columns; nothing to restore.
  end
end
