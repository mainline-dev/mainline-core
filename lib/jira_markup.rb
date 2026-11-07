# frozen_string_literal: true

require 'cgi'

# Jira's wiki markup, as found in a ticket's description, as a little HTML for
# reading in the museum. Everything is escaped; only headings, paragraphs,
# lists, bold, italic, code blocks and links to web addresses come back as
# markup. Macros such as colour and panels are dropped, keeping their text.
# Images are not shown.
module JiraMarkup
  CODE = /\{(code|noformat)(?::[^}]*)?\}\n?(.*?)\n?\{\1\}/m
  HEADING = /\Ah[1-6]\.\s+(.*)\z/
  LIST_ITEM = /\A\s*([*#-])[*#-]*\s+(.*)\z/
  MACRO = /\{[a-z]+(?::[^}]*)?\}/i
  LINK = /\[([^\[\]|]+)\|([^\[\]\s]+)\]/
  BOLD = /(?<![\w*])\*(?=\S)([^*\n]+?)(?<=\S)\*(?![\w*])/
  ITALIC = /(?<![\w_])_(?=\S)([^_\n]+?)(?<=\S)_(?![\w_])/
  WEB = %r{\Ahttps?://}i
  HELD = /\u0000(\d+)\u0000/

  def self.to_html(text)
    codes = []
    text = text.to_s.gsub("\r\n", "\n").gsub(CODE) {
      codes << Regexp.last_match(2)
      "\n\u0000#{codes.size - 1}\u0000\n"
    }
    Blocks.new(codes).render(text.split("\n"))
  end

  # A line's text with its links, bold and italic, everything else escaped.
  def self.inline(text)
    links = []
    escaped = CGI.escapeHTML(text.gsub(MACRO, '')).gsub(LINK) {
      label, url = Regexp.last_match.captures
      links << (url.match?(WEB) ? %(<a href="#{url}" target="_blank" rel="noopener">#{label}</a>) : label)
      "\u0000#{links.size - 1}\u0000"
    }
    escaped.gsub(BOLD, '<strong>\1</strong>').gsub(ITALIC, '<em>\1</em>').gsub(HELD) { links[Regexp.last_match(1).to_i] }
  end

  # Lines gathered into headings, paragraphs, lists and code blocks.
  class Blocks
    def initialize(codes)
      @codes = codes
      @html = +''
      @paragraph = []
      @list = nil
    end

    def render(lines)
      lines.each { |line| add(line) }
      close_paragraph
      close_list
      @html
    end

    private

    def add(line)
      if (code = line[/\A#{HELD}\z/o, 1])
        block(%(<pre class="mu-code">#{CGI.escapeHTML(@codes[code.to_i])}</pre>))
      elsif (heading = line[HEADING, 1])
        block(%(<h4 class="mu-md-h">#{JiraMarkup.inline(heading)}</h4>))
      elsif (item = line.match(LIST_ITEM))
        list_item(item[1] == '#' ? 'ol' : 'ul', item[2])
      elsif line.strip.empty?
        close_paragraph
        close_list
      else
        close_list
        @paragraph << JiraMarkup.inline(line.strip)
      end
    end

    def block(html)
      close_paragraph
      close_list
      @html << html
    end

    def list_item(kind, text)
      close_paragraph
      close_list unless @list == kind
      @html << %(<#{kind} class="mu-md-list">) unless @list
      @list = kind
      @html << "<li>#{JiraMarkup.inline(text)}</li>"
    end

    def close_paragraph
      @html << "<p>#{@paragraph.join('<br>')}</p>" unless @paragraph.empty?
      @paragraph = []
    end

    def close_list
      @html << "</#{@list}>" if @list
      @list = nil
    end
  end
end
