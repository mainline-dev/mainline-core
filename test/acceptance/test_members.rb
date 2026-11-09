# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'

describe 'Team members page' do
  include MainlineDSL

  before do
    setup_team
  end

  it 'non-working account holder can access members page' do
    holder = Person.create(name: 'Buyer', email: 'buyer@corp.co')
    TeamMembership.create(team_id: @team.id, person_id: holder.id, working: false)
    login_as(holder)

    resp = driver.visit_members(@team)

    assert_equal 200, resp.status
    assert_shown('members-page', resp.body)
  end

  it 'shows current working members' do
    holder = Person.create(name: 'Buyer', email: 'buyer@corp.co')
    TeamMembership.create(team_id: @team.id, person_id: holder.id, working: false)
    add_person(name: 'Alice')
    login_as(holder)

    resp = driver.visit_members(@team)

    assert_includes resp.body, 'Alice'
  end

  it 'shows invite form when team is trialing' do
    holder = Person.create(name: 'Buyer', email: 'buyer@corp.co')
    TeamMembership.create(team_id: @team.id, person_id: holder.id, working: false)
    @team.update(creator_id: holder.id)
    login_as(holder)

    resp = driver.visit_members(@team)

    assert_equal 200, resp.status
    assert_shown('invite-form', resp.body)
  end

  it 'shows invite form when team has active subscription' do
    holder = Person.create(name: 'Buyer', email: 'buyer@corp.co')
    TeamMembership.create(team_id: @team.id, person_id: holder.id, working: false)
    @team.update(creator_id: holder.id)
    login_as(holder)

    resp = driver.visit_members(@team)

    assert_shown('invite-form', resp.body)
  end

  it 'submits invite from members page' do
    holder = Person.create(name: 'Buyer', email: 'buyer@corp.co')
    TeamMembership.create(team_id: @team.id, person_id: holder.id, working: false)
    login_as(holder)

    resp = driver.submit_invite(@team, email: 'dev@corp.co')

    assert_predicate resp, :redirect?
    bidx = BlindIndex.generate_bidx('dev@corp.co', key: Lockbox.master_key)
    invite = Invitation.where(team_id: @team.id, email_bidx: bidx).first

    refute_nil invite
  end

  it 'rejects duplicate pending invite' do
    holder = Person.create(name: 'Buyer', email: 'buyer@corp.co')
    TeamMembership.create(team_id: @team.id, person_id: holder.id, working: false)
    login_as(holder)

    driver.submit_invite(@team, email: 'dev@corp.co')
    resp = driver.submit_invite(@team, email: 'dev@corp.co')
    resp = driver.follow_invite_redirect if resp.redirect?

    assert_error_shown(resp.body)
    assert_equal 1, Invitation.where(team_id: @team.id,
      email_bidx: BlindIndex.generate_bidx('dev@corp.co', key: Lockbox.master_key)).count
  end

  it 'rejects invite for existing team member' do
    holder = Person.create(name: 'Buyer', email: 'buyer@corp.co')
    TeamMembership.create(team_id: @team.id, person_id: holder.id, working: false)
    add_person(name: 'Alice', email: 'alice@corp.co')
    login_as(holder)

    resp = driver.submit_invite(@team, email: 'alice@corp.co')
    resp = driver.follow_invite_redirect if resp.redirect?

    assert_error_shown(resp.body)
    bidx = BlindIndex.generate_bidx('alice@corp.co', key: Lockbox.master_key)

    assert_equal(0, BypassRLS.call { Invitation.where(team_id: @team.id, email_bidx: bidx).count })
  end

  it 'allows re-inviting an archived member' do
    holder = Person.create(name: 'Buyer', email: 'buyer@corp.co')
    TeamMembership.create(team_id: @team.id, person_id: holder.id, working: false)
    @team.update(creator_id: holder.id)
    alice = add_person(name: 'Alice', email: 'alice@corp.co')
    TeamMembership.where(team_id: @team.id, person_id: alice.id).update(working: true)
    login_as(holder)
    driver.submit_archive_member(@team, alice)

    resp = driver.submit_invite(@team, email: 'alice@corp.co')
    resp = driver.follow_invite_redirect if resp.redirect?

    refute_error_shown(resp.body)
    assert_equal 1, Invitation.where(team_id: @team.id,
      email_bidx: BlindIndex.generate_bidx('alice@corp.co', key: Lockbox.master_key)).count
  end
