# frozen_string_literal: true

Sequel.migration do
  up do
    add_column :teams, :mcp_token, :text
  end

  down do
    drop_column :teams, :mcp_token
  end
end
