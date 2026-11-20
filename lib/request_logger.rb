# frozen_string_literal: true

# One line for each request. The log is kept outside the app, so an address
# is written without what would let a reader act as someone else: its query
# string, where a sign-in code arrives, and the token of a link sent by email.
class RequestLogger
  EMAILED_LINK = %r{(/(?:magic-login|verify-email|invite)/)[^/?#]+}

  def initialize(app, logger)
    @app = app
    @logger = logger
  end

  def call(env)
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    status, headers, body = @app.call(env)
    return [status, headers, body] if env['PATH_INFO'] == '/up'

    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
    @logger.write(log_line(env, status, content_length(headers), elapsed))

    [status, headers, body]
  end

  private

  def log_line(env, status, length, elapsed)
    addr = env['HTTP_X_FORWARDED_FOR'] || env['REMOTE_ADDR'] || '-'
    ts = Time.now.strftime('%d/%b/%Y:%H:%M:%S %z')
    secs = format('%<e>0.4f', e: elapsed)
    ref = discreet(env['HTTP_REFERER'] || '-')
    ua = env['HTTP_USER_AGENT'] || '-'
    "#{addr} [#{ts}] \"#{env['REQUEST_METHOD']} #{discreet(env['PATH_INFO'])}\" #{status} #{length} #{secs} \"#{ref}\" \"#{ua}\"\n"
  end

  def content_length(headers)
    length = headers.is_a?(Hash) ? headers['content-length'] : nil
    length.nil? || length == '0' ? '-' : length
  end

  def discreet(address)
    address.sub(/[?#].*/m, '').gsub(EMAILED_LINK, '\\1[token]')
  end
end
