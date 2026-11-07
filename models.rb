# frozen_string_literal: true

require_relative 'db'
require_relative 'lib/lockbox_setup'
require_relative 'lib/encrypted_email'
require 'sequel/model'

Sequel::Model.cache_associations = false if ENV['RACK_ENV'] == 'development'

Sequel::Model.plugin :auto_validations
Sequel::Model.plugin :require_valid_schema
Sequel::Model.plugin :subclasses unless ENV['RACK_ENV'] == 'development'

unless defined?(Unreloader)
  require 'rack/unreloader'
  Unreloader = Rack::Unreloader.new(reload: false, autoload: !ENV['NO_AUTOLOAD'])
end

Unreloader.autoload('models') {|f| Sequel::Model.send(:camelize, File.basename(f).sub(/\.rb\z/, ''))}

if %w[development test].include?(ENV['RACK_ENV'])
  require 'logger'
  LOGGER = Logger.new($stdout)
  LOGGER.level = Logger::FATAL if ENV['RACK_ENV'] == 'test'
  DB.loggers << LOGGER
end
