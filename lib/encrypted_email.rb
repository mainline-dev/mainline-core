# frozen_string_literal: true

module EncryptedEmail
  def email
    @email ||= Lockbox.new(key: Lockbox.master_key, encode: true)
      .decrypt(email_ciphertext)
  end

  def email=(val)
    @email = val
    box = Lockbox.new(key: Lockbox.master_key, encode: true)
    self.email_ciphertext = box.encrypt(val)
    self.email_bidx = BlindIndex.generate_bidx(val, key: Lockbox.master_key) if respond_to?(:email_bidx=)
  end

  module ClassMethods
    def find_by_email(email)
      bidx = BlindIndex.generate_bidx(email, key: Lockbox.master_key)
      where(email_bidx: bidx).first
    end
  end

  def self.included(base)
    base.extend(ClassMethods) if base.columns.include?(:email_bidx)
  end
end
