# frozen_string_literal: true

class MonitoredRepo < Sequel::Model
  many_to_one :team

  def repo_name
    @repo_name ||= Lockbox.new(key: Lockbox.master_key, encode: true)
      .decrypt(repo_name_ciphertext)
  end

  def repo_name=(val)
    @repo_name = val
    box = Lockbox.new(key: Lockbox.master_key, encode: true)
    self.repo_name_ciphertext = box.encrypt(val)
    self.repo_name_bidx = BlindIndex.generate_bidx(val, key: Lockbox.master_key)
  end

  def self.find_by_repo_name(name)
    bidx = BlindIndex.generate_bidx(name, key: Lockbox.master_key)
    where(repo_name_bidx: bidx).first
  end
end
