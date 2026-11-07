# frozen_string_literal: true

Sequel.migration do
  change do
    add_column :teams, :split_threshold_seconds, Float
  end
end
