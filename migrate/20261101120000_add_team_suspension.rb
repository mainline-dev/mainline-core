# frozen_string_literal: true

# A team can be suspended: its pages, MCP and deploy API close until the
# suspension is lifted. The message is shown to the account holder, who is
# sent to the link when one is set. Core sets none of these itself.
#
# The first migration named by timestamp: from here on Sequel's timestamp
# migrator runs, after recording the numbered migrations already applied.
Sequel.migration do
  change do
    alter_table(:teams) do
      add_column :suspended_at, 'timestamptz'
      add_column :suspended_message, :text
      add_column :suspended_link, String, size: 500
    end
  end
end
