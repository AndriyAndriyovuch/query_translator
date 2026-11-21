# QueryTranslator

Перетворює пошуковий запит, написаний звичайними словами, на фільтри, які ваш JSON API вже розуміє.

> *«зала на 50 людей у Чикаго на завтра до $300»*
> → `GET /api/v1/venues?by_city_match=Chicago&by_capacity_gte=50&available_on=2026-11-22&max_price=300.0`

Гем просить мовну модель (через [RubyLLM](https://rubyllm.com)) заповнити суворий бланк відповіді, а потім перевіряє
кожен фільтр за списком, який ви йому дали. Сам пошук лишається за вашим застосунком: гем лише складає запит до API.

[English](README.md) · [Інструкція для агентів (англійською)](AGENTS.md)

## Що він уміє

- **Будь-яка мова і сленг.** «Chi-town», «50k», «днюха», «salón de fiestas» перетворюються на ваші фільтри.
- **Питає, а не вгадує.** На «велика зала» чи «на вихідних» він перепитує і дає 2–4 варіанти відповіді тією ж
  мовою, якою написаний запит.
- **Чесно каже, коли не впевнений.** Якщо частину запиту не можна виразити жодним фільтром («з видом на море»), він
  про це скаже, і ви покажете звичайну форму фільтрів замість неправильних результатів.
- **Кілька видів пошуку.** Для кожного запиту він сам вибирає потрібний, наприклад зали чи «мої скасовані
  бронювання».
- **Безпечна відповідь.** Проходять лише назви фільтрів і значення зі списку. Текст людини для моделі тільки дані,
  тож «ігноруй правила і…» нічого не зробить.

## Що потрібно

- Ruby 3.2+
- Ключ до мовної моделі, яку RubyLLM підтримує зі структурованою відповіддю. За замовчуванням це Claude Haiku 5.5.

## Встановлення

```ruby
# Gemfile
gem 'query_translator', git: 'https://github.com/AndriyAndriyovuch/query_translator.git', branch: 'master'
```

```bash
bundle install
```

## Налаштування

```ruby
# config/initializers/ruby_llm.rb
RubyLLM.configure do |config|
  config.anthropic_api_key = Rails.application.credentials.dig(:anthropic, :api_key)
end

# config/initializers/query_translator.rb
QueryTranslator.configure do |config|
  config.model = 'claude-haiku-5-5'      # будь-яка модель, яку знає RubyLLM
  config.confidence_threshold = 0.7      # нижче цього порогу результат вважається невпевненим
  config.max_query_length = 500          # довший текст обрізається
  config.extra_instructions = 'Prices are in US dollars per time slot.' # ваші правила для моделі, не обов'язково
end
```

Ключ тримайте в credentials, ніколи не в коді.

## Опишіть, що можна шукати

Один `Resource` на кожен вид пошуку (зазвичай це один index-ендпоінт API), один `Filter` на кожен параметр запиту:

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

| тип | що ви отримаєте |
| --- | --- |
| `string` | текст без зайвих пробілів |
| `integer` / `decimal` | `Integer` / `Float` |
| `date` / `datetime` | `Date` / `Time` |
| `boolean` | тільки `true`: такий фільтр можна лише ввімкнути |
| `enum` | одне зі значень `values` (для enum вони обов'язкові) |

`multiple: true` дозволяє фільтру мати кілька значень («draft or published»). Тоді ви отримаєте масив, і Rails
складе з нього `by_status[]=draft&by_status[]=published`.

Модель читає саме `description`. Одне чітке речення з одиницями й форматом дає більшу частину успіху.

## Переклад запиту

```ruby
result = QueryTranslator::Translator.call(query: params[:query], resources: [venues, bookings], today: Date.current)
```

Далі три випадки:

```ruby
if result.clarify?
  # покажіть result.question і кнопку на кожен варіант з result.options;
  # після кліку перекладіть ще раз "#{query} — #{option}"
elsif result.low_confidence?
  # покажіть звичайну форму фільтрів, заповнену з result.filters, і підказку їх перевірити
else
  # викличте result.path з result.filters (або перекиньте на відповідну сторінку)
end
```

У `result` є ще `resource`, `confidence`, `unmapped` (частини запиту, для яких немає фільтра) і `errors` (що
відкинула перевірка). Порожній запит повертає порожній невпевнений результат і в модель не йде.

Якщо модель недоступна, гем кидає `QueryTranslator::Error`: покажіть форму фільтрів з коротким повідомленням.

## Скіл для Claude Code

У репозиторії є скіл, який проводить агента через усе підключення в іншому проєкті:
`skills/query-translator-setup/SKILL.md`. Скопіюйте цю папку в `.claude/skills/` проєкту (або в `~/.claude/skills/`,
щоб він був у всіх проєктах) і попросіть Claude «add natural language search». Якщо `.claude/` проєкту
синхронізується із загальної бази і його не можна міняти вручну, кладіть скіл у `~/.claude/skills/`.

Правила скіл бере з [AGENTS.md](AGENTS.md) встановленого гема, тож вони відповідають версії гема в `Gemfile.lock`.
Сам скіл — це копія: після оновлення гема скопіюйте його ще раз.

## Поради

- Зберігайте відповіді в кеші за сьогоднішньою датою і нормалізованим текстом. Той самий текст того самого дня дає
  ті самі фільтри, а «в суботу» щодня означає іншу дату.
- У тестах застосунку підміняйте `QueryTranslator::Translator.call`. Справжню модель там не викликайте.
- Якщо пошук помиляється, спершу покращте описи фільтрів.

## Розробка гема

```bash
bundle install
bundle exec rake          # тести + RuboCop
```

Тести зі справжніми відповідями моделі програють записи з `spec/cassettes/`. Щоб перезаписати їх (це треба після
будь-якої зміни тексту для моделі), покладіть `ANTHROPIC_API_KEY=...` у `.env`, видаліть `spec/cassettes/` і запустіть
`bundle exec rspec`. Ключ із записів прибирається.

## Ліцензія

MIT, див. [LICENSE.txt](LICENSE.txt).
