# frozen_string_literal: true

require_relative 'signed_state'

# When the email signup form was loaded, signed into the form, so a signup sent
# back faster than a person could type is known for a bot. A form with no
# start, a forged one, or one sent back within three seconds is a bot; one left
# open for over a day has expired and is asked for again.
module SignupTimer
  VALUE = 'signup-form'
  MIN_SECONDS = 3
  MAX_SECONDS = 24 * 60 * 60

  def self.token
    SignedState.generate(VALUE)
  end

  def self.check(token)
    value, started_at = SignedState.read(token.to_s, ttl: nil)
    return :bot unless value == VALUE

    age = Time.now - started_at
    return :bot if age < MIN_SECONDS
    return :expired if age > MAX_SECONDS

    :ok
  end
end
