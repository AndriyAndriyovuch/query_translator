---
version: 1.0.0
updated: 2026-11-21
---

# QueryTranslator — integration guide for coding agents

You are wiring `query_translator` into a Ruby/Rails application so its users can search in plain language. This file
tells you how to do that correctly. Follow it step by step and do not improvise around the rules marked **MUST**.

The human-facing overview is in [README.md](README.md). This file is the authority when the two differ.

---

## 1. What the gem does and does not do

**Does:** takes free text plus a list of resources (kinds of search) and their filters, asks an LLM through RubyLLM to
fill in a strict JSON form, checks every returned filter against the list, casts values to their types, and returns a
`QueryTranslator::Result`: which resource, which filters, how confident, what did not fit, and an optional
clarification question with answer options.

**Does not:** query your database, call your API, render anything, cache, authorize, rate-limit, or know anything about
your domain beyond what your filter descriptions say. All of that is the app's job and is described below.

Data flow:

```text
user text ─► app builds resources ─► Translator.call ─► LLM (structured output, schema with enums)
                                                    ◄─ answer form
                                       FilterCheck: known names only, values cast, wrong ones reported
                                    ◄─ Result(resource, filters, confidence, unmapped, errors, question, options)
app ─► question?  → show options, re-translate "<text> — <option>"
    ─► unsure?    → show the normal filter form prefilled with result.filters
    ─► otherwise  → call / redirect to result.path with result.filters (through the normal index endpoint)
```

---

## 2. Hard rules

1. **MUST** keep the LLM key in the app's credentials (or ENV through the project's credentials helper). Never in code,
   specs, fixtures or logs.
2. **MUST** name every filter exactly as the API endpoint accepts the query param. The gem returns those names as hash
   keys and the app puts them into the URL unchanged.
3. **MUST** take enum values from code (model `enum` definitions, constants), never from database rows of a production
   system you can't see. Lists that live in the database (categories, tags) are built at request time inside the app.
4. **MUST** send results through the normal index endpoint and its authorization/policy scope. The gem only builds
   filters; it never widens what a user may see.
5. **MUST NOT** pass filter names or values to `send`, `public_send`, `constantize`, `order(params...)` or SQL without
   the endpoint's own whitelist. The gem guarantees names and enum values come from your list, but keep the endpoint's
   whitelist (`PERMITTED_ATTRIBUTES`) as the second wall.
6. **MUST** handle all three outcomes: `clarify?`, `low_confidence?`, confident. Showing results for an unsure answer
   without a hint is a bug.
7. **MUST** rescue `QueryTranslator::Error` and fall back to the normal filter UI (web) or a 503 with a plain sentence
   (API). Never show the provider's error message to users.
8. **MUST NOT** call the real model in the app's test suite. Stub `QueryTranslator::Translator.call`.
9. **MUST** describe every boolean filter as something that is switched on (see §6.4). The gem only ever sends `true`.
10. **MUST NOT** edit the gem's prompt to fit one app. App-specific wording goes into filter descriptions, resource
    descriptions or `config.extra_instructions`.

---

## 3. Public API reference

### 3.1 Configuration

```ruby
QueryTranslator.configure do |config|
  config.model = 'claude-haiku-5-5'   # default; any RubyLLM model id with structured output support
  config.confidence_threshold = 0.7   # default; Result#low_confidence? is true below it
  config.max_query_length = 500       # default; longer text is cut before it reaches the model
  config.extra_instructions = nil     # default; text appended to the prompt as "More rules from the app"
end

QueryTranslator.config.model        # read anywhere
```

RubyLLM itself is configured by the app (provider key, timeouts):

```ruby
RubyLLM.configure do |config|
  config.anthropic_api_key = RCreds.fetch(:anthropic, :api_key) # or credentials.dig(...)
end
```

Haiku is the default on purpose: the gem was tuned on it across eight projects. If Haiku handles a project, larger
models do too; do not switch models to fix a bad filter description.

### 3.2 `QueryTranslator::Filter`

```ruby
QueryTranslator::Filter.new(name:, type:, description:, values: nil, multiple: false)
```

| field | meaning |
| --- | --- |
| `name` | the API query param, exactly (`by_status`, `by_price_gte`, `order_by[start_date]`) |
| `type` | one of `string integer decimal date datetime boolean enum` |
| `description` | one sentence the model reads; see §6 |
| `values` | allowed values; **required** for `enum`, ignored otherwise |
| `multiple` | `true` when the endpoint accepts several values (`by_x[]=a&by_x[]=b`) |

