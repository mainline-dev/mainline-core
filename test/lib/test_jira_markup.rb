# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/jira_markup'

describe JiraMarkup do
  cover 'JiraMarkup*'

  def html(text)
    JiraMarkup.to_html(text)
  end

  it 'turns headings into headings and lines into paragraphs' do
    assert_equal '<h4 class="mu-md-h">Background</h4><p>Customers abandon<br>at the account step.</p><p>Second.</p>',
      html("h2. Background\nCustomers abandon\nat the account step.\n\nSecond.")
  end

  it 'turns bullets and numbers into lists' do
    assert_equal '<ul class="mu-md-list"><li>Guest checkout</li><li>No password</li></ul>', html("* Guest checkout\n- No password")
    assert_equal '<ol class="mu-md-list"><li>First</li><li>Second</li></ol>', html("# First\n# Second")
  end

  it 'marks bold and italic, leaving snake_case and lone stars alone' do
    assert_equal '<p><strong>Email</strong> is <em>required</em>, guest_token stays, 2 * 3 too</p>',
      html('*Email* is _required_, guest_token stays, 2 * 3 too')
  end

  it 'keeps code as it was written' do
    assert_equal %(<pre class="mu-code">GuestCheckout.enabled?\n  &lt;b&gt;*not bold*&lt;/b&gt;</pre>),
      html("{code:ruby}GuestCheckout.enabled?\n  <b>*not bold*</b>{code}")
    assert_equal '<pre class="mu-code">as is</pre>', html("{noformat}\nas is\n{noformat}")
  end

  it 'links only to web addresses, in a new tab' do
    assert_equal '<p><a href="https://example.com/a?b=1&amp;c=2" target="_blank" rel="noopener">the spec</a></p>',
      html('[the spec|https://example.com/a?b=1&c=2]')
    assert_equal '<p>click</p>', html('[click|javascript:alert(1)]')
  end

  it 'drops macros like colour and panels, keeping what is inside' do
    assert_equal '<p>Red alert and a panel</p>', html('{color:red}Red alert{color} and {panel:title=x}a panel{panel}')
  end

  it 'escapes everything else' do
    assert_equal '<p>&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt; &amp; more</p>', html('<script>alert("x")</script> & more')
  end

  it 'gives nothing for an empty description' do
    assert_equal '', html('')
    assert_equal '', html(nil)
  end
end
