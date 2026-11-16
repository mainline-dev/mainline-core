# frozen_string_literal: true

require 'net/http'
require 'resolv'

# The internet as ClientMetadata reaches it: the system's resolver, and an
# HTTPS GET to the very address that was checked, so a name cannot resolve
# somewhere else between the check and the connection. Each step gives up
# after five seconds, and no more than 10 KB and one byte of a body is read.
module HttpsFetch
  TIMEOUT = 5
  MAX_BYTES = 10_240

  def self.addresses(host)
    Resolv.getaddresses(host)
  end

  def self.get(uri, address)
    http = Net::HTTP.new(uri.host, uri.port)
    http.ipaddr = address
    http.use_ssl = true
    http.open_timeout = http.read_timeout = http.write_timeout = http.ssl_timeout = TIMEOUT
    http.start { http.request(Net::HTTP::Get.new(uri, 'Accept' => 'application/json')) { |response| return read(response) } }
  end

  def self.read(response)
    body = +''
    response.read_body do |chunk|
      body << chunk
      break if body.bytesize > MAX_BYTES
    end
    ClientMetadata::Response.new(status: response.code.to_i, body: body, location: response['location'],
      cache_control: response['cache-control'])
  end
end
