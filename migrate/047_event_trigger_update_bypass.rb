# frozen_string_literal: true

Sequel.migration do
  up do
    run <<~SQL
      CREATE OR REPLACE FUNCTION prevent_event_mutation()
      RETURNS TRIGGER AS $$
      BEGIN
          IF TG_OP = 'DELETE' AND current_setting('app.allow_team_deletion', true) = 'true' THEN
              RETURN OLD;
          END IF;
          IF TG_OP = 'UPDATE' AND current_setting('app.rls_bypass', true) = 'true' THEN
              RETURN NEW;
          END IF;
          RAISE EXCEPTION 'events table is append-only: % not allowed', TG_OP;
          RETURN NULL;
      END;
      $$ LANGUAGE plpgsql;
    SQL
  end

  down do
    run <<~SQL
      CREATE OR REPLACE FUNCTION prevent_event_mutation()
      RETURNS TRIGGER AS $$
      BEGIN
          IF TG_OP = 'DELETE' AND current_setting('app.allow_team_deletion', true) = 'true' THEN
              RETURN OLD;
          END IF;
          RAISE EXCEPTION 'events table is append-only: % not allowed', TG_OP;
          RETURN NULL;
      END;
      $$ LANGUAGE plpgsql;
    SQL
  end
end
