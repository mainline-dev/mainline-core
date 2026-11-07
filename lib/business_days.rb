# frozen_string_literal: true

module BusinessDays
  def self.between(from, to)
    count = 0
    date = from.to_date + 1
    end_date = to.to_date
    while date <= end_date
      count += 1 unless date.saturday? || date.sunday?
      date += 1
    end
    count
  end
end
