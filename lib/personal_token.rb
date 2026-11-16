# frozen_string_literal: true

require 'digest'
require 'securerandom'
require 'zlib'

# The shape of a personal token: mainline_pat_, a random part, then a
# checksum of the random part. A secret scanner can tell a real token from a
# look-alike by the checksum without asking Mainline. Only the token's SHA-256
# digest is stored.
module PersonalToken
  PREFIX = 'mainline_pat_'
  ALPHABET = [*'0'..'9', *'A'..'Z', *'a'..'z'].join.freeze
  RANDOM_LENGTH = 32
  CHECK_LENGTH = 6

  def self.generate
    random = Array.new(RANDOM_LENGTH) { ALPHABET[SecureRandom.random_number(ALPHABET.length)] }.join
    "#{PREFIX}#{random}#{checksum(random)}"
  end

  def self.well_formed?(token)
    token = token.to_s
    return false unless token.start_with?(PREFIX)

    random = token[PREFIX.length, RANDOM_LENGTH]
    random.match?(/\A[0-9A-Za-z]{#{RANDOM_LENGTH}}\z/o) && token[(PREFIX.length + RANDOM_LENGTH)..] == checksum(random)
  end

  def self.digest(token)
    Digest::SHA256.hexdigest(token)
  end

  # The checksum a scanner computes: the random part's CRC32, written in the
  # token's own alphabet as six characters, the most significant first.
  def self.checksum(random)
    value = Zlib.crc32(random)
    Array.new(CHECK_LENGTH) {
      digit = ALPHABET[value % ALPHABET.length]
      value /= ALPHABET.length
      digit
    }.reverse.join
  end
end
