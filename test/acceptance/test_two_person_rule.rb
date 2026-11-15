# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'

# A story can be released only if two people have seen it: two people were on
# it while it was active, or a walkthrough is recorded for it.
describe 'Two people see every story before release' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    @bob   = add_person(name: 'Bob')
    create_map
    activity = create_activity('Browse', for_personas: [create_persona('Shopper')])
    @story = create_story('Find things', under_task: create_task('Search', under_activity: activity))
  end

  def released?
    @story.reload.status == 'released'
  end

  it 'releases a paired story with no walkthrough' do
    assign_person(@story, person: @alice)
    assign_person(@story, person: @bob)
    deploy_story(@story)

    release_story(@story)

    assert_predicate self, :released?
  end

  it 'records no walkthrough for a story that has not been deployed' do
    update_settings(allow_solo_activation: '1')
    assign_person(@story, person: @alice)

    record_walkthrough(@story, attended_by: [@bob])
    driver.follow_redirect! if driver.last_response.redirect?

    assert_refused_because('not-deployed')
    deploy_story(@story)
    release_story(@story)

    refute_predicate self, :released?
  end

  it 'records a walkthrough on a paired story, which never needs one' do
    carol = add_person(name: 'Carol')
    assign_person(@story, person: @alice)
    assign_person(@story, person: @bob)
    deploy_story(@story)

    record_walkthrough(@story, attended_by: [carol])
    driver.follow_redirect! if driver.last_response.redirect?

    assert_notice_shown
  end

  describe 'a story one person worked on' do
    before do
      update_settings(allow_solo_activation: '1')
      assign_person(@story, person: @alice)
      deploy_story(@story)
    end

    it 'cannot be released without a walkthrough' do
      release_story(@story)
      driver.follow_redirect! if driver.last_response.redirect?

      assert_refused_because('needs-walkthrough')
      refute_predicate self, :released?
    end

    it 'releases once a walkthrough is recorded' do
      record_walkthrough(@story, attended_by: [@bob])

      release_story(@story)

      assert_predicate self, :released?
    end

    it 'releases with no walkthrough once the team has turned the rule off' do
      update_settings(two_person_rule: '0', two_person_rule_reason: 'Reviewing another way for now')

      release_story(@story)

      assert_predicate self, :released?
    end

    it 'keeps the rule on when it is turned off with no reason given' do
      update_settings(two_person_rule: '0', two_person_rule_reason: '  ')
      driver.follow_redirect! if driver.last_response.redirect?

      assert_refused_because('reason-needed')
      release_story(@story)

      refute_predicate self, :released?
    end

    it 'shows in the settings history that the rule was turned off, and why' do
      update_settings(two_person_rule: '0', two_person_rule_reason: 'Reviewing another way for now')
      visit_settings

      assert_page_includes('data-setting="two_person_rule"')
      assert_shown('settings-event-reason')
    end

    describe 'and someone on another team' do
      before do
        @eve = Person.create(name: 'Eve', email: 'eve@elsewhere.co')
        @elsewhere = Team.create(name: 'Elsewhere')
        TeamMembership.create(team_id: @elsewhere.id, person_id: @eve.id)
        login_as(@eve)
      end

      it "cannot record a walkthrough for this team's story, here or through their own team" do
        assert_equal 403, driver.submit_walkthrough(@team, @story, attendee_ids: [@bob.id]).status
        assert_raises(RuntimeError) { driver.submit_walkthrough(@elsewhere, @story, attendee_ids: [@bob.id]) }

        login_as(@alice)
        release_story(@story)

        refute_predicate self, :released?
      end

      it "cannot see this team's walkthroughs" do
        assert_equal 403, visit_walkthroughs.status
      end
    end

    it 'does not take the person on the story as attending its walkthrough' do
      record_walkthrough(@story, attended_by: [@alice])
      driver.follow_redirect! if driver.last_response.redirect?

      assert_refused_because('attendee-on-story')
      release_story(@story)

      refute_predicate self, :released?
    end
  end
end

