# frozen_string_literal: true

# What the routes that take a story's title through a template share: the
# templates a team chooses between, and the title each builds from what was
# typed into its fields. Route files load one at a time as they are first
# asked for, so what more than one of them needs lives here.
class Mainline
  STORY_TEMPLATES = %w[connextra card behaviour].freeze

  def template_title
    template = typecast_params.nonempty_str('template')
    title = case template
            when 'connextra' then connextra_title
            when 'behaviour' then behaviour_title
            when 'card'      then card_title
            else typecast_params.nonempty_str('title')
            end
    [template, title]
  end

  def connextra_title
    role    = typecast_params.nonempty_str('role')
    goal    = typecast_params.nonempty_str('goal')
    benefit = typecast_params.nonempty_str('benefit')
    "As a #{role}, I want to #{goal}, so that #{benefit}" if role && goal && benefit
  end

  def behaviour_title
    context = typecast_params.nonempty_str('beh_context')
    persona = typecast_params.nonempty_str('beh_persona')
    action  = typecast_params.nonempty_str('beh_action')
    "When #{context}, #{persona} can #{action}" if context && persona && action
  end

  def card_title
    persona = typecast_params.nonempty_str('card_persona')
    action  = typecast_params.nonempty_str('card_action')
    "#{persona} #{action}" if persona && action
  end
end
