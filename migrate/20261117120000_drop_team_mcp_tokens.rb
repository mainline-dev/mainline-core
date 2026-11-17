# frozen_string_literal: true

# Team tokens are retired: a coding agent reads at /mcp with its person's
# personal token, or an app's sign-in. The old tokens' hashes go with the
# column.
Sequel.migration do
  up do
    drop_column :teams, :mcp_token
  end

  down do
    add_column :teams, :mcp_token, :text
  end
end
