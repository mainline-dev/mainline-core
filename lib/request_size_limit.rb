# frozen_string_literal: true

require 'stringio'

# Turns away a request whose body is larger than anything the app takes, before
# any route reads it into memory. The largest thing the app takes is a 10 MB
# Jira CSV, sent as a form upload.
#
# A request that states its length is judged on that. One that doesn't (a
# chunked upload) is read up to one byte past the limit and no further; if it
# fits, the routes read it from that copy.
class RequestSizeLimit
  MAX_BYTES = 11 * 1024 * 1024
  CHUNK = 64 * 1024
  TOO_LARGE = [413, { 'content-type' => 'text/plain' }, ['Request body too large']].freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    length = env['CONTENT_LENGTH']
    if length && !length.empty?
      return too_large if length.to_i > MAX_BYTES
    elsif env['rack.input']
      body = read_at_most(env['rack.input'], MAX_BYTES + 1)
      return too_large if body.bytesize > MAX_BYTES

      env['rack.input'] = StringIO.new(body)
    end
    @app.call(env)
  end

  private

  def too_large
    [TOO_LARGE[0], TOO_LARGE[1].dup, TOO_LARGE[2].dup]
  end

  def read_at_most(input, limit)
    body = String.new(encoding: Encoding::BINARY)
    while body.bytesize < limit
      chunk = input.read([CHUNK, limit - body.bytesize].min)
      break if chunk.nil? || chunk.empty?

      body << chunk
    end
    body
  end
end
