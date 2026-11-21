---
name: query-translator-setup
description: Add natural-language search to a Rails app with the query_translator gem — free text in any language becomes validated filters for the app's existing index endpoints, with clarification questions and a fallback to the filter UI. Use when asked to "add natural language search", "search in plain words", "let users type what they need", "text to filters", "NL search", "plug in query_translator", or to make an API searchable by a sentence. Reuses the project's own index endpoints and search services and fits any Rails layout.
version: 1.0.0
updated: 2026-11-21
---

# QueryTranslator — set up natural-language search

You plug the `query_translator` gem into the current Rails project. The gem turns a sentence into filters for the
project's **existing** index endpoints; it never searches by itself. The full rules live in the gem's own `AGENTS.md`
("the guide" below); this skill is the order of work.

## Ground rules

- The host project's own instructions win over this skill wherever they differ: commit policy, comment style, naming,
  layering, test style, who writes the code, how to talk to the developer. Look for them wherever the repository keeps
  them: `AGENTS.md`, `CLAUDE.md`, `.claude/rules/`, `.claude/instructions/`, `.github/copilot-instructions.md`,
  `.github/instructions/`.
- Never create, read or print credential keys. The developer adds the LLM key.
- Never call a real model from the app's test suite.
- Ask the developer one question at a time, with options, when a decision is theirs (which resources, which pages,
  guest access, the LLM provider, a rate limit, creating try-out data). Do not guess business rules.

## Steps

### 1. Check the starting point

- Rails app? Ruby 3.2+? Is `query_translator` already in `Gemfile`? If yes, find what exists
  (`grep -rln "QueryTranslator" app business lib config spec 2>/dev/null`) and continue from the first missing step.
- Does the project already call an LLM (`ruby_llm`, `ruby-openai` or `anthropic` in `Gemfile.lock`)? Then the provider
  is a question in step 4, and an existing `ruby_llm` must allow `~> 2.2`.
- Find the project's search layer (search or query objects, e.g. `app/services/search/*.rb`) and the controllers
  whose index actions filter: API ones under `app/controllers/api/**` and, in a monolith, HTML ones that call a search
  service. Is there an HTML UI (Hotwire/views), or is the app API-only?

### 2. Add the gem and read its guide

```ruby
gem 'query_translator', git: 'https://github.com/AndriyAndriyovuch/query_translator.git', branch: 'master'
```

Run `bundle install`, then read the whole guide from the installed copy before writing any code:

```bash
cat "$(bundle info query_translator --path)/AGENTS.md"
```

If that fails, stop and tell the developer; do not work from memory. This skill is written for guide version 1.x (see
its frontmatter); if the major version differs, ask the developer to copy the skill again from the gem's repository.
Everything below refers to the guide's sections (§).

### 3. Propose the resources — and get them approved

Do §4 step 3 and step 4: inventory the index endpoints, read their permitted params, model enums and scopes, and map
every useful param to a filter (name exactly as the endpoint takes it, type, one-sentence description, enum values
from code, `multiple:` where arrays are accepted). Database lists only from small shared tables the staff manages
(categories, regions); never per-tenant or per-user records, names users type, or people: every name goes into the
prompt of every call and can come back in a question (§7).

Show the developer a compact table per resource (name, path, who may call it, filters) and ask which resources to
include. Do not write code before they confirm.

### 4. Provider, key and initializers

- Provider: Anthropic with `claude-haiku-5-5`, the gem's tuned default. If the project already calls another LLM, ask
  which one to use; another provider needs a model with structured output in RubyLLM, its own key setting, and the
  step 8 run on that model.
- Ask the developer to add the key to the credentials of development and of every deployed environment
  (`anthropic: api_key:` by default), not test: specs stub the translator, and without a key a forgotten stub fails
  loudly instead of spending money.
