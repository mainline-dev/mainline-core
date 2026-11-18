# frozen_string_literal: true

require 'time'

# A moment as the pages write it: in UTC and saying so, in a time element
# that carries the exact moment for anything reading the page.
module UtcStamp
  def self.html(time)
    utc = time.getutc
    %(<time datetime="#{utc.iso8601}">#{utc.strftime('%Y-%m-%d %H:%M')} UTC</time>)
  end
end
