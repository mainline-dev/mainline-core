# frozen_string_literal: true

# Who may create an account on this install. SIGNUPS=open lets anyone. Any
# other value closes sign-ups, so a typo can't leave a public install open:
# then only the first person, who needs a way in, and people with a live
# invitation for that address can.
module Signups
  def self.open?
    ENV.fetch('SIGNUPS') == 'open'
  end

  def self.first_person?
    Person.empty?
  end

  # Whether to show the sign-up form, before anyone has given an address.
  def self.available?(invite_token:)
    open? || first_person? || !Invitation.pending(invite_token).nil?
  end

  def self.allowed?(email:, invite_token:)
    open? || first_person? || invited?(email, invite_token)
  end

  def self.invited?(email, invite_token)
    invitation = Invitation.pending(invite_token)
    !invitation.nil? && invitation.email_bidx == BlindIndex.generate_bidx(email, key: Lockbox.master_key)
  end
  private_class_method :invited?
end
