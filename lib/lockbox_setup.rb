# frozen_string_literal: true

require 'lockbox'
require 'blind_index'

Lockbox.master_key = ENV.fetch('LOCKBOX_MASTER_KEY') {
  '0' * 64 if %w[test development].include?(ENV.fetch('RACK_ENV', 'development'))
}
