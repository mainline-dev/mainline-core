# frozen_string_literal: true

ENV['MT_NO_PLUGINS'] = '1'
gem 'minitest'
require 'minitest/global_expectations/autorun'
require_relative '../../lib/oauth_setting'

describe OauthSetting do
  cover 'OauthSetting*'

  it 'is on only when OAUTH_ENABLED says true' do
    assert OauthSetting.on?('OAUTH_ENABLED' => 'true')

    [nil, '', 'false', 'TRUE', 'yes', '1'].each do |value|
      refute OauthSetting.on?('OAUTH_ENABLED' => value), value.inspect
    end
    refute OauthSetting.on?({})
  end
end