- `config/initializers/ruby_llm.rb` (or the project's existing RubyLLM setup): the key from the credentials
  (`Rails.application.credentials.dig(:anthropic, :api_key)`, or the project's own credentials helper), plus
  `config.request_timeout = 15` and `config.max_retries = 1`, because a user waits on this call and RubyLLM's
  defaults are 300 s and 3 retries. Both settings are global: if the app already uses RubyLLM for long jobs, ask
  first.
- `config/initializers/query_translator.rb`: `model`, `confidence_threshold`, `max_query_length`, and a one- or
  two-sentence `extra_instructions` with domain facts (currency, units, market).

### 5. Business objects

Per §4 step 5: one object builds the resources from code constants (and the database lists at request time, skipped
when empty); another calls the gem, caches the answer by date + normalized text, and adds app-specific clarification
questions that need the database. Neither writes to the database. Put them where the project keeps business logic
(service objects, actions, operations), as the kind its rules let a controller call. If the resources ever differ per
user or role, put that in the cache key too.

### 6. Endpoints and UI

Per §4 step 6 and §5:

- API (when the searched index endpoints are API endpoints): `GET /api/v1/natural_search?query=` returning the ready
  call; guests allowed when at least one searched endpoint is public (a private resource is still translated, and its
  own page asks for sign-in, §5).
- HTML (only if the app has one): a search box where the developer wants it (ask; offer to draw options if the project
  asks for visual choices), a question page with one button per option, a low-confidence hint on the result page,
  "what we searched for" chips with a remove link each.
- On `QueryTranslator::Error`: log it (and report it to the project's error tracker, if any), then the API answers 503
  with a plain translated sentence and the web redirects to the plain filter page with a short message, never a 500.
- Carry the original text to the result page in a param that page does not filter by (`query` is taken where a page
  has a full-text filter). An answer button sends `"<text> — <option>"`; trim the text so it all fits
  `max_query_length`, because the gem cuts anything longer.
- A public endpoint pays for every new text: ask the developer whether to rate-limit the natural-search actions on
  their own (§7).
- Every string in every locale file; the box `maxlength` from `QueryTranslator.config.max_query_length`.

### 7. Specs

Per §4 step 7: a helper that builds a real `QueryTranslator::Result` from the app's resources, the translator stubbed
with `allow(QueryTranslator::Translator).to receive(:call)`, specs for the business object, the API endpoint
(acceptance/request spec in the project's style) and the web flow, each with its `QueryTranslator::Error` fallback,
and one for an empty database list.

Then run the checks the project defines (its own `AGENTS.md`/`CLAUDE.md`, a verification skill or script, its CI
config). Where it defines none: the full suite, the linter, and `brakeman` and `bundler-audit` if the bundle has them.

### 8. Try it live

Per §4 step 8, once the developer has added the key: a throwaway script outside the repository, run with
`bin/rails runner`, sends 30+ realistic queries through the step 5 object that calls the gem, on development data —
every filter, other languages, slang, typos, relative dates, several values, negations, vague words, off-topic and
hostile text.

- Its first line is `Rails.cache = ActiveSupport::Cache::NullStore.new`, so a re-run reaches the model instead of
  replaying today's cached answers. Never `Rails.cache.clear`: it can wipe a Redis database other apps share.
- Use the data that is already there. If a case needs records that are missing, ask before creating any, and remove
  them at the end.
- Fix wrong answers by improving descriptions, not the gem, and run the set again.

### 9. Report

- files added and changed;
- the resources and filters that went in, and what was left out and why (ids, geo, positional pairs, private lists);
- the live results: how many queries, what works, what still goes wrong;
- try-out records created and whether they were removed (with the cleanup command), or "none";
- anything the developer must do: add the key to every deployed environment before deploying (without it every search
  fails with a 500), review, commit (if the project leaves that to them), switch a `path:` gem source to `git:`, decide
  on a rate limit if that is still open.

Finish with the guide's hand-over checklist (§10).
