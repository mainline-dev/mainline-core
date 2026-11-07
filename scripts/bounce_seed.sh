#!/usr/bin/env bash
set -euo pipefail

EMAIL="${1:-}"

docker compose exec -T app bundle exec rake dev_bounce
docker compose exec -T app bundle exec rake dev_up
docker compose exec -T app bundle exec rake dev_seed

if [ -n "$EMAIL" ]; then
  docker compose exec -T app ruby -r ./app -e "
    person = Person.find_by_email('$EMAIL')
    person ||= Person.create(name: '$EMAIL'.split('@').first.gsub('.', ' ').split.map(&:capitalize).join(' '), email: '$EMAIL')
    Team.each do |team|
      unless TeamMembership.where(team_id: team.id, person_id: person.id).any?
        TeamMembership.create(team_id: team.id, person_id: person.id, working: true)
      end
      team.update(creator_id: person.id) unless team.creator_id
    end
    puts \"Injected #{person.name} (#{person.email}) into #{Team.count} teams\"
    puts \"Login: http://localhost:3000/_test_login?person_id=#{person.id}\"
  "
fi
