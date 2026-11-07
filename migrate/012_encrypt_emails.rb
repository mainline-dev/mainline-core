# frozen_string_literal: true

require_relative '../lib/lockbox_setup'

Sequel.migration do
  up do
    # -- Add encrypted columns --

    alter_table(:people) do
      add_column :email_ciphertext, :text
      add_column :email_bidx, :text
    end

    alter_table(:person_identities) do
      add_column :email_ciphertext, :text
    end

    alter_table(:invitations) do
      add_column :email_ciphertext, :text
      add_column :email_bidx, :text
    end

    # -- Backfill from plaintext --

    lockbox = Lockbox.new(key: Lockbox.master_key, encode: true)

    from(:people).each do |row|
      ciphertext = lockbox.encrypt(row[:email])
      bidx = BlindIndex.generate_bidx(row[:email], key: Lockbox.master_key)
      from(:people).where(id: row[:id]).update(
        email_ciphertext: ciphertext,
        email_bidx: bidx
      )
    end

    from(:person_identities).each do |row|
      ciphertext = lockbox.encrypt(row[:email])
      from(:person_identities).where(id: row[:id]).update(
        email_ciphertext: ciphertext
      )
    end

    from(:invitations).each do |row|
      ciphertext = lockbox.encrypt(row[:email])
      bidx = BlindIndex.generate_bidx(row[:email], key: Lockbox.master_key)
      from(:invitations).where(id: row[:id]).update(
        email_ciphertext: ciphertext,
        email_bidx: bidx
      )
    end

    # -- Drop plaintext columns and add indexes --

    alter_table(:people) do
      drop_column :email
      set_column_not_null :email_ciphertext
      add_unique_constraint :email_bidx, name: :people_email_bidx_unique
    end

    alter_table(:person_identities) do
      drop_column :email
      set_column_not_null :email_ciphertext
    end

    alter_table(:invitations) do
      drop_column :email
      set_column_not_null :email_ciphertext
      add_index :email_bidx, name: :idx_invitations_email_bidx
    end
  end

  down do
    alter_table(:people) do
      add_column :email, 'citext'
    end

    alter_table(:person_identities) do
      add_column :email, 'citext'
    end

    alter_table(:invitations) do
      add_column :email, 'citext'
    end

    lockbox = Lockbox.new(key: Lockbox.master_key, encode: true)

    from(:people).each do |row|
      email = lockbox.decrypt(row[:email_ciphertext])
      from(:people).where(id: row[:id]).update(email: email)
    end

    from(:person_identities).each do |row|
      email = lockbox.decrypt(row[:email_ciphertext])
      from(:person_identities).where(id: row[:id]).update(email: email)
    end

    from(:invitations).each do |row|
      email = lockbox.decrypt(row[:email_ciphertext])
      from(:invitations).where(id: row[:id]).update(email: email)
    end

    alter_table(:people) do
      set_column_not_null :email
      add_unique_constraint :email, name: :people_email_key
      drop_column :email_ciphertext
      drop_column :email_bidx
    end

    alter_table(:person_identities) do
      set_column_not_null :email
      drop_column :email_ciphertext
    end

    alter_table(:invitations) do
      set_column_not_null :email
      drop_column :email_ciphertext
      drop_column :email_bidx
    end
  end
end
