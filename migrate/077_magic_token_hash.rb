# frozen_string_literal: true

Sequel.migration do
  up do
    add_column :people, :last_magic_token_hash, String
  end

  down do
    drop_column :people, :last_magic_token_hash
  end
end
