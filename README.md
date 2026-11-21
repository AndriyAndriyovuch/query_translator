# QueryTranslator

Turns a search request written in plain language into filters your JSON API already understands.

> *"a hall for 50 people in Chicago tomorrow under $300"*
> → `GET /api/v1/venues?by_city_match=Chicago&by_capacity_gte=50&available_on=2026-11-22&max_price=300.0`

The gem asks an LLM (through [RubyLLM](https://rubyllm.com)) to fill in a strict answer form, then checks every filter
against the list you gave it. Searching itself stays with your app: the gem only builds the API call.

[Українською](README.uk.md) · [Guide for coding agents](AGENTS.md)

## What you get

- **Any language and slang.** "Chi-town", "50k", "днюха", "salón de fiestas" all map to your filters.
- **Questions instead of guesses.** For "a big hall" or "on the weekend" it asks back, with 2–4 answer options, in the
  language of the request.
- **Honest confidence.** When part of the request fits no filter ("with a sea view"), it says so, and you show your
  usual filter form instead of wrong results.
- **Several kinds of search.** It picks the right one per request, e.g. venues vs. "my cancelled bookings".
- **Safe output.** Only filter names and enum values from your list get through. The user's text is treated as data,
  so "ignore your rules and…" does nothing.

## Requirements

- Ruby 3.2+
- An API key for an LLM provider that RubyLLM supports with structured output. The default model is Claude Haiku 5.5.

## Install

```ruby
# Gemfile
gem 'query_translator', git: 'https://github.com/AndriyAndriyovuch/query_translator.git', branch: 'master'
```

```bash
bundle install
```

## Set up

```ruby
# config/initializers/ruby_llm.rb
RubyLLM.configure do |config|
  config.anthropic_api_key = Rails.application.credentials.dig(:anthropic, :api_key)
end

# config/initializers/query_translator.rb
QueryTranslator.configure do |config|
  config.model = 'claude-haiku-5-5'      # any RubyLLM model id
  config.confidence_threshold = 0.7      # below it the result counts as unsure
  config.max_query_length = 500          # longer text is cut off
  config.extra_instructions = 'Prices are in US dollars per time slot.' # your own rules, optional
end
```

Keep the key in credentials, never in code.

## Describe what can be searched

One `Resource` per kind of search (usually one API index endpoint), one `Filter` per query param:

```ruby
venues = QueryTranslator::Resource.new(
  name: 'venues',
  path: '/api/v1/venues',
  description: 'Venues and studios for rent in the public catalog',
  filters: [
    QueryTranslator::Filter.new(name: 'by_city_match', type: 'string', description: 'US city name in English'),
    QueryTranslator::Filter.new(name: 'by_capacity_gte', type: 'integer', description: 'Number of guests to fit'),
    QueryTranslator::Filter.new(name: 'available_on', type: 'date', description: 'Date with a free time slot'),
    QueryTranslator::Filter.new(name: 'max_price', type: 'decimal', description: 'Highest price in USD'),
    QueryTranslator::Filter.new(name: 'with_parking', type: 'boolean', description: 'The venue has parking'),
    QueryTranslator::Filter.new(name: 'by_status', type: 'enum', description: 'Listing status',
                                values: %w[draft published], multiple: true)
  ]
)
```

| type | value you get back |
| --- | --- |
| `string` | stripped text |
| `integer` / `decimal` | `Integer` / `Float` |
| `date` / `datetime` | `Date` / `Time` |
| `boolean` | `true` only: a boolean filter can only be switched on |
| `enum` | one of `values` (required for enums) |

`multiple: true` lets a filter take several values ("draft or published") and gives you an array, so Rails builds
`by_status[]=draft&by_status[]=published`.

The `description` is what the model reads: one clear sentence with units and formats does most of the work.

## Translate

```ruby
result = QueryTranslator::Translator.call(query: params[:query], resources: [venues, bookings], today: Date.current)
```

Then handle three cases:

```ruby
if result.clarify?
  # show result.question with a button per result.options;
  # on click, translate again with "#{query} — #{option}"
elsif result.low_confidence?
  # show your filter form, prefilled with result.filters, and a hint to check them
else
  # call result.path with result.filters (or redirect to the matching page)
end
```

`result` also has `resource`, `confidence`, `unmapped` (parts that fit no filter) and `errors` (what the check threw
out). A blank query returns an empty, unsure result without calling the model.

If the model can't be reached, `QueryTranslator::Error` is raised: show the filter form with a short message.

## Claude Code skill

The repository ships a skill that walks a coding agent through the whole setup in another project:
`skills/query-translator-setup/SKILL.md`. Copy that folder into the project's `.claude/skills/` (or into
`~/.claude/skills/` for every project) and ask Claude to "add natural language search". Where `.claude/` is synced
from a shared baseline and must not be edited by hand, use `~/.claude/skills/`.

The skill reads its rules from the installed gem's [AGENTS.md](AGENTS.md), so they match the gem version in
`Gemfile.lock`. The skill file itself is a copy: copy it again after updating the gem.

## Tips

- Cache answers by today's date plus the normalized text: the same text on the same day gives the same filters, and
  "on Saturday" changes meaning every day.
- In your app's tests stub `QueryTranslator::Translator.call`; never call a real model there.
- If a search goes wrong, improve the filter descriptions first.

## Development

```bash
bundle install
bundle exec rake          # specs + RuboCop
```

The specs with real model answers replay recordings from `spec/cassettes/`. To re-record them (needed after any prompt
change), put `ANTHROPIC_API_KEY=...` into `.env`, delete `spec/cassettes/` and run `bundle exec rspec`. The key is
stripped from the recordings.

## License

MIT, see [LICENSE.txt](LICENSE.txt).
