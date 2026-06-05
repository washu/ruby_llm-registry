# RubyLlm::Registry

[![CI](https://github.com/washu/ruby_llm-registry/actions/workflows/ci.yml/badge.svg)](https://github.com/washu/ruby_llm-registry/actions/workflows/ci.yml)

Local-first, versioned prompt storage and rendering for RubyLLM applications.

## What it does

`RubyLlm::Registry` treats prompts as immutable artifacts stored outside your app code. It can:

- load the latest or a specific semantic version
- resolve labels like `production` or `staging`
- read prompt files from a filesystem-backed registry
- render ERB templates with required-variable validation
- export/import prompts as YAML, JSON, or markdown
- compare prompt revisions and surface a field/body diff
- optionally store prompts in SQLite, ActiveRecord, MongoDB, or S3 backends when those gems/services are loaded

## Quick start

```ruby
prompt = RubyLlm::Registry.get("email/summarizer", label: :production)

rendered = prompt.render(
  user_name: "Ava",
  email_body: "Thanks for the update",
  summary_length: "concise"
)

diff = RubyLlm::Registry.diff(prompt, prompt.export(format: :markdown))
puts diff.changed_fields
```

## Optional adapters

The gem stays filesystem-first by default. If you need a different store, opt in explicitly:

```ruby
sqlite = RubyLlm::Registry.database_backend(:sqlite, path: "tmp/prompts.db")

# or, when those integrations are available in your app:
# RubyLlm::Registry.database_backend(:active_record)
# RubyLlm::Registry.database_backend(:mongo, collection: MyCollection)
# RubyLlm::Registry.backend(:s3, client: s3_client, bucket: "my-bucket")
```

All non-filesystem adapters are loaded lazily, so your app only pulls in the storage stack it actually uses.

## Prompt file layout

```text
prompts/
└── email/
	└── summarizer/
		├── v1.0.0.md
		├── v1.1.0.md
		└── v1.2.3.md
```

Each file may include YAML front matter:

```markdown
---
version: 1.2.3
labels: [production]
required_vars: [user_name, email_body]
metadata:
  description: Concise email thread summarizer
---

Hello <%= user_name %>
```

## Development

Run the test suite with:

```bash
bundle exec rspec
```

SimpleCov enforces a 90% minimum coverage threshold, and the latest verified local run is 93%.

The integration specs exercise real fixtures plus optional Docker-backed services:

- SQLite and ActiveRecord use local temp databases
- MongoDB spins up a `mongo:8` container when Docker is available
- S3 uses a `minio/minio` container for compatibility testing

If Docker is unavailable, those examples skip cleanly.

## License

MIT
