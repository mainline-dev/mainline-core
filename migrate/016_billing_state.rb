# frozen_string_literal: true

Sequel.migration do
  up do
    add_column :teams, :billing_state, String, default: 'solo', null: false
    add_column :teams, :paddle_subscription_id, String

    drop_column :teams, :stripe_customer_id
    drop_column :teams, :stripe_subscription_id
    drop_column :teams, :subscription_status
    drop_column :teams, :trial_starts_at
    drop_column :teams, :trial_ends_at
    drop_column :teams, :price_cents
    drop_column :teams, :currency

    run <<~SQL
      CREATE OR REPLACE FUNCTION enforce_map_cap()
      RETURNS TRIGGER AS $$
      DECLARE
          active_count integer;
          cap integer;
          state text;
      BEGIN
          SELECT COUNT(*) INTO active_count
          FROM maps
          WHERE team_id = NEW.team_id
            AND archived_at IS NULL;

          SELECT billing_state INTO state
          FROM teams
          WHERE id = NEW.team_id;

          IF state IN ('active', 'trialing', 'past_due') THEN
              SELECT 10 + (COALESCE(map_pack_count, 0) * 10) INTO cap
              FROM teams
              WHERE id = NEW.team_id;
          ELSE
              cap := 3;
          END IF;

          IF active_count >= cap THEN
              RAISE EXCEPTION 'Team has reached the maximum of % active maps', cap;
          END IF;

          RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
    SQL
  end

  down do
    run <<~SQL
      CREATE OR REPLACE FUNCTION enforce_map_cap()
      RETURNS TRIGGER AS $$
      DECLARE
          active_count integer;
          cap integer;
      BEGIN
          SELECT COUNT(*) INTO active_count
          FROM maps
          WHERE team_id = NEW.team_id
            AND archived_at IS NULL;

          SELECT 10 + (COALESCE(map_pack_count, 0) * 10) INTO cap
          FROM teams
          WHERE id = NEW.team_id;

          IF active_count >= cap THEN
              RAISE EXCEPTION 'Team has reached the maximum of % active maps', cap;
          END IF;

          RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
    SQL

    drop_column :teams, :paddle_subscription_id
    drop_column :teams, :billing_state

    add_column :teams, :stripe_customer_id, String
    add_column :teams, :stripe_subscription_id, String
    add_column :teams, :subscription_status, String
    add_column :teams, :trial_starts_at, 'timestamp with time zone'
    add_column :teams, :trial_ends_at, 'timestamp with time zone'
    add_column :teams, :price_cents, Integer
    add_column :teams, :currency, 'character(3)'
  end
end
