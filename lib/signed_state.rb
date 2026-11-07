# frozen_string_literal: true

require 'openssl'

module SignedState
  SEPARATOR = '.'
  TTL = 600

  def self.generate(value)
    payload = "#{value}:#{Time.now.to_i}"
    "#{payload}#{SEPARATOR}#{sign(payload)}"
  end

  def self.verify(token)
    read(token)&.first
  end

  # The signed value and when it was signed, or nil if the token is not one of
  # ours or is older than ttl seconds (no limit when ttl is nil).
  def self.read(token, ttl: TTL)
    return nil if token.nil? || token.empty?

    parts = token.split(SEPARATOR, 2)
    return nil if parts.length != 2

    payload, signature = parts
    return nil if payload.empty? || signature.empty?

    expected = sign(payload)
    return nil unless signature.bytesize == expected.bytesize
    return nil unless OpenSSL.fixed_length_secure_compare(signature, expected)

    idx = payload.rindex(':')
    return nil unless idx

    value = payload[0...idx]
    timestamp = payload[(idx + 1)..]

    issued_at = timestamp.to_i
    return nil if ttl && Time.now.to_i - issued_at > ttl

    [value, Time.at(issued_at)]
  end

  def self.sign(value)
    OpenSSL::HMAC.hexdigest('SHA256', key, value)
  end

  def self.key
    OpenSSL::HMAC.digest('SHA256', ENV.fetch('MAINLINE_SESSION_SECRET'), 'mainline-signed-state')
  end

  private_class_method :sign, :key
end
