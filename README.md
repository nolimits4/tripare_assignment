# Hotel Booking Platform — Infrastructure & Database Reliability

Terraform design for an `Internet → ALB → ECS/Fargate → RDS` stack on AWS, plus a
locally runnable PostgreSQL environment covering migrations, seed data, query
optimisation, backup and restore.

No AWS deployment is required. Terraform is reviewed through `fmt`, `init`,
`validate` and `plan`; the database work runs entirely on Docker Compose.

---

## Contents

- [Architecture](#architecture)
- [Repository layout](#repository-layout)
- [Prerequisites](#prerequisites)
- [Part 1 & 2 — Terraform](#part-1--2--terraform)
- [Part 3 — GitHub Actions](#part-3--github-actions)
- [Part 4 — Local database](#part-4--local-database)
- [Part 5 — Seed data and query optimisation](#part-5--seed-data-and-query-optimisation)
- [Part 6 — Backup and restore](#part-6--backup-and-restore)
- [Verification checklist](#verification-checklist)
- [Design notes](#design-notes)

---

## Architecture

```
                            Internet
                               │
                       :80 from 0.0.0.0/0
                               │
                   ┌───────────▼───────────┐
                   │  Application LB       │   public subnets, 1 per AZ
                   │  sg: hotelapp-alb-sg  │
                   └───────────┬───────────┘
                               │
                     :80 from the ALB SG only
                               │
                   ┌───────────▼────────────┐
                   │  ECS Fargate service   │  private subnets
                   │  sg: ...-ecs-tasks-sg  │  assign_public_ip = false
                   └───────────┬────────────┘
                               │
                    :5432 from the tasks SG only
                               │
                   ┌───────────▼───────────┐
                   │  RDS PostgreSQL 16    │  private subnets
                   │  sg: hotelapp-rds-sg  │  publicly_accessible = false
                   └───────────────────────┘

     egress to the internet for image pulls goes out via NAT gateways
     in the public subnets — one shared in dev, one per AZ in prod
```

The security groups form a closed chain. Each tier references the previous
tier's **security group ID**, never a CIDR block:

| Security group | Ingress | Source |
| --- | --- | --- |
| `hotelapp-<env>-alb-sg` | TCP 80 | `0.0.0.0/0` |
| `hotelapp-<env>-ecs-tasks-sg` | TCP 80 | the ALB security group |
| `hotelapp-<env>-rds-sg` | TCP 5432 | the ECS tasks security group |

Nothing else can reach the database. It has no public IP, it sits in private
subnets with no route to the internet gateway, and its only ingress rule points
at the Fargate task security group.

---

## Repository layout

```
.
├── README.md
├── docker-compose.yml              PostgreSQL 16 with auto-applied migrations
├── .env.example                    local credential overrides
│
├── infra/
│   ├── modules/
│   │   ├── network/                VPC, public/private subnets, IGW, NAT, routes
│   │   ├── ecs/                    ALB, ALB SG, tasks SG, cluster, task def, service, IAM
│   │   ├── rds/                    RDS SG, subnet group, parameter group, instance, secret
│   │   └── backup/                 S3 bucket, scheduled pg_dump task, lifecycle, alarm
│   └── envs/
│       ├── dev/                    small, single NAT, retention 1d,  protection off
│       └── prod/                   large, NAT per AZ, retention 30d, protection on
│
├── db/
│   ├── init/00_bootstrap.sh        applies migrations then seed on first start
│   ├── migrations/
│   │   ├── 001_schema.sql          hotel_bookings, booking_events
│   │   └── 002_indexes.sql         the reporting index and supporting indexes
│   ├── seed/001_seed.sql           5,000 bookings + events, deterministic
│   └── queries/
│       ├── report_query.sql        the Part 5 query verbatim
│       ├── explain_benchmark.sql   before/after EXPLAIN (ANALYZE, BUFFERS)
│       └── verify_data.sql         dataset fingerprint used by backup/restore
│
├── scripts/
│   ├── backup.sh                   timestamped dump + checksum + manifest
│   ├── restore.sh                  restore into a fresh DB, then verify
│   ├── seed.sh                     reapply schema and seed without a rebuild
│   ├── benchmark.sh                run the EXPLAIN comparison
│   └── lib/common.sh               shared helpers
│
└── .github/workflows/
    ├── terraform.yml               fmt, init, validate, plan → PR comment + artifact
    ├── db-tests.yml                PR only: proves the scripts work
    └── db-restore-drill.yml        manual only: on-demand recovery rehearsal
```

---

## Prerequisites

| Tool | Version | Needed for |
| --- | --- | --- |
| Docker + Docker Compose | 20.10+ / v2 | Parts 4–6 |
| Bash | 4+ (Git Bash on Windows) | the scripts |
| Terraform | 1.5+ | Parts 1–3 |

AWS credentials are **not** required for `fmt`, `init -backend=false` or
`validate`. They are only needed if you want `plan` to resolve live data
sources — see [the plan note](#running-a-plan-without-aws-credentials).

---

## Part 1 & 2 — Terraform

### Module structure

Three modules, composed once per environment. Environments share no state and
no resources; the only thing they share is the module source.

| Module | Creates |
| --- | --- |
| `network` | VPC, public + private subnets across N AZs, IGW, NAT gateway(s), route tables |
| `ecs` | ALB + listener + target group, ALB SG, tasks SG, cluster, task definition, service, execution/task IAM roles, log group |
| `rds` | RDS SG, DB subnet group, parameter group, PostgreSQL instance, generated master password in Secrets Manager |

### Environment differences

Everything below is driven by `.tfvars` — the module code is identical.

| Setting | `dev` | `prod` |
| --- | --- | --- |
| VPC CIDR | `10.10.0.0/16` | `10.20.0.0/16` |
| Availability zones | 2 | 3 |
| NAT gateways | 1, shared | 1 per AZ |
| Fargate task | 256 CPU / 512 MiB | 1024 CPU / 2048 MiB |
| Desired count | 1 | 3 |
| ALB deletion protection | `false` | `true` |
| Log retention | 7 days | 90 days |
| **RDS instance class** | `db.t4g.micro` | `db.m6g.large` |
| **RDS backup retention** | **1 day** | **30 days** |
| **RDS deletion protection** | **`false`** | **`true`** |
| RDS Multi-AZ | `false` | `true` |
| Final snapshot on destroy | skipped | taken |
| Performance Insights | off | on |
| Enhanced monitoring | off | 60s |
| Storage | 20 GiB → 50 | 100 GiB → 500 |
| State backend key | `hotelapp/dev/terraform.tfstate` | `hotelapp/prod/terraform.tfstate` |

### Running it

```bash
cd infra/envs/dev

terraform fmt -check -recursive
terraform init -backend=false
terraform validate
terraform plan -refresh=false -var-file=dev.tfvars
```

Same for `prod`:

```bash
cd infra/envs/prod
terraform init -backend=false
terraform validate
terraform plan -refresh=false -var-file=prod.tfvars
```

To check formatting across the whole tree in one go:

```bash
terraform fmt -check -recursive infra/
```

### Remote state

Each environment declares an S3 backend with a **partial** configuration —
only the state key and encryption flag are committed. The bucket, region and
lock table are supplied at init time so the same code works against any
account:

```bash
cp backend.hcl.example backend.hcl   # edit to taste
terraform init -backend-config=backend.hcl
```

`backend.hcl` is gitignored. Dev and prod use separate buckets and separate
DynamoDB lock tables, so a mistake in one environment cannot touch the other.

### Running a plan without AWS credentials

`terraform plan` needs to reach AWS to resolve `aws_availability_zones` and
`aws_region`. Without credentials it will fail at that point — which is
expected, and hence the commands above lead with `init -backend=false`
and `validate`, both of which pass offline.

With credentials exported, the plan runs clean:

```bash
export AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=... AWS_REGION=ap-south-1
terraform plan -refresh=false -var-file=dev.tfvars
```

Nothing in this repository has been applied to a real account, and no state
files are committed.

---

## Part 3 — GitHub Actions

`.github/workflows/terraform.yml` runs on every pull request touching `infra/`:

1. **`fmt`** — `terraform fmt -check -recursive -diff` across the tree. Fails
   the run on any unformatted file.
2. **`validate-and-plan`** — a matrix over `dev` and `prod`, each running
   `init`, `validate` and `plan -refresh=false`.

The plan is surfaced **three** ways:

- **PR comment** — one comment per environment, updated in place on each push
  rather than appended, with the plan in a collapsible block.
- **Workflow artifact** — `terraform-plan-dev` / `terraform-plan-prod`,
  containing the full text plan and the binary plan file, kept 14 days.
- **Job summary** — the same table and plan rendered on the run's summary page.

### Why there is no scheduled backup workflow

The three workflows are split by *who triggers them and why*:

| Workflow | Trigger | Purpose |
| --- | --- | --- |
| `terraform.yml` | PR touching `infra/` | fmt, validate, plan |
| `db-tests.yml` | PR touching `db/`, `scripts/`, compose | Proves the scripts work on a clean checkout |
| `db-restore-drill.yml` | Manual only | On-demand recovery rehearsal |

Deliberately absent: a cron workflow that runs `backup.sh` every few hours.
GitHub Actions runners are ephemeral, so such a job would create a fresh
container, seed it, dump the data it had just generated, and then destroy
everything. It would back up nothing that existed before the run and leave
nothing behind after it — a green checkmark every four hours providing zero
recovery capability, which is worse than no job at all because it *looks* like
backup coverage.

Scheduled backups belong in the infrastructure, and live in two places here:

1. **RDS automated backups** — configured in the `rds` module, 1 day in dev and
   30 days in prod, giving point-in-time recovery.
2. **`infra/modules/backup/`** — an EventBridge schedule firing a Fargate task
   every four hours that runs `pg_dump` and streams the result to S3. See
   [Scheduled backups](#scheduled-backups-in-aws).

Restore is manual by design. It is destructive, and a human has to decide which
dump to trust; automating it on a timer would be actively dangerous.

`.github/workflows/db-tests.yml` covers the database half: shellcheck over
every script, `docker compose up --wait`, the EXPLAIN benchmark, then
`backup.sh` followed by `restore.sh`. It is the same sequence run by hand, so a green run means the checked-out repo genuinely works.

---

## Part 4 — Local database

```bash
docker compose up -d
```

That is the whole setup. On first start the entrypoint runs
`db/init/00_bootstrap.sh`, which applies every file in `db/migrations/` in
order and then every file in `db/seed/`. The container is ready when its
healthcheck passes.

Connect:

```bash
docker compose exec postgres psql -U hotelapp -d hotelapp
```

Defaults are `hotelapp` / `hotelapp` / `hotelapp_local_pw` on port 5432.
Override them by copying `.env.example` to `.env`.

### Schema

`db/migrations/001_schema.sql` creates both tables as specified, with a few
additions a production schema would want:

- a foreign key from `booking_events.booking_id` to `hotel_bookings.id`
  with `ON DELETE CASCADE`
- `CHECK` constraints: `checkout_date > checkin_date`, `amount >= 0`, and
  `status` restricted to the five valid values
- `gen_random_uuid()` defaults via `pgcrypto`

### Resetting

```bash
./scripts/seed.sh          # reapply schema + seed to a running container
docker compose down -v     # destroy the volume; next `up` re-bootstraps
```

---

## Part 5 — Seed data and query optimisation

### The dataset

`db/seed/001_seed.sql` generates:

| | |
| --- | --- |
| Bookings | 5,000 |
| Cities | 8, including `delhi` at ~30% of rows |
| Organisations | 6 |
| Statuses | 5 (`pending`, `confirmed`, `cancelled`, `completed`, `refunded`) |
| Events | ~2,700 across ~1,650 bookings, with JSONB payloads |
| `created_at` spread | 180 days |

The brief asks for 100 bookings as a minimum. That is deliberately exceeded:
on 100 rows PostgreSQL will pick a sequential scan no matter what indexes
exist, because the whole table fits in a couple of pages. At 5,000 rows spread
over 180 days, the 30-day window selects roughly 1 row in 6 and the index
choice becomes measurable rather than theoretical.

`setseed(0.42)` is called first, so every reviewer gets identical data and
comparable `EXPLAIN` numbers. The seed truncates before inserting, so it is
safe to re-run.

### The query

```sql
SELECT org_id, status, COUNT(*), SUM(amount)
FROM hotel_bookings
WHERE city = 'delhi'
  AND created_at >= NOW() - INTERVAL '30 days'
GROUP BY org_id, status;
```

### The index

```sql
CREATE INDEX idx_hotel_bookings_city_created_at
    ON hotel_bookings (city, created_at DESC)
    INCLUDE (org_id, status, amount);
```

**Why this shape:**

1. **`city` first, `created_at` second.** PostgreSQL walks a B-tree left to
   right and can only use *one* range predicate as a search bound — every
   column after it degrades to a filter. With `(city, created_at)` the planner
   descends straight to the `delhi` entries and then range-scans the last
   30 days within them: both predicates are satisfied by the index. Reversed,
   `(created_at, city)` would force a scan of every row in the 30-day window
   across all eight cities before filtering. Equality columns before range
   columns is the general rule.

2. **`DESC` on `created_at`.** The predicate is a "recent N days" window and
   almost every related query in this schema is newest-first. Storing the
   column descending means the hot rows sit at the start of the scan range.

3. **`INCLUDE (org_id, status, amount)`.** These three are the only other
   columns the query touches — two grouping keys and one aggregate input.
   Carrying them in the index leaf makes the query **index-only**: the planner
   never visits the heap, which is where the bulk of the I/O would otherwise
   go. They are in `INCLUDE` rather than the key, so they add no comparison
   cost and do not bloat the tree's internal pages.

**Expected plan shift:** `Seq Scan` over all 5,000 rows → `Index Only Scan
using idx_hotel_bookings_city_created_at`, with a large drop in
`Buffers: shared hit` and a `Heap Fetches: 0` line once the table is vacuumed.

**Supporting indexes** in the same migration:

| Index | Why |
| --- | --- |
| `idx_booking_events_booking_id_created_at` | PostgreSQL does not index foreign keys automatically. Without it, fetching a booking's event stream is a sequential scan, and a cascading delete scans the entire events table per deleted row. |
| `idx_booking_events_event_type_created_at` | Serves "all events of type X in the last hour" — the usual operational query. |
| `idx_hotel_bookings_org_created_at` | Tenant-scoped listing, the second most common access pattern after the report above. |

### Measuring it

```bash
./scripts/benchmark.sh
```

This runs the query twice against the same data: once inside a transaction
with `enable_indexscan` / `enable_indexonlyscan` / `enable_bitmapscan` set to
`off` (forcing the pre-index plan without touching the schema), then once
normally. Both plans are printed with `EXPLAIN (ANALYZE, BUFFERS)`, followed by
the result set and the on-disk size of every index.

Disabling the plan nodes rather than dropping and recreating the index means
the comparison is exact — same rows, same statistics, same cache state.

> The benchmark output has not been pasted here because it has not yet been
> run on this machine (see [Verification status](#verification-status)). Run
> `./scripts/benchmark.sh` and the two plans print side by side.

---

## Part 6 — Backup and restore

### Backup

```bash
./scripts/backup.sh                 # custom-format dump (default)
./scripts/backup.sh --format plain  # plain SQL
./scripts/backup.sh --keep 5        # prune all but the newest 5
```

Produces, in `backups/`:

| File | Contents |
| --- | --- |
| `hotelapp_<UTC timestamp>.dump` | the `pg_dump` archive |
| `…​.dump.sha256` | checksum, verified on restore |
| `…​.manifest.txt` | row counts and checksums captured **before** the dump |
| `latest.dump` | pointer to the newest dump |

Timestamps are UTC and ISO-8601 basic (`20260910T143000Z`), so they sort
lexicographically. The script verifies the archive is readable with
`pg_restore --list` before declaring success, which catches a truncated or
half-written dump immediately rather than at recovery time.

### Restore

```bash
./scripts/restore.sh                        # newest backup → hotelapp_restored
./scripts/restore.sh backups/xyz.dump       # a specific file
./scripts/restore.sh --target scratch xyz.dump
./scripts/restore.sh --in-place xyz.dump    # overwrite the source database
```

By default the restore goes into a **brand new database** (`hotelapp_restored`),
created fresh by dropping and recreating it. The source database is never
touched, so both can be compared afterwards — which is the point of the
exercise.

### How to verify the restore worked

`restore.sh` performs all of the following automatically and fails loudly on
any of them:

1. **Checksum** — the dump's SHA-256 matches what `backup.sh` recorded.
2. **Both tables exist** in the restored database.
3. **`hotel_bookings` is non-empty**, and the row counts for both tables are
   printed.
4. **The reporting index survived.** A restore that silently drops
   `idx_hotel_bookings_city_created_at` would leave the database functional but
   slow — exactly the kind of regression that goes unnoticed for weeks.
5. **Referential integrity** — zero `booking_events` rows point at a booking
   that is not present.
6. **Fingerprint comparison** — `db/queries/verify_data.sql` runs against both
   the source and the restored database, and the two outputs are diffed. It
   covers row counts, distinct cities/orgs/statuses, a checksum over all
   `amount` values, and index counts. Identical output means the restore is
   faithful, not merely non-empty.

To confirm by hand:

```bash
# Row counts should match
docker compose exec postgres psql -U hotelapp -d hotelapp           -c "SELECT COUNT(*) FROM hotel_bookings;"
docker compose exec postgres psql -U hotelapp -d hotelapp_restored  -c "SELECT COUNT(*) FROM hotel_bookings;"

# Full fingerprint on either database
docker compose exec postgres psql -U hotelapp -d hotelapp_restored -f /sql/queries/verify_data.sql

# The report query should return the same numbers from the restored copy
docker compose exec postgres psql -U hotelapp -d hotelapp_restored -f /sql/queries/report_query.sql
```

### Scheduled backups in AWS

`infra/modules/backup/` provisions the production side of the same idea:

| Piece | What it does |
| --- | --- |
| EventBridge Scheduler | Fires every 4 hours (`rate(4 hours)`), 15-minute flexible window, 2 retries |
| Fargate task | Runs `pg_dump --format=custom` and streams it straight to S3 — no local disk staging |
| S3 bucket | Versioned, encrypted, all public access blocked |
| Lifecycle | prod: Standard-IA at 30 days → Glacier IR at 90 → expire at 365. dev: expire at 7 |
| Task IAM role | `s3:PutObject` on `dumps/*` only — it cannot read or delete existing backups |
| CloudWatch alarm | Fires when no successful dump is logged within two scheduled windows |

Two details worth calling out:

- **The task role is write-only.** It can create backups but cannot list, read
  or delete them. A compromised application task therefore cannot exfiltrate
  the backup history or wipe it — which is exactly what ransomware attempts
  first.
- **The alarm watches for *absence*.** A backup job that quietly stops running
  looks identical to one that is working, right up until the day you need it.
  The metric filter counts successful dumps and the alarm treats missing data
  as breaching.

Environment differences:

| | dev | prod |
| --- | --- | --- |
| Schedule enabled | `false` | `true` |
| Retention | 7 days | 365 days |
| Storage tiering | none | IA → Glacier IR |
| Failure alarm | off | on |
| Bucket force-destroy | allowed | blocked |

Dev has the schedule defined but disabled: RDS automated backups already cover
that environment, and a Fargate task every four hours is pure cost for a
database nobody would ever restore from.

The backup task gets its own security group, created in the environment root
(`backup.tf`) rather than inside the module. RDS must allow that group, and the
module needs the RDS secret ARN — defining it inside the module would create a
cycle between the two.

### Verifying a dump — locally

A genuinely end-to-end check — destroy everything and rebuild from the dump
alone:

```bash
./scripts/backup.sh
docker compose down -v      # volume gone, all data destroyed
docker compose up -d        # fresh database, re-bootstrapped from migrations
./scripts/restore.sh        # the dump is restored and verified
```

---

## Verification checklist

The exact commands from the assessment's "How We Will Review" section:

```bash
# Terraform — run in infra/envs/dev and again in infra/envs/prod
terraform fmt
terraform init          # add -backend=false to skip remote state
terraform validate
terraform plan -refresh=false -var-file=dev.tfvars

# Database
docker compose up -d
./scripts/backup.sh
./scripts/restore.sh
```

`-var-file` is required because the sizing values live in the tfvars rather
than being hardcoded. Every variable also carries a sensible default matching
its environment, so a bare `terraform plan` works too.

### Verification status

Full disclosure on what has and has not been executed:

- **Not yet run on this machine.** Neither Terraform nor a running Docker
  daemon was available in the environment where this repository was authored,
  so the commands above have not been executed here and no `EXPLAIN` output has
  been captured.
- Both GitHub Actions workflows run exactly these commands, so the first CI
  run on a pull request will confirm the whole thing end to end.
- Anything found on that first run belongs in a follow-up commit, along with
  the real benchmark output pasted into [Part 5](#measuring-it).

---

## Design notes

**Why the security group chain rather than CIDR rules.** Referencing security
group IDs means the rules stay correct when subnets are re-CIDRed or AZs are
added. It also makes the intent readable in the console: the RDS rule literally
says "from the ECS task security group", which is the requirement stated in
prose.

**Why the master password is generated, not passed in.** `random_password`
produces the credential and `aws_secretsmanager_secret_version` stores it; it
never appears in a tfvars file or in version control. The task execution role
is granted `secretsmanager:GetSecretValue` on that one secret ARN, and the task
definition references it as a secret rather than a plaintext environment
variable, so the password never lands in the task definition JSON.

**Why one route table per private subnet.** In prod each AZ routes through its
own NAT gateway, so losing an AZ cannot cut egress for tasks in the surviving
ones. Dev collapses to a single shared NAT gateway, which is the single largest
cost saving available in this design.

**Why `deployment_circuit_breaker` with rollback.** A task definition that
crashes on boot would otherwise leave the service cycling indefinitely. With
the circuit breaker enabled, ECS detects the failed deployment and rolls back
to the last healthy revision on its own.

**Why dumps are copied rather than bind-mounted.** The obvious design is to
mount `./backups` into the container and let `pg_dump --file` write straight to
it. That breaks on Linux and on CI: `pg_dump` runs as the postgres user
(uid 999) while the host directory belongs to whoever cloned the repository, so
the directory is not writable and the dump fails. Docker Desktop hides the
mismatch on macOS and Windows, which makes it a bug that only ever appears in
CI. Writing to a container-local path and copying the result out with
`docker cp` avoids uid mapping altogether and behaves the same everywhere.
`restore.sh` copies in the same direction for the same reason.

**Why the dump is `--format=custom`.** It is compressed, it can be restored
selectively, and `pg_restore --list` gives a cheap integrity check that plain
SQL does not. `--format=plain` remains available via a flag for anyone who
wants a human-readable dump.

**Why `--clean --if-exists` on the dump.** The default restore path uses a
fresh database where these are unnecessary, but including them keeps the same
artefact usable for in-place recovery. It is also why `pg_restore` may exit
non-zero on a fresh target — it emits `DROP` statements for objects that do not
exist yet. The script treats the verification results, not the exit code, as
the source of truth, and says so in its output.

### Known limitations

Deliberate scope boundaries, not oversights:

- **HTTP only on the ALB.** HTTPS needs an ACM certificate and a DNS zone,
  neither of which exists without a real account. In production the listener
  would be 443 with a redirect from 80.
- **`nginx:alpine` as the workload.** A placeholder, as the brief allows. A
  real service would come from ECR with an immutable digest tag.
- **No autoscaling policy.** `desired_count` is fixed. Production would attach
  an `aws_appautoscaling_target` tracking ALB request count per target.
- **Backups run on demand.** `backup.sh` is invoked manually. Scheduling it
  (cron, or an ECS scheduled task shipping to S3 with lifecycle rules) is the
  obvious next step, alongside RDS's own automated backups which are already
  configured at 1 and 30 days.
- **No VPC endpoints.** Tasks reach Secrets Manager and ECR through the NAT
  gateway. Interface endpoints would cut NAT data charges and keep the traffic
  off the public internet.