`Filter.new` raises `ArgumentError` for an unknown type or an `enum` without values. That happens when the resources
are built, so a broken list fails loudly at the first request, not silently.

### 3.3 `QueryTranslator::Resource`

```ruby
QueryTranslator::Resource.new(name:, path:, description:, filters:)
```

`name` is what the model picks (`venues`, `bookings`); `path` is the index endpoint the result points to;
`description` tells the model when to choose this resource. Both are plain `Data` objects (immutable, `#with` works).

### 3.4 `QueryTranslator::Translator`

```ruby
result = QueryTranslator::Translator.call(query: text, resources: [res_a, res_b], today: Date.current)
```

- `today` defaults to `Date.today`; pass the app's `Date.current` so "tomorrow" follows the app's time zone.
- A blank query returns `Result.empty` without calling the model.
- Raises `QueryTranslator::Error` when RubyLLM fails (network, provider error) or the model returns no JSON.
  `RubyLLM::ConfigurationError` (no key) is **not** wrapped: it is a setup error and should crash loudly.

### 3.5 `QueryTranslator::Result`

| member | meaning |
| --- | --- |
| `resource` | the chosen `Resource` or `nil` |
| `path` | `resource&.path` |
| `filters` | `{ "name" => cast_value }`; an array for `multiple` filters |
| `confidence` | the model's own score, 0..1 |
| `unmapped` | parts of the request, in the user's words, that no filter can express |
| `errors` | what `FilterCheck` threw out (unknown filter, bad value, several values for a one-value filter, `false` for a boolean) |
| `question`, `options` | a clarification question and 2–4 answer options, in the request's language; empty strings/arrays when none |
| `clarify?` | a question is present |
| `low_confidence?` | `confidence < threshold` **or** no filters **or** anything unmapped **or** any error |

Cast values: `string` → stripped `String`, `integer` → `Integer` (base 10), `decimal` → `Float`, `date` → `Date`,
`datetime` → `Time` (ISO 8601), `boolean` → `true`, `enum` → `String` from `values`. Rails turns them into URL params
(`Date#to_param` → `2026-11-22`, arrays → `name[]=…`). A `Time` becomes `2026-11-01 00:00:00 UTC`; call `#iso8601` on
it first when the API or the client expects ISO strings.

### 3.6 `QueryTranslator::FilterCheck`

Usable on its own, e.g. to validate filters that came from somewhere else:

```ruby
check = QueryTranslator::FilterCheck.call(resource: res, filters: { 'by_status' => %w[draft paid], 'x' => 1 })
check.filters # => { "by_status" => ["draft", "paid"] }
check.errors  # => ["unknown filter x"]
```

`nil` values are skipped silently.

---

## 4. Integration, step by step

The paths below follow the COAX Rails template (ABDI: `app/`, `business/`, `data/`, `infrastructure/`, Readymade,
`action_scope` search services). In another layout keep the same separation: resources and translation in a business
object, thin controllers.

### Step 1 — Gemfile

```ruby
gem 'query_translator', git: 'https://github.com/AndriyAndriyovuch/query_translator.git', branch: 'master'
```

Pin a `ref:` or `tag:` instead of `branch:` when the project needs reproducible builds. Run `bundle install` and
confirm `Gemfile.lock` has a `GIT` block for the gem. Never commit a `path:` source: CI and servers don't have it.

### Step 2 — key and initializers

1. Ask the developer to add the key to the credentials of each environment (`anthropic: api_key:`). You do not
   create or read credential keys yourself.
2. `config/initializers/ruby_llm.rb` — provider key from credentials (see §3.1).
3. `config/initializers/query_translator.rb` — model, threshold, length, and `extra_instructions` with domain facts
   the model cannot guess (currency, units, market), one or two sentences.

### Step 3 — inventory the searchable endpoints

For every index endpoint a user might want to search in words:

1. Find the controller action (`app/controllers/api/**`), its route (`config/routes.rb`), the search service it calls
   (`app/services/search/*.rb`), and the permitted params (`PERMITTED_ATTRIBUTES`, `params.permit(...)`).
2. Read the model (`data/*.rb` or `app/models/*.rb`): enums, custom scopes, and what `action_scope` generates
   (`Model.options_for_search` lists generated scopes; read the gem source when unsure).
3. Note who may call the endpoint (guest, client, owner, admin) and what scope the policy applies.
4. Pick the 2–5 resources users actually ask about. Not every index needs to be searchable in words.

