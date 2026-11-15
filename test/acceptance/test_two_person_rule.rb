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
end
