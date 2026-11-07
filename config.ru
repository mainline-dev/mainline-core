# frozen_string_literal: true

# Before anything reads (and removes) the database URLs.
require_relative 'lib/env_check'

dev = ENV['RACK_ENV'] == 'development'

if dev
  require 'logger'
  logger = Logger.new($stdout)
end

require 'rack/unreloader'
Unreloader = Rack::Unreloader.new(subclasses: %w[Roda Sequel::Model], logger: logger, reload: dev, autoload: dev) { Mainline }
require_relative 'models'
Unreloader.require('app.rb') { 'Mainline' }
app = dev ? Unreloader : Mainline.freeze.app

run app

unless dev
  Tilt.finalize!
  RubyVM::YJIT.enable if defined?(RubyVM::YJIT.enable)
end

freeze_core = false
# freeze_core = !dev # Uncomment to enable refrigerator
if freeze_core
  begin
    require 'refrigerator'
  rescue LoadError
  else
    require 'nio' if defined?(Puma)
    Refrigerator.freeze_core
  end
end
