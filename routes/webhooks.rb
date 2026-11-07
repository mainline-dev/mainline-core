# frozen_string_literal: true

class Mainline
  hash_branch('webhooks') do |r|
    response['Content-Type'] = 'application/json'

    r.hash_branches('webhooks')

    response.status = 404
    '{}'
  end
end
