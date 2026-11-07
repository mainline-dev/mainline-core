# frozen_string_literal: true

class TrackedBranch < Sequel::Model
  many_to_one :monitored_repo

  def branch_name
    @branch_name ||= Lockbox.new(key: Lockbox.master_key, encode: true)
      .decrypt(branch_name_ciphertext)
  end

  def branch_name=(val)
    @branch_name = val
    box = Lockbox.new(key: Lockbox.master_key, encode: true)
    self.branch_name_ciphertext = box.encrypt(val)
    self.branch_name_bidx = BlindIndex.generate_bidx(val, key: Lockbox.master_key)
  end
end
