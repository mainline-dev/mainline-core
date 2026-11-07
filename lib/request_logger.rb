# frozen_string_literal: true

class RequestLogger
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
    ref = env['HTTP_REFERER'] || '-'
    ua = env['HTTP_USER_AGENT'] || '-'
    "#{addr} [#{ts}] \"#{env['REQUEST_METHOD']} #{request_path(env)}\" #{status} #{length} #{secs} \"#{ref}\" \"#{ua}\"\n"
  end

  def content_length(headers)
    length = headers.is_a?(Hash) ? headers['content-length'] : nil
    length.nil? || length == '0' ? '-' : length
  end

  def request_path(env)
    qs = env['QUERY_STRING']
    qs.nil? || qs.empty? ? env['PATH_INFO'] : "#{env['PATH_INFO']}?#{qs}"
  end
end