describe 'The Walkthroughs page' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    @bob   = add_person(name: 'Bob')
  end

  it 'is a tab under Teamwork' do
    visit_walkthroughs

    assert_shown('teamwork-page-walkthroughs')
    assert_shown('teamwork-tab-walkthroughs')
  end

  it 'says the rule is off, with the way to Settings, once the team has turned it off' do
    update_settings(two_person_rule: '0', two_person_rule_reason: 'Reviewing another way for now')

    visit_walkthroughs

    assert_shown('walkthrough-rule-off')
    assert_shown('walkthrough-rule-settings')
  end

  it 'says nothing about the rule being off while it is on' do
    visit_walkthroughs

    refute_shown('walkthrough-rule-off')
  end

  it 'says so when no story is waiting for a walkthrough' do
    visit_walkthroughs

    assert_shown('walkthrough-none-needed')
    assert_empty walkthroughs_needed
  end

  describe 'with a story one person has deployed' do
    before do
      create_map
      activity = create_activity('Browse', for_personas: [create_persona('Shopper')])
      @story = create_story('Find things', under_task: create_task('Search', under_activity: activity))
      update_settings(allow_solo_activation: '1')
      assign_person(@story, person: @alice)
      deploy_story(@story)
    end

    it 'lists the story as needing a walkthrough, with a form offering the people who are not on it' do
      visit_walkthroughs

      assert_equal [@story.id], walkthroughs_needed
      assert_equal [@bob.id], could_attend(@story)
      refute_shown('walkthrough-none-needed')
    end

    it 'shows how many scenarios the story has and the day it was last deployed' do
      create_scenario(@story, given_text: 'a full shop', when_text: 'a guest searches', then_text: 'matches are listed')
      create_scenario(@story, given_text: 'an empty shop', when_text: 'a guest searches', then_text: 'nothing is listed')

      visit_walkthroughs

      assert_equal '2', walkthrough_row(@story)[:scenarios]
      assert_equal @story.reload.last_deployed_at.strftime('%Y-%m-%d'), walkthrough_row(@story)[:last_deployed]
    end
  end
end

describe 'A team of one and the two-person rule' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    create_map
    activity = create_activity('Browse', for_personas: [create_persona('Shopper')])
    @story = create_story('Find things', under_task: create_task('Search', under_activity: activity))
  end

  it 'releases a solo story with no walkthrough' do
    assign_person(@story, person: @alice)
    deploy_story(@story)

    release_story(@story)

    assert_equal 'released', @story.reload.status
  end

  it 'has no Walkthroughs tab, and is sent on to the pairing matrix from the page address' do
    visit_teamwork

    refute_shown('teamwork-tab-walkthroughs')
    assert_equal "/teams/#{@team.id}/teamwork", URI(visit_walkthroughs.location.to_s).path
  end
end

describe 'The limit on stories awaiting a walkthrough' do
  include MainlineDSL

  before do
    setup_team
    @alice, @bob, @carol, @dan = %w[Alice Bob Carol Dan].map { |name| add_person(name: name) }
    create_map
    activity = create_activity('Browse', for_personas: [create_persona('Shopper')])
    @task = create_task('Search', under_activity: activity)
    update_settings(allow_solo_activation: '1')
    @waiting = [@alice, @bob, @carol].map { |person| deployed_by_one(person) }
    @next = create_story('Next', under_task: @task)
  end

  def deployed_by_one(person)
    story = create_story("#{person.name}'s story", under_task: @task)
    assign_person(story, person: person)
    deploy_story(story)
    story
  end

  it 'stops anyone starting another story once three are waiting' do
    assign_person(@next, person: @dan)

    assert_shown('form-errors')
    assert_equal 'planned', @next.reload.status
  end

  it 'lets a story start once the team raises the limit, giving a reason' do
    update_settings(walkthrough_limit: 4, walkthrough_limit_reason: 'Two people are away this week')

    assign_person(@next, person: @dan)

    assert_equal 'active', @next.reload.status
  end

  it 'keeps the limit when it is raised with no reason given' do
    update_settings(walkthrough_limit: 4, walkthrough_limit_reason: ' ')
    driver.follow_redirect! if driver.last_response.redirect?

    assert_refused_because('reason-needed')
    assign_person(@next, person: @dan)

    assert_equal 'planned', @next.reload.status
  end

  it 'refuses a limit above ten or below one, and keeps the one it had' do
    [11, 0].each do |limit|
      update_settings(walkthrough_limit: limit, walkthrough_limit_reason: 'Trying it')
      driver.follow_redirect! if driver.last_response.redirect?

      assert_refused_because('out-of-range')
    end
    assign_person(@next, person: @dan)

    assert_equal 'planned', @next.reload.status
  end

  it 'shows on the Walkthroughs page how many stories are waiting against the limit' do
    update_settings(walkthrough_limit: 5, walkthrough_limit_reason: 'Two people are away this week')

    visit_walkthroughs

    assert_equal({ waiting: '3', limit: '5' }, walkthroughs_against_limit)
  end

  it 'shows in the settings history that the limit was changed, and why' do
    update_settings(walkthrough_limit: 5, walkthrough_limit_reason: 'Two people are away this week')
    visit_settings

    assert_page_includes('data-setting="walkthrough_limit"')
    assert_shown('settings-event-reason')
  end

  it 'lets a story start once one of the three has been walked through' do
    record_walkthrough(@waiting.first, attended_by: [@dan])

    assign_person(@next, person: @dan)

    assert_equal 'active', @next.reload.status
  end
end
