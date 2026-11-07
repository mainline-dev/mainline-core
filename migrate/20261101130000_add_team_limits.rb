# frozen_string_literal: true

# Optional limits on a team's working members and active maps. Empty means
# unlimited. Core enforces them; it never sets them itself.
Sequel.migration do
  change do
    alter_table(:teams) do
      add_column :member_limit, Integer
      add_column :map_limit, Integer
    end
  end
end
