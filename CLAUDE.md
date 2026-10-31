# FlowOps — agent guide

Multi-tenant invoice operations app: Rails 7.2 API + React 18/TS + Sidekiq.
Setup: README.md. Architecture: @docs/architecture.md
Session tasks: @docs/candidate-instructions.md

## Working protocol (mandatory)
1. Before editing: locate the code, explain your root-cause hypothesis, and
   propose the fix. Wait for approval
2. Reproduce: run the task's challenge spec and show the failure
3. Fix narrowly: smallest change that addresses the root cause, following
   existing patterns. No opportunistic refactors, no new gems/packages
4. Verify: the task's challenge spec + the full baseline suite
5. Close with: what changed and why it is correct, trade-offs, residual risk,
   and what to monitor in production

## Commands (always through Docker)
- Single spec: `docker compose exec -e RAILS_ENV=test backend bundle exec rspec spec/path_spec.rb:42`
- Backend baseline: `... rspec spec/models spec/requests spec/services spec/jobs`
- Backend challenge: `... rspec spec/challenges`
- Frontend: `docker compose exec frontend npm test` / `npm run test:challenge`
- Typecheck: `docker compose exec frontend npx tsc --noEmit` (no RuboCop/ESLint in
  this repo; do not add them)
- After changing job code: `docker compose restart sidekiq`
- Paths inside `docker compose exec backend` are relative to `backend/`; git paths
  from the repo root need the `backend/` or `frontend/` prefix

## Test helpers (use them in new specs)
- `QueryCounter.capture { ... }` (backend/spec/support/query_counter.rb): counts
  SQL queries, for N+1 assertions
- `ThreadBarrier.new(n)` (backend/spec/support/thread_barrier.rb): releases threads
  together, for race-condition specs
- `renderProbe` (frontend/src/diagnostics/renderProbe.ts): counts InvoiceRow
  renders, for React re-render assertions

## Definition of done
- Baseline stays green
- Challenge passes because the behavior is fixed. NEVER edit, skip, remove,
  or weaken specs in backend/spec/challenges or frontend/src/challenge

## Layers
- Thin controllers; logic lives in `Invoices::Query`, `Dashboard::Summary`,
  `Payments::ApplyWebhook`, `Ai::InvoiceExtractionService`
- Business-rule fixes belong in the service/model, not the controller or React

## Invariants
### Tenancy
- Every model belongs to an Account. Every lookup starts from the
  authenticated account; never `Model.find(id)` without scoping
- Authorization is the API's responsibility; hiding data in React does not count
- `Invoice#number` is unique per account

### Payments (money)
- Always integer cents
- The financial record is the LedgerEntry, not the Invoice status
- A Northstar Pay event applies cash at most once, including repeated AND
  concurrent deliveries. The guarantee must come from the database (unique
  constraint / transaction / lock), not only a Ruby check (race condition)

### Jobs
- `DocumentProcessingJob` (`retry: 5`) may run concurrently for the same
  document. Processing and ExtractionRun must be concurrency-safe (atomic
  claim / lock), with no duplicate extraction or records

### AI extraction
- `mock` provider by default, no network; works with an empty `OPENAI_API_KEY`
- `Ai::RetryableError` (timeout, rate limit, unavailable) → propagate so
  Sidekiq retries
- `Ai::InvalidResponseError`, `Ai::ConfigurationError` → do not retry; record
  a terminal failure
- Invalid/incomplete data is NEVER stored as successful `extracted_data`
- Every attempt produces an ExtractionRun with a consistent outcome
- Reproduce failures with filenames `scenario-timeout|rate-limit|unavailable|invalid`

### Performance
- Performance changes keep API response shapes exactly the same
- Backend: measure first (query log, N+1, indexes); frontend: identify the
  re-render cause before memoizing

## Do not
- Do not replace demo auth (`Bearer demo-account-{id}`)
- Do not modify existing migrations; add new ones
- Do not modify seeds
- Do not change `VITE_API_URL` to the Docker service name

## Directory structure
```
backend/app/
  controllers/api/          base, dashboard, documents, invoices, webhooks/payments
  controllers/concerns/     account_authentication.rb (resolves current account)
  jobs/                     document_processing_job.rb
  models/                   account, customer, invoice, payment_event, ledger_entry,
                            document, extraction_run
  serializers/              invoice_serializer.rb, document_serializer.rb (response shape)
  services/ai/              invoice_extraction_service, provider_registry,
                            mock_provider, openai_compatible_provider (errors in ai.rb)
  services/dashboard/       summary.rb
  services/invoices/        query.rb
  services/payments/        apply_webhook.rb
backend/spec/
  challenges/               one spec per reported issue (do not edit)
  models, requests, services, jobs/   baseline
  factories/core.rb, support/
frontend/src/
  pages/                    DashboardPage, InvoiceDetailPage
  components/               InvoiceTable, InvoiceRow, SummaryCards, StatusBadge, Layout
  hooks/                    useInvoices, useInvoice (TanStack Query)
  services/                 api.ts, invoiceFilters.ts, money.ts
  context/AccountContext.tsx
  challenge/                frontend challenge tests (do not edit)
```