end

describe 'Archive member' do
  include MainlineDSL

  before do
    setup_team
    @holder = Person.create(name: 'Buyer', email: 'buyer@corp.co')
    @team.update(creator_id: @holder.id)
    TeamMembership.create(team_id: @team.id, person_id: @holder.id, working: false)
    @alice = add_person(name: 'Alice', email: 'alice@corp.co')
    login_as(@holder)
  end

  it 'account holder archives a working member' do
    resp = driver.submit_archive_member(@team, @alice)

    assert_predicate resp, :redirect?

    membership = TeamMembership.where(team_id: @team.id, person_id: @alice.id).first

    refute_nil membership.left_at, 'Expected left_at to be set'
  end

  it 'archived member appears in archived list' do
    driver.submit_archive_member(@team, @alice)

    resp = driver.visit_members(@team)

    assert_includes resp.body, 'Archived Members'
    assert_includes resp.body, 'Alice'
  end

  it 'archived member no longer in working list' do
    @bob = add_person(name: 'Bob', email: 'bob@corp.co')
    driver.submit_archive_member(@team, @alice)

    resp = driver.visit_members(@team)
    working_section = resp.body.split('Archived Members').first

    assert_includes working_section, 'Bob'
    refute_includes working_section, 'Alice'
  end

  it 'auto-unassigns from active stories on archive' do
    login_as(@alice)
    create_map
    persona = create_persona('Customer')
    activity = create_activity('Onboarding', for_personas: [persona])
    task = create_task('Sign up', under_activity: activity)
    story = create_story('Register', under_task: task)
    StoryAssignment.create(story_id: story.id, person_id: @alice.id, team_id: @team.id)
    login_as(@holder)

    driver.submit_archive_member(@team, @alice)

    assert_equal(0, BypassRLS.call { StoryAssignment.where(person_id: @alice.id).count })
    assert_event_recorded(entity: story, action: 'person_unassigned')
  end

  it 'records member_archived event' do
    driver.submit_archive_member(@team, @alice)

    membership = TeamMembership.where(team_id: @team.id, person_id: @alice.id).first
    event = Event.where(entity_id: membership.id, action: 'member_archived').first

    refute_nil event, 'Expected member_archived event'
    assert_equal @team.id, event.team_id
    assert_equal @alice.id, event.before_state['person_id']
    assert_equal 'Alice', event.before_state['name']
  end

  it 'non-creator cannot archive a member' do
    login_as(@alice)

    resp = driver.submit_archive_member(@team, @alice)

    assert_equal 403, resp.status

    membership = TeamMembership.where(team_id: @team.id, person_id: @alice.id).first

    assert_nil membership.left_at
  end

  it 'account holder cannot archive themselves' do
    @holder_membership = TeamMembership.where(team_id: @team.id, person_id: @holder.id).first
    @holder_membership.update(working: true)

    resp = driver.submit_archive_member(@team, @holder)

    @holder_membership.reload

    assert_nil @holder_membership.left_at
    assert_predicate resp, :redirect?
  end

  it 'archive button not shown for account holder in members list' do
    @holder_membership = TeamMembership.where(team_id: @team.id, person_id: @holder.id).first
    @holder_membership.update(working: true)

    resp = driver.visit_members(@team)

    refute_includes resp.body, 'data-test-id="archive-buyer"'
    assert_includes resp.body, 'data-test-id="archive-alice"'
  end
end