Many COAX APIs expose `GET /api/v1/metadata` with every search service's `FORM_OPTIONS`: a quick way to see the real
param names and enum values.

### Step 4 — map params to filters

`action_scope` / Readymade conventions and how to describe them:

| API param | filter type | description pattern |
| --- | --- | --- |
| `by_<col>` on an enum column | `enum`, `values:` enum keys, `multiple: true` if arrays are accepted | "Booking status" |
| `by_<col>` on a string column | `string` | "Exact deal number, e.g. D-0042" — say **exact** |
| `by_<col>_match` | `string` | "Part of the city name" — say **part of** |
| `by_search_query` / `by_free_text` / `q` | `string` | "Free-text search by name, code and email" — list the fields |
| `by_<col>_gte` / `_lte` (numbers) | `integer` / `decimal` | "Lowest price in USD", "Highest price in USD" |
| `by_<col>_gte` / `_lte` (date column) | `date` | "Due on or after this date" |
| `by_<col>_gte` / `_lte` (datetime column) | `datetime` | "Created at or after this moment" |
| `<col>_from` / `<col>_to` | `date` | if `_to` excludes the day itself, **say so**: "before this date (the date itself is not included)" |
| `with_<thing>` / `has_<thing>` | `boolean` | "Only invoices past their due date" — see §6.4 |
| `sort_by_<col>` | `enum`, `values: %w[asc desc]` | "Sort by expected value" |
| `order_by[<col>]` (nested hash) | `enum`, name `"order_by[<col>]"`, `values: %w[asc desc]` | one filter per sortable field |
| `sort=<word>` | `enum` with the words | "Order of the results: newest, name or lowest price" |
| `by_<x>_within_days`, `by_stale_days` | `integer` | "Decision expected within this many days from today" |

Skip, unless the API accepts a human-readable value:

- foreign keys (`by_user`, `by_project`, `by_<association>`): the model can't know ids;
- `_gt` / `_lt` duplicates of `_gte` / `_lte`; exact-match datetimes; `_gte` on enum integers;
- params the gem cannot express (§9): geo tuples, positional pairs (`range[]=start&range[]=end`), nested hashes other
  than one-key `order_by[...]`.

**Database-driven lists** (categories, tags, regions) become an `enum` of ids built at request time, with the
id–name pairs in the description, and hierarchy shown when the scope includes children:

```ruby
def category_filters
  return [] if categories.empty?   # an enum without values raises

  [ filter('by_category_tree', 'enum',
           "Kind of place by category id. A category includes its subcategories, so pick the broader one unless " \
           "the request names an exact kind: #{categories.map { |c| category_name(c) }.join(', ')}",
           categories.map { |c| c.id.to_s }) ]
end

def category_name(category)
  [ "#{category.id} #{category.name}", ("(in #{category.parent_id})" if category.parent_id) ].compact.join(' ')
end
```

### Step 5 — the business objects

