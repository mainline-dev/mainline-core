# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/business_days'

describe BusinessDays do
  cover 'BusinessDays*'
  it 'returns 0 for same day' do
    monday = Time.utc(2026, 4, 20, 9, 0, 0)

    assert_equal 0, BusinessDays.between(monday, monday)
  end

  it 'counts weekdays between two dates' do
    monday = Time.utc(2026, 4, 20, 9, 0, 0)
    friday = Time.utc(2026, 4, 24, 17, 0, 0)

    assert_equal 4, BusinessDays.between(monday, friday)
  end

  it 'skips weekends' do
    friday = Time.utc(2026, 4, 17, 17, 0, 0)
    monday = Time.utc(2026, 4, 20, 9, 0, 0)

    assert_equal 1, BusinessDays.between(friday, monday)
  end

  it 'handles spanning multiple weeks' do
    monday = Time.utc(2026, 4, 6, 9, 0, 0)
    friday_two_weeks = Time.utc(2026, 4, 17, 17, 0, 0)

    assert_equal 9, BusinessDays.between(monday, friday_two_weeks)
  end

  it 'works with Time objects' do
    deploy_time = Time.utc(2026, 4, 15, 14, 30, 0)
    now = Time.utc(2026, 4, 17, 10, 0, 0)

    assert_equal 2, BusinessDays.between(deploy_time, now)
  end

  it 'handles deploy on friday checked on monday as 1 business day' do
    friday = Time.utc(2026, 4, 17, 16, 0, 0)
    monday = Time.utc(2026, 4, 20, 10, 0, 0)

    assert_equal 1, BusinessDays.between(friday, monday)
  end
end
