# frozen_string_literal: true

class FlashAdapter
  attr_reader :message, :type, :reason

  def initialize
    @message = nil
    @type = nil
    @reason = nil
  end

  def notice(msg)
    @message = msg
    @type = 'notice'
  end

  def error(msg, reason: nil)
    @message = msg
    @type = 'error'
    @reason = reason
  end

  def set?
    !@message.nil?
  end

  def write_session(session_flash)
    return unless set?

    session_flash[@type] = @message
    session_flash['error_reason'] = @reason if @reason
  end

  def to_htmx_trigger
    return unless set?

    detail = { message: @message, type: @type }
    detail[:reason] = @reason if @reason
    { showFlash: detail }
  end

  def self.clear_session(session_flash)
    %w[notice error error_reason].each { |k| session_flash.delete(k) }
    %i[notice error error_reason].each { |k| session_flash.delete(k) }
  end
end
