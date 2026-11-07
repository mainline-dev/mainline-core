# frozen_string_literal: true

Sequel.migration do
  up do
    drop_table(:team_holidays)
  end

  down do
    create_table(:team_holidays) do
      foreign_key :team_id, :teams, type: :uuid, null: false
      Date :holiday_date, null: false
      String :name, null: false
      primary_key [:team_id, :holiday_date]
    end

    run "ALTER TABLE team_holidays ENABLE ROW LEVEL SECURITY"
    run "CREATE POLICY team_isolation ON team_holidays USING (team_id = current_setting('app.current_team_id')::uuid)"
  end
end
