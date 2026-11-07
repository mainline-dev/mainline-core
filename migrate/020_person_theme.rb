# frozen_string_literal: true

Sequel.migration do
  up do
    add_column :people, :theme, String
  end

  down do
    drop_column :people, :theme
  end
end
