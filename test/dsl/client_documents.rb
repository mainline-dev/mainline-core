# frozen_string_literal: true

require_relative '../../lib/client_metadata'

# The client metadata documents apps publish, as the app fetches them in
# tests: every name resolves to one public address, and an address nobody
# published answers 404. Nothing reaches the internet.
class ClientDocuments
  def initialize
    @pages = {}
  end

  def publish(url, body)
    @pages[url] = body
  end

  def addresses(_host)
    ['160.79.104.10']
  end

  def get(uri, _address)
    body = @pages[uri.to_s]
    ClientMetadata::Response.new(status: body ? 200 : 404, body: body.to_s)
  end
end
