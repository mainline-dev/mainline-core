# frozen_string_literal: true

Sequel.migration do
  up do
    alter_table(:stories) do
      add_column :decoupling_strategy, String
      add_column :decoupling_label, String, size: 50
    end

    run <<~SQL
      ALTER TABLE stories ADD CONSTRAINT valid_decoupling_strategy
        CHECK (decoupling_strategy IS NULL OR decoupling_strategy IN ('flag', 'bba', 'dark_launch'))
    SQL

    run <<~SQL
      ALTER TABLE stories ADD CONSTRAINT decoupling_fields_coherent
        CHECK (
          (decoupling_strategy IS NULL AND decoupling_label IS NULL)
          OR decoupling_strategy IS NOT NULL
        )
    SQL
  end

  down do
    alter_table(:stories) do
      drop_constraint :decoupling_fields_coherent
      drop_constraint :valid_decoupling_strategy
      drop_column :decoupling_label
      drop_column :decoupling_strategy
    end
  end
end
