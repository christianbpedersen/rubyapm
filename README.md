# RubyAPM

Rails-specific application performance monitoring. A gem in your Rails app
measures where every request and job spends its time (controller Ruby,
custom classes, views, ActiveRecord, the database, GraphQL resolvers,
external APIs, cache), aggregates it in-process, and ships compact batches to
the RubyAPM server, a Rails app that stores per-minute rollups and lets you
drill down from an app overview to a single SQL statement or trace.

```
server/        the RubyAPM Rails app: ingest API + dashboard (port 4400)
sample_app/    "Shopwell", a Rails 8 shop with the agent installed (port 4500)
fake_services/ stand-ins for payment/inventory/shipping/email APIs (port 4501)
bin/           start, stop, simulate, deploy-chirpbin, update-docs-agent, …
```

The agent gem lives in its own public repository,
[christianbpedersen/ruby_apm](https://github.com/christianbpedersen/ruby_apm),
together with the wire protocol (`docs/PROTOCOL.md` there). This repo uses it
from a git tag: the server in its tests, and the Shopwell sample app.
Releasing an agent change: commit and tag in `ruby_apm`, then bump the tag in
the monitored apps' Gemfiles, `sample_app/Gemfile`, `server/Gemfile`, and run
`bin/update-docs-agent <tag>` for docs.chirpbin.com.

## Running the demo

```bash
bin/start                         # server, fake APIs and sample app in the background
bin/start-simulation --rps 15     # traffic generator (log/simulate.log)
open http://localhost:4400        # dashboard
bin/stop                          # stops everything, including the simulation
bin/deploy-sample --regression    # ship a slow build of the sample (then --rollback)
```

First-time setup (Ruby 3.3.5 via rbenv, local Postgres): `bin/setup`.

The simulator mixes HTML pages, a JSON API, checkout (`POST /orders`),
GraphQL operations and background jobs, varies throughput in a 10-minute
wave, and every 20 minutes stages a 2-minute slow-payments incident
(`--incident-every 0` disables it), which you can zoom into on the charts.

## The agent

```ruby
# Gemfile
gem "ruby_apm", git: "https://github.com/christianbpedersen/ruby_apm.git", tag: "v0.2.0"

# config/initializers/ruby_apm.rb
RubyAPM.configure do |c|
  c.app_name = "Shopwell"
  c.api_key  = ENV["RUBY_APM_API_KEY"]
  c.endpoint = "http://localhost:4400"
end
```

What is instrumented automatically:

| Layer | Source |
|---|---|
| Middleware / Rack | `RubyAPM::Middleware` inserted first in the stack |
| Controller (Ruby) | `process_action.action_controller` |
| View | `render_template/partial/collection/layout.action_view` |
| ActiveRecord | `Relation#exec_queries`, `find_by_sql`, `calculate`, `pluck`, `save`, `destroy`, instantiation |
| Database | `sql.active_record`, with obfuscated SQL, per-statement histograms, N+1 detection |
| GraphQL | graphql-ruby tracer: operation-named transactions, parse/validate/analyze/execute, per-field resolvers, Dataloader sources |
| External APIs | `Net::HTTP` (also covers Faraday's default adapter, HTTParty and most SDKs) |
| Cache | `cache_*.active_support` |
| Jobs | `perform.active_job` (own transactions) and `enqueue.active_job`; native Sidekiq workers via server/client middleware |
| Runtime | per process, every flush: RSS, CPU, GC count/time, allocations, threads, DB pool usage |
| Custom code | `include RubyAPM::MethodTracer; trace_method :foo`, `RubyAPM.trace("name") { }`, or `auto_instrument_paths` |

Time is attributed as **exclusive** time (a segment's duration minus its
children), so the layers of a request add up to its duration. Dataloader
fibers are handled: a segment stops accruing time while its fiber is
suspended.

### Built for high-throughput apps

- No per-request I/O. Finished transactions are merged into per-minute
  buckets in memory under a short mutex; the payload size depends on the
  number of distinct transaction/segment/SQL names, not on request volume.
- A background thread drains the buckets every `flush_interval` (10 s) and
  POSTs one gzipped MessagePack document over a persistent connection.
- Bounded memory: caps on transaction names, SQL statements, traces, slow
  query samples and segments per trace; undelivered data is retried with at
  most 10 minutes kept.
- Fork-safe (Puma cluster, Unicorn): the reporter restarts in each worker.
- SQL literals are stripped in the app; raw SQL and bind values used for
  `EXPLAIN` never leave the process.

Measured overhead (`bench/overhead.rb` in the gem repo: a Rack app running 15
ActiveRecord queries against in-memory SQLite, i.e. a worst case where every
query is ~60 µs): about 140 µs per request, roughly 9 µs per query, mostly
ActiveSupport::Notifications dispatch and segment bookkeeping. With real
database round trips that is well under 1% of request time. Draining and
encoding 3,300 requests' worth of data took 0.1 ms and produced about 1 KB.

Useful settings: `apdex_t`, `trace_threshold`, `slow_query_threshold`,
`explain_slow_queries`, `ignored_errors`, `ignore_paths`,
`graphql_field_trace_threshold`, `auto_instrument_paths`,
`instrument_instantiation` (off by default; model instantiation is already
counted inside the ActiveRecord segments).

## The server

- `POST /api/v1/ingest` (Bearer API key) folds a payload into rollup tables
  with one multi-row `INSERT … ON CONFLICT` per table. Latency histograms are
  merged with an element-wise array sum (`nf_array_add`). In development an
  unknown API key registers its app automatically.
- Single tenant: one installation, any number of monitored apps. Agents
  authenticate with their app's API key.
- Users: everyone signs in with email and password (bcrypt, rate-limited).
  Admins add users under *Users*; RubyAPM sends no email, so adding someone
  (or resetting a password) gives the admin a setup link to pass on, valid
  for three days and only until a password is set. Members see every app;
  admins also manage users. The last admin can't be removed or demoted.
  First admin: `bin/rails rubyapm:create_user EMAIL=you@example.com` prints
  a setup link. The account page lists signed-in browsers, API tokens and
  connected MCP clients, each revocable.
- Single sign-on: SAML 2.0 with OneLogin (or any SAML IdP), set up by an
  admin under *Users → Single sign-on*. The page lists the values to enter at
  the IdP (entity ID `…/saml/metadata`, ACS `…/saml/acs`) and takes the IdP's
  metadata URL or XML. Users are matched by email; optionally, unknown people
  from allowed domains get a member account on first sign-in. Password
  sign-in can be limited to admins as a break-glass. Responses must be signed
  by the IdP's certificate, addressed to this SP, unexpired, answer the
  pending request (when SP-initiated), and each assertion works once.
- Alerts: per-app policies (Apdex, error rate, p95, average, throughput,
  external API latency, slow queries), evaluated every minute over complete
  minutes, with incidents that open and resolve and Slack-compatible webhook
  notifications. New apps get three defaults.
- Deployments: the first time an agent reports a new revision it is
  recorded as a deploy, drawn on every chart, and compared before/after
  (app-wide and per transaction, with overlapping incidents called out).
  `bin/deploy-sample [--regression|--rollback]` redeploys the sample.
- The dashboard has a light and a dark theme (toggle at the top right; it
  follows the OS until you pick one, and remembers your choice per browser).
- Dashboard pages: Overview, Transactions, transaction detail, trace
  waterfall, Database, SQL statement, Slow queries (with EXPLAIN plan
  analysis), GraphQL, External APIs, Code & classes, Errors, Alerts, Deployments,
  Hosts & runtime. Every
  chart supports drag-to-zoom, and the time window follows you through every
  drill-down link.
- Storage: per-minute rollups per transaction, segment, SQL statement and
  error, plus app-wide totals per minute for overview charts. An hourly
  maintenance thread folds minute rows older than 24h into hourly rows and
  deletes data older than `RETENTION_DAYS` (default 8); `bin/rails
  rubyapm:maintain` does the same from cron. Histograms are merged in
  Postgres with a PL/pgSQL `nf_array_add`/`nf_hist_sum`.
- Scale check: `bin/rails rubyapm:demo_backfill` creates a demo app with a
  week of history replayed from a live one (~4M minute rows before
  compaction); `bin/page-timings APP_ID` times the main pages. With that
  week, every page renders in under 1 s for the 7d range (it was up to 29 s
  before compaction and query tuning).

## MCP server

`POST /mcp` speaks the Model Context Protocol (Streamable HTTP, stateless,
JSON responses), so an assistant can ask the APM questions directly. All
tools are read-only and return JSON with links back to the dashboard:

| Tool | |
|---|---|
| `apm_list_apps` | apps with their last hour at a glance |
| `apm_app_overview` | web/job summaries, time per layer, top transactions, incidents, deploys |
| `apm_timeseries` | rpm, avg, p95/p99, error rate, Apdex per bin, app-wide or for one transaction |
| `apm_transactions` | transactions ranked by total time, avg, p95, rpm, errors or Apdex |
| `apm_transaction_detail` | one transaction: layers, costly segments and SQL, errors, slowest traces |
| `apm_trace` | a sampled slow request as a call tree |
| `apm_sql` / `apm_slow_queries` / `apm_sql_statement` | SQL ranking, N+1 flags, slow queries, EXPLAIN plans and findings |
| `apm_errors` | error groups; with a fingerprint, the backtrace and affected transactions |
| `apm_external_services` | outbound HTTP by host |
| `apm_deployments` | deploys; with an id or revision, a before/after comparison |
| `apm_incidents` | alert policies and incidents |

RubyAPM is its own OAuth 2.1 authorization server, so the endpoint needs
nothing in front of it. Every call carries a bearer token:

- **Claude (claude.ai, Desktop) and other OAuth clients**: add
  `https://<host>/mcp` as a custom connector. The client finds the server
  through the 401's `resource_metadata` (RFC 9728) and the authorization
  server metadata (RFC 8414), registers itself (RFC 7591), and sends the user
  to `/oauth/authorize` to sign in and approve read access. Codes need PKCE
  (S256); access tokens last an hour, refresh tokens 30 days and rotate on
  every use.
- **Claude Code and scripts**: create a personal token on the account page:
  `claude mcp add --transport http rubyapm https://<host>/mcp --header "Authorization: Bearer rapm_pat_…"`

Only SHA-256 digests of tokens and codes are stored. Requests carrying a
browser `Origin` other than the server's own are refused. Under a path
prefix (`/apm`), the host-root discovery URLs
(`/.well-known/oauth-authorization-server/apm`,
`/.well-known/oauth-protected-resource/apm/mcp`) must also be routed to the
app; `config.ru` maps them. Locally: `http://localhost:4400/mcp`.

## Tests

```bash
(cd server && bin/rails test)         # real agent payloads through ingest, every page rendered
```

## Production: chirpbin.com/apm

The server runs on nuc2 in `~/chirpbin.com/apm`, next to the other chirpbin
apps: a `chirpbin-apm-web` container (host port 3600, on the shared `chirpbin`
Docker network) and its own Postgres container (`apm-db-1`, volume
`apm_pg_data`). The Caddy proxy in `~/chirpbin.com/proxy` sends
`https://chirpbin.com/apm/*` to it (the rest of chirpbin.com is the landing
page); `apm.chirpbin.com` permanently redirects there. The app mounts itself
under `/apm` (`RAILS_RELATIVE_URL_ROOT`).

- Dashboard: RubyAPM's own users (see above); MCP:
  `https://chirpbin.com/apm/mcp`. Caddy routes `/apm/*` and the two
  `/.well-known/…/apm` discovery paths to the container.
- Ingest: `https://chirpbin.com/apm/api/v1/ingest`, authenticated by the API
  key of each app; the first one is created on boot from
  `RUBY_APM_BOOTSTRAP_APP` and `RUBY_APM_BOOTSTRAP_API_KEY`.
- Secrets live only in `~/chirpbin.com/apm/.env` on nuc2 (created once by the
  deploy script with random values).

Deploy: `bin/deploy-chirpbin` copies `server/` to nuc2, builds the
image there and restarts the containers. On boot the server runs
`db:prepare` and `rubyapm:bootstrap`.

## Known limitations

- Outbound HTTP is instrumented through `Net::HTTP` only (which covers
  Faraday's default adapter, HTTParty and most SDKs); curl-based clients such
  as Typhoeus/Ethon, `httpx` and `excon` are not timed yet.
- Async ActiveRecord queries (`load_async`) and work handed to other threads
  run outside the request's transaction and are not attributed to it.
- With Sidekiq running ActiveJob, the job's `perform` segment appears twice
  (nested); layer totals are unaffected.
- Per-trace GC time and allocation counts come from process-wide counters, so
  they are approximate under concurrency.
- EXPLAIN plan analysis is written for PostgreSQL text plans; MySQL and SQLite
  plans are only lightly understood. Plans are never captured with ANALYZE.
- Data older than 24 h is hourly, so zooming into it gives hour bins, and
  deploys older than that are compared in whole hours.
- No per-app permissions: every user sees every app. No email delivery, so
  setup and reset links are passed on by hand. Retention defaults to 8 days.
