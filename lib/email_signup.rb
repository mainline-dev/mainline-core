# frozen_string_literal: true

require 'bcrypt'

# Signing up with an email address and a password: what is wrong with the
# details given, if anything, and the person made from them, with the email
# identity that holds their password as a digest. Whether sign-ups are open,
# the verification email and any invitation are the app's to see to.
module EmailSignup
  Result = Struct.new(:person, :error, keyword_init: true)
  EMAIL = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/
  COST = 12

  def self.call(name:, email:, password:)
    error = refusal(name, email, password)
    return Result.new(error: error) if error

    Result.new(person: create(name, email, password))
  end

  # What is wrong with a password, if anything. bcrypt reads only so much of
  # one, so a longer one is refused.
  def self.password_error(password)
    if password.length < 12 then 'Password must be at least 12 characters'
    elsif password.length > 70 then 'Password must be 70 characters or fewer'
    end
  end

  def self.refusal(name, email, password)
    if name.length < 2 then 'Name must be at least 2 characters'
    elsif name.length > 100 then 'Name must be 100 characters or fewer'
    elsif email.empty? then 'Email is required'
    elsif !email.match?(EMAIL) then 'Email is not valid'
    elsif email.length > 254 then 'Email is too long'
    elsif (error = password_error(password)) then error
    elsif Person.find_by_email(email) then 'An account with that email already exists'
    end
  end

  def self.create(name, email, password)
    DB.transaction do
      person = Person.create(name: name, email: email)
      PersonIdentity.create(
        person_id: person.id, provider: 'email', provider_subject: BlindIndex.generate_bidx(email, key: Lockbox.master_key),
        email: email, password_digest: BCrypt::Password.create(password, cost: COST)
      )
      person
    end
  end
  private_class_method :refusal, :create
end