ABDI: no database writes → **Actions**. Suggested files (replace `NaturalSearches` with the project's naming):

```text
business/natural_searches/actions/build_resources.rb   # returns [Resource, ...]
business/natural_searches/actions/translate.rb         # cache + gem call + app-specific clarifications
```

`BuildResources` builds `QueryTranslator::Resource` objects with private helpers (`venue_filters`, `filter(...)`),
reading constants (`Search::X::SORTS`, `Model.statuses.keys`, `Model::AMENITIES`) so the list follows the code.

`Translate` (sketch, adapt names):

```ruby
class NaturalSearches::Actions::Translate < BaseAction
  attr_reader :query, :venues

  def call
    translation
  end

  private

  def translation
    @translation ||= Rails.cache.fetch(cache_key, expires_in: 1.day) { answer(translate) }
  end

  def translate
    QueryTranslator::Translator.call(query: query, resources: NaturalSearches::Actions::BuildResources.call,
                                     today: Date.current)
  end

  def answer(result)
    { resource: result.resource&.name, path: result.path, filters: result.filters, confidence: result.confidence,
      low_confidence: result.low_confidence?, unmapped: result.unmapped, question: result.question,
      options: result.options }
  end

  def cache_key
    [ 'natural_search', Date.current.iso8601, Digest::SHA256.hexdigest(query.to_s.squish.downcase) ]
  end
end
```

- Cache a plain hash: it serializes cleanly to Redis and to JSON.
- The **date is part of the cache key** because relative dates ("on Saturday") change meaning every day.
- Cache only the translation. Never cache search results here.
- App-specific questions that need the database belong here, after the gem: e.g. venue_hub asks "Which state?" when
  the translated city has published venues in several states, and that question **wins** over a city question the
  model may have asked (its options come from real data).

### Step 6 — controllers

API (returns the ready call; the client makes the second request itself):

```ruby
class Api::V1::NaturalSearchesController < Api::V1::BaseController
  allow_guests # only if the searched endpoints are public

  rescue_from QueryTranslator::Error do
    error_response('Service Unavailable', I18n.t('natural_searches.unavailable'), 503)
  end

  def index
    render json: { natural_search: NaturalSearches::Actions::Translate.call(query: params[:query].to_s,
                                                                             venues: scoped_collection) }
  end

  private

  def record_class
    Venue # the Authorizer concern needs a model for its policy check
  end
end
```

Web (redirects to the normal page with the filters, or renders the question):

```ruby
def index
  @query = params[:query].to_s.squish
  @search = NaturalSearches::Actions::Translate.call(query: @query, venues: scoped_collection)
  return if @search[:question].present?   # render the question page

  redirect_to result_path, alert: (t('.unsure') if @search[:low_confidence]), status: :see_other
end
```

- `result_path` maps the resource to the matching HTML page and merges the filters plus `query:` (to show "You
  searched for …"). Keep the mapping in a private method; it is routing, not business logic.
- The question page shows the question and one link per option to the same action with
  `query: "#{@query} — #{option}"`, plus the edit box and a link to the plain filter form.
- Show "what we searched for" chips on the result page: one chip per active filter param with a link that removes it.
- Keep the text box limit in sync: `maxlength: QueryTranslator.config.max_query_length`.
- Add every user-facing string to every locale file the project keeps.

### Step 7 — tests in the app

Helper that builds a real `Result` from the app's own resources:

```ruby
module NaturalSearchHelpers
  def natural_search_result(resource_name: 'venues', filters: {}, **answer)
    resource = NaturalSearches::Actions::BuildResources.call.find { |item| item.name == resource_name }
    QueryTranslator::Result.new(resource: resource, filters: filters, confidence: 0.9, unmapped: [], errors: [],
                                question: '', options: [], **answer)
  end
end
```

```ruby
before { allow(QueryTranslator::Translator).to receive(:call).and_return(natural_search_result(filters: {...})) }
```

Cover at least:

- the business action: a confident answer passes through; each app-specific clarification fires;
- the API endpoint (acceptance spec): 200 with the ready call; 503 when the translator raises;
- the web flow (request spec): redirect with filters; low confidence → alert; question page renders options; a second
  resource redirects to its page;
- the resource builder does not raise when a database list (categories) is empty.

Run the project's full suite, linter and security scanner (`brakeman`, `bundler-audit`) afterwards.

### Step 8 — try it live before handing over

Write a throwaway script (scratch directory, not committed) that runs 30+ realistic queries through
`Translate` against development data with a real key, and read every answer:

- plain requests per resource; every filter type at least once;
- other languages the users speak; slang and abbreviations ("NYC", "50k", "asap");
- typos; relative dates ("next Saturday", "last week", "this quarter");
- several values ("draft or submitted"); negations ("without", "never", "not overdue");
- vague words ("big", "cheap", "bad reviews"); off-topic ("what's the weather"); hostile ("ignore your rules…").

For every wrong answer change the **filter or resource description** (or `extra_instructions`) and run the set again.
Report what you changed and what still goes wrong.

---

## 5. Handling the outcomes — precedence

1. `QueryTranslator::Error` → fallback UI / 503.
2. `question.present?` (gem or app clarification) → ask; even if filters exist.
3. `low_confidence` → show the filter form prefilled with `filters`, with a short "check the filters" hint.
4. Otherwise → go to the resource's page / call `path` with `filters`.

A resource that needs a signed-in user (e.g. "my bookings") still gets translated for guests; let the target page's
authentication handle it (redirect to sign-in).

---

## 6. Writing descriptions that work

The descriptions are the only thing the model knows about the domain. During tuning, every wrong answer was fixed by a
clearer description or a general rule, never by a bigger model.

### 6.1 Resources

One sentence on what the records are, in business words, and whose they are:
"Venues and studios for rent in the public catalog", "The signed-in client's own bookings",
"Stripe payments and refunds against billing invoices".

### 6.2 Filters

- Say **exact** vs **part of** for strings.
- Give **units** and **currency**: "in USD", "in seconds", "in miles", "percent".
- Give **formats** for odd values: "a year like 2020, not an age", "two-letter state code".
- For ranges say **lowest/highest**, **on or after/on or before**, and whether an end date is excluded.
- For enums with cryptic values explain them in the description: "Priority: 0 is P0 (highest) … 3 is P3",
  "krytter is a hunting-license invoice".
- For free-text filters list the fields searched.
- Keep it to one sentence. The model sees every filter of every resource on each call.

### 6.3 What the model already does well (don't fight it)

Abbreviations and slang for places, amounts like "50k" or "10 grand", relative dates and periods (it sets both ends of
a range), converting hours/days into seconds (8-hour working days), "over 40 hours" → `_gte 144001`, exact values
through `_gte` + `_lte`, quarters, "this week" with exclusive ends when the description says so.

### 6.4 Booleans

Most COAX `with_*` scopes switch on for **any** non-blank value, so `with_x=false` returns the opposite of what the user
asked. The gem therefore treats every boolean as a switch: the prompt tells the model to send only `"true"`, and
`FilterCheck` drops a `false` and reports it (the result becomes unsure). Describe booleans as what they turn on:
"Only payments that have at least one refund". A negation ("never refunded") goes to another filter when one fits (a
status) or ends up in `unmapped` — the user then sees the filter form, not wrong results.

### 6.5 `extra_instructions`

For facts that apply to every filter: currency, units, market, time zone conventions. Not for per-filter wording.

---

## 7. Security

- **Prompt injection:** the user's text goes in as the user message; the system prompt says it is data. The response
  schema only allows your resource names and filter names, and enum values are checked again in Ruby. A hostile
  request ends up with no filters and low confidence.
- **Allowed values only:** enum values come from your list; never forward a free-form value into code that dispatches
  on it (`send(kind)`). If the project already has such a scope, flag it to the developer.
- **Authorization** stays in the index endpoints (§2.4). The natural-search endpoint only returns filters.
- **Cost:** every uncached request is one LLM call (fractions of a cent on Haiku). Cache by day + text; add the
  project's usual rate limiting if the endpoint is public.
- **Privacy:** the model sees the user's text and your filter descriptions (including database-driven names like
  categories). Don't put personal data into descriptions.

---

## 8. Testing the gem itself (when you change it)

- `bundle exec rake` runs specs and RuboCop.
- `spec/query_translator/realistic_queries_spec.rb` replays real model answers from `spec/cassettes/` (VCR). Any change
  to the prompt or the schema changes the request body, so playback fails until you re-record: put
  `ANTHROPIC_API_KEY=...` (a key that belongs to an Anthropic workspace) into the gem's gitignored `.env`, delete
  `spec/cassettes/`, run `bundle exec rspec`, then check that no key is in the recordings
  (`grep -ri "x-api-key\|sk-ant" spec/cassettes` must print nothing).
- Without a key the cassettes replay and nothing is recorded; non-200 answers are never recorded.

---

## 9. Known limitations

- One resource per request. "Show me deals and contacts" picks one or asks.
- No OR across different filters ("in Chicago or under $100").
- No geo search, positional pairs or arbitrary nested hashes; only one-key `order_by[...]`.
- Dates and datetimes come back without a time zone of the app (datetimes in UTC); `today` is the only clock input.
- The model's `confidence` varies a little between calls; that is why `low_confidence?` also uses hard rules.
- Free-form string enums in the database (a Jira status, an environment name) are best described as `string` with
  examples, not as `enum`, unless the values are fixed in code.

---

## 10. Hand-over checklist

- [ ] Gem from `git:` (not `path:`) in the Gemfile, lockfile updated.
- [ ] Key in credentials, both initializers present, model set explicitly.
- [ ] Every filter name equals a permitted param of its endpoint; enum values come from code.
- [ ] Booleans described as switches; ranges say lowest/highest and whether ends are included.
- [ ] Database-driven enums skip themselves when empty.
- [ ] Translation cached by date + normalized text.
- [ ] API endpoint returns the ready call; 503 on `QueryTranslator::Error`.
- [ ] Web flow: question page, low-confidence hint, redirect with filters, "what we searched for" chips.
- [ ] All strings in every locale.
- [ ] App specs stub the translator; full suite, linter and security scan green.
- [ ] 30+ live queries tried and the results reported to the developer.
