# frozen_string_literal: true

Sequel.migration do
  up do
    alter_table(:monitored_repos) do
      set_column_default :threshold_hours, 24
    end
    from(:monitored_repos).where { threshold_hours > 24 }.update(threshold_hours: 24)
  end

  down do
    alter_table(:monitored_repos) do
      set_column_default :threshold_hours, 72
    end
  end
end
