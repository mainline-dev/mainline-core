# frozen_string_literal: true

require_relative '../coverage_helper'
ENV['MT_NO_PLUGINS'] = '1'
gem 'minitest'
require 'minitest/global_expectations/autorun'
require_relative '../../lib/flash_adapter'

describe FlashAdapter do
  cover 'FlashAdapter*'
  before do
    @flash = FlashAdapter.new
  end

  describe '#notice' do
    it 'stores a notice message' do
      @flash.notice('Story created')

      assert_equal 'Story created', @flash.message
      assert_equal 'notice', @flash.type
    end
  end

  describe '#error' do
    it 'stores an error message' do
      @flash.error('Something broke')

      assert_equal 'Something broke', @flash.message
      assert_equal 'error', @flash.type
    end
  end

  describe '#set?' do
    it 'returns false when empty' do
      refute_predicate @flash, :set?
    end

    it 'returns true after notice' do
      @flash.notice('hi')

      assert_predicate @flash, :set?
    end

    it 'returns true after error' do
      @flash.error('bad')

      assert_predicate @flash, :set?
    end
  end

  describe '#write_session' do
    it 'writes message to session flash with string keys' do
      session_flash = {}
      @flash.notice('Story deployed')

      @flash.write_session(session_flash)

      assert_equal 'Story deployed', session_flash['notice']
      assert_nil session_flash['error']
    end

    it 'writes error to session flash with string keys' do
      session_flash = {}
      @flash.error('Only active stories can be deployed')

      @flash.write_session(session_flash)

      assert_equal 'Only active stories can be deployed', session_flash['error']
      assert_nil session_flash['notice']
    end

    it 'writes the reason for an error alongside it' do
      session_flash = {}
      @flash.error('Scenarios not verified', reason: 'unverified-scenarios')

      @flash.write_session(session_flash)

      assert_equal 'unverified-scenarios', session_flash['error_reason']
    end

    it 'writes no reason for an error without one' do
      session_flash = {}
      @flash.error('Something broke')

      @flash.write_session(session_flash)

      refute session_flash.key?('error_reason')
    end

    it 'does nothing when no message set' do
      session_flash = {}

      @flash.write_session(session_flash)

      assert_nil session_flash['notice']
      assert_nil session_flash['error']
    end
  end

  describe '#to_htmx_trigger' do
    it 'returns trigger hash for notice' do
      @flash.notice('Story archived')

      result = @flash.to_htmx_trigger

      assert_equal({ showFlash: { message: 'Story archived', type: 'notice' } }, result)
    end

    it 'returns trigger hash for error' do
      @flash.error('Cannot archive')

      result = @flash.to_htmx_trigger

      assert_equal({ showFlash: { message: 'Cannot archive', type: 'error' } }, result)
    end

    it 'includes the reason for an error' do
      @flash.error('Scenarios not verified', reason: 'unverified-scenarios')

      result = @flash.to_htmx_trigger

      assert_equal({ showFlash: { message: 'Scenarios not verified', type: 'error', reason: 'unverified-scenarios' } },
        result)
    end

    it 'returns nil when no message set' do
      assert_nil @flash.to_htmx_trigger
    end
  end

  describe '.clear_session' do
    it 'removes notice and error with string keys' do
      session_flash = { 'notice' => 'old', 'error' => 'old err' }

      FlashAdapter.clear_session(session_flash)

      assert_nil session_flash['notice']
      assert_nil session_flash['error']
    end

    it 'removes notice and error with symbol keys' do
      session_flash = { notice: 'old', error: 'old err' }

      FlashAdapter.clear_session(session_flash)

      assert_nil session_flash[:notice]
      assert_nil session_flash[:error]
    end

    it 'removes the error reason' do
      session_flash = { 'error' => 'old err', 'error_reason' => 'unverified-scenarios' }

      FlashAdapter.clear_session(session_flash)

      assert_nil session_flash['error_reason']
    end

    it 'removes mixed key types' do
      session_flash = { notice: 'sym', 'error' => 'str' }

      FlashAdapter.clear_session(session_flash)

      assert_nil session_flash[:notice]
      assert_nil session_flash['error']
    end
  end
end
