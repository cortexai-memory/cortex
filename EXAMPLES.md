# Cortex Use Cases & Examples

Real-world scenarios showing how Cortex saves time and prevents mistakes.

## Table of Contents

- [Layer 0: Session Continuity](#layer-0-session-continuity)
- [Phase 2: Semantic Search](#phase-2-semantic-search)
- [Phase 3: Knowledge Management](#phase-3-knowledge-management)
- [Phase 4: Impact Analysis](#phase-4-impact-analysis)
- [Team Workflows](#team-workflows)

---

## Layer 0: Session Continuity

### Use Case 1: End-of-Day Context Handoff

**Problem:** You finish at 5pm mid-feature. Next morning, you waste 10 minutes remembering where you left off.

**Solution:**

```bash
# Friday 5pm
git commit -m "feat: add login form (WIP)"
# Go home

# Monday 9am
cx  # Claude sees your Friday commit
```

**Claude's view:**
```markdown
## SINCE LAST SESSION
a1b2c3d feat: add login form (WIP)

## RECENT COMMITS (24h)
- a1b2c3d feat: add login form (WIP) [+87/-2]
  Files: src/auth/LoginForm.tsx, src/auth/types.ts

## GIT STATUS
Branch: feature/auth | Uncommitted: 0 files
Last: a1b2c3d feat: add login form (WIP) (16 hours ago)
```

**Result:** Claude knows you're working on the login form, no re-explaining needed.

**Time saved:** 10 minutes per day = **50 minutes per week**

---

### Use Case 2: Context Switch Recovery

**Problem:** You switch between 3 projects daily. Each switch requires 5 minutes of context rebuild.

**Solution:**

```bash
# Project A
cd ~/project-a
cx
# Claude knows: "We're refactoring the payment system"

# Project B
cd ~/project-b
cx
# Claude knows: "We're fixing the OAuth bug in production"

# Back to Project A
cd ~/project-a
cx
# Claude remembers: "Back to payment refactoring"
```

**Result:** Zero cognitive overhead on project switches.

**Time saved:** 15 minutes per day = **1.25 hours per week**

---

## Phase 2: Semantic Search

### Use Case 3: Find Related Work by Meaning

**Problem:** You remember fixing an auth bug 2 months ago, but can't remember the commit.

**Without Cortex:**
```bash
git log --grep="auth" --oneline  # 47 results, mostly irrelevant
git log --grep="bug" --oneline   # 203 results
# Give up after 10 minutes
```

**With Cortex:**
```
You: Find commits about authentication bugs

Claude: [Calls cortex_search(query="authentication bugs")]

Results:
- fix: prevent null pointer in OAuth callback [95% match]
- fix: handle expired tokens in auth middleware [89% match]
- fix: race condition in session validation [82% match]
```

**Result:** Found the right commit in **10 seconds** vs. 10+ minutes.

**Time saved:** 10+ minutes per search

---

### Use Case 4: Natural Language Commit Discovery

**Problem:** Product asks "Did we ever try implementing real-time notifications?"

**Without Cortex:**
```bash
git log --all --grep="notification" --grep="realtime" --grep="websocket"
# Still not sure if we tried it
```

**With Cortex:**
```
You: Did we implement real-time notifications?

Claude: [Calls cortex_search(query="real-time notifications websocket")]

Results:
- feat: add WebSocket server for notifications [93% match]
- refactor: remove real-time notification experiment [91% match]
- docs: why we chose polling over WebSocket [88% match]
```

**Result:** Clear answer with context in **15 seconds**.

---

## Phase 3: Knowledge Management

### Use Case 5: Architectural Decision Records

**Problem:** New developer asks "Why did we choose MongoDB over PostgreSQL?" Nobody remembers.

**Solution:**

```
You: Store a decision about our database choice

Claude: [Calls cortex_remember]
cortex_remember(
  category="decision",
  title="Use MongoDB for product catalog",
  content="Chose MongoDB because:
  - Schema flexibility for varied product types
  - Built-in full-text search
  - Horizontal scaling via sharding",
  context="Evaluated PostgreSQL with JSONB but lacked sharding support at scale",
  alternatives="PostgreSQL with JSONB, Cassandra, DynamoDB",
  tags="database,architecture,mongodb"
)
```

**6 months later:**

```
New Developer: Why are we using MongoDB?

Claude: [Calls cortex_recall(query="mongodb database choice")]

Found: "Use MongoDB for product catalog"
- Schema flexibility for varied product types
- Built-in full-text search
- Horizontal scaling via sharding

Alternatives considered: PostgreSQL with JSONB, Cassandra, DynamoDB
```

**Result:** Institutional knowledge preserved forever.

**Time saved:** Hours of investigation + prevents wrong decisions

---

### Use Case 6: Bug Fix Learning

**Problem:** You fix a tricky bug but forget the lesson. Same bug reappears 6 months later.

**Solution:**

```
You: Remember this bug fix lesson

Claude: [Calls cortex_remember]
cortex_remember(
  category="bug_fix",
  title="Race condition in payment processing",
  content="Payment webhooks arrived before DB transaction completed",
  root_cause="Async webhook handler didn't wait for transaction commit",
  prevention="Always use database-level locks for payment state changes",
  severity="critical",
  tags="payments,race-condition,webhooks"
)
```

**6 months later:**

```
You: Recall payment bugs

Claude: [Calls cortex_recall(query="payment bugs")]

Found: "Race condition in payment processing"
Root cause: Async webhook handler didn't wait for transaction commit
Prevention: Always use database-level locks for payment state changes
```

**Result:** Same bug never happens again.

**Impact:** Prevents critical production bugs

---

## Phase 4: Impact Analysis

### Use Case 7: Safe Refactoring

**Problem:** You want to refactor `auth/middleware.ts` but don't know what depends on it.

**Without Cortex:**
```bash
git grep "auth/middleware"  # 127 results across 40 files
# Manually check each file
# Takes 30+ minutes
# Still not sure if you found everything
```

**With Cortex:**
```
You: What breaks if I change auth/middleware.ts?

Claude: [Calls cortex_impact(filepath="auth/middleware.ts")]

## Impact Analysis: auth/middleware.ts

Impact Level: HIGH (score: 87)

Direct Dependents: 12 files
- src/api/server.ts
- src/routes/protected.ts
- src/routes/admin.ts
[... 9 more]

Transitive Impact: 34 files
- Tests that import protected routes
- API endpoints using auth
[... 32 more]

Recommendation:
⚠️ HIGH IMPACT - Consider:
- Review all 46 dependent files
- Add comprehensive integration tests
- Use feature flag for gradual rollout
```

**Result:** Full dependency tree in **5 seconds** vs. 30+ minutes.

**Impact:** Prevents breaking changes in production

---

### Use Case 8: Code Hotspot Detection

**Problem:** You inherit a codebase. Don't know where to focus refactoring efforts.

**Solution:**

```
You: Find the most frequently changed files

Claude: [Calls cortex_patterns(pattern_type="hotspots")]

## Codebase Patterns

### Hotspots (Most Changed Files)
- `src/legacy/UserService.ts` — 147 changes [CRITICAL]
- `config/database.ts` — 89 changes [HIGH]
- `src/api/routes.ts` — 67 changes [HIGH]
- `src/models/User.ts` — 54 changes [MEDIUM]

Recommendation: Focus refactoring on UserService.ts (147 changes suggests
it's doing too many things)
```

**Result:** Data-driven refactoring priorities.

**Time saved:** Days of code archaeology

---

### Use Case 9: Finding Related Files

**Problem:** You're working on the login flow. What other files do you need to check?

**Solution:**

```
You: What files are related to auth/login.ts?

Claude: [Calls cortex_related(filepath="auth/login.ts")]

## Related Files: auth/login.ts

### Import Relationships
- `auth/validators.ts` (strength: 23)
- `auth/session.ts` (strength: 18)
- `models/User.ts` (strength: 12)

### Frequently Co-Changed
- `auth/login.test.ts` (15 times)
- `auth/types.ts` (12 times)
- `components/LoginForm.tsx` (8 times)

Insight: These files change together 67% of the time
```

**Result:** Know exactly which files to review.

**Time saved:** 20+ minutes of exploration

---

## Team Workflows

### Use Case 10: Onboarding New Developers

**Problem:** New developer needs to understand the codebase quickly.

**Solution:**

```
New Dev: Show me the architectural decisions

Claude: [Calls cortex_decisions()]

## Architectural & Technical Decisions

1. Use MongoDB for product catalog
   - Schema flexibility, full-text search, horizontal scaling
   - Alternatives: PostgreSQL, Cassandra

2. Choose Next.js over Create React App
   - SSR for SEO, API routes, file-based routing
   - Migration completed Q2 2025

3. Adopt trunk-based development
   - Short-lived feature branches (<2 days)
   - CI must pass before merge
```

**Result:** Comprehensive architecture understanding in minutes.

**Time saved:** 2-3 days of onboarding

---

### Use Case 11: Code Review Context

**Problem:** Reviewing a PR but don't know why certain decisions were made.

**Solution:**

```
Reviewer: Why is this using MongoDB instead of PostgreSQL?

Claude: [Calls cortex_recall(query="mongodb postgresql database")]

Found decision from 6 months ago:
"Use MongoDB for product catalog"
- Reason: Schema flexibility for varied product types
- Alternatives considered: PostgreSQL with JSONB
- Trade-off: Gave up ACID for flexibility
```

**Result:** Informed code review with historical context.

**Impact:** Better review quality, fewer debates

---

## Workflow Comparisons

### Before Cortex

| Task | Time | Frustration |
|------|------|-------------|
| Remember yesterday's work | 10 min | 😤 High |
| Find old commit | 10+ min | 😡 Very High |
| Know what depends on file | 30+ min | 😱 Extreme |
| Understand past decisions | Unknown | 🤷 Impossible |

**Total wasted time per week:** ~5 hours

### After Cortex

| Task | Time | Frustration |
|------|------|-------------|
| Remember yesterday's work | 0 sec | 😊 None |
| Find old commit | 10 sec | 😊 None |
| Know what depends on file | 5 sec | 😊 None |
| Understand past decisions | 5 sec | 😊 None |

**Total wasted time per week:** ~5 minutes

**Time saved:** ~5 hours per week = **260 hours per year** = **6.5 weeks**

---

## Quick Command Reference

### Layer 0 (No Setup)
```bash
cx                    # Start AI session with memory
cortex-status.sh      # Check memory stats
```

### Phase 2 (Semantic Search)
```
cortex_index()        # Index commits
cortex_search(query="auth bugs", file_type="ts")
cortex_diff(commit1="abc123", commit2="HEAD")
```

### Phase 3 (Knowledge Base)
```
cortex_remember(category="decision", title="...", content="...")
cortex_recall(query="database choice")
cortex_decisions()    # List all decisions
```

### Phase 4 (Code Intelligence)
```
cortex_impact(filepath="src/auth.ts")
cortex_related(filepath="src/auth.ts")
cortex_patterns()     # Detect hotspots
```

---

## ROI Calculator

**Assumptions:**
- 2 hours saved per week per developer
- $75/hour developer rate
- Team of 5 developers

**Annual savings:**
- Time: 520 hours (13 weeks)
- Cost: $39,000
- Prevented bugs: Priceless

**Setup time:** 5 minutes
**Payback period:** Immediate
