# frozen_string_literal: true

Sequel.migration do
  up do
    alter_table(:stories) do
      set_column_allow_null :created_by_id
    end

    alter_table(:invitations) do
      set_column_allow_null :invited_by
    end
  end

  down do
    alter_table(:stories) do
      set_column_not_null :created_by_id
    end

    alter_table(:invitations) do
      set_column_not_null :invited_by
    end
  end
end
