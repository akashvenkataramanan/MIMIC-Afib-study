## Diagnostic Queries for AF Episode Detection Debugging

These queries help you understand exactly what's happening in the AF episode detection algorithm for **stay_id 30000831** (the problem patient).

---

## Quick Start

### Option 1: Simple Diagnostic (Recommended First)

**File**: `diagnostic_simple.sql`

**What it shows**: Only the charttimes where there are **conflicting observations** (multiple rhythms at same time)

**How to run**:
1. Open BigQuery Console
2. Copy and paste the entire `diagnostic_simple.sql`
3. Click "Run"

**What to look for**:
- Rows where `observations_at_this_time` > 1
- See which rhythm wins (rank=1, KEPT) vs. which loses (rank>1, DISCARDED)
- **Key finding**: You should see "AF" beating "A Flut" or "1st AV" at the same charttimes

**Example of problem**:
```
charttime: 2140-04-19 08:00:00
  Row 1: "af (atrial fibrillation)" | is_af=TRUE  | rank=1 | ✓ KEPT
  Row 2: "a flut (atrial flutter)"  | is_af=FALSE | rank=2 | ✗ DISCARDED

→ Algorithm thinks AF continues at 08:00, but actually patient was in flutter!
```

---

### Option 2: Full Audit Trail (Deep Dive)

**File**: `diagnostic_audit_query.sql`

**What it shows**: 7 separate views of EVERY step in the pipeline

**How to run**: Copy and run each PART separately (they're separated by headers)

**The 7 Parts**:

#### Part 1: Raw Observations
- All rhythm charting from chartevents
- Before any processing
- Shows: charttime, value, caregiver_id, storetime

#### Part 2: After Labeling
- Shows which observations get `is_af = TRUE` vs `FALSE`
- This is where the regex pattern is applied
- Look for: Unexpected TRUE/FALSE assignments

#### Part 3: Deduplication Analysis
- Shows ALL observations with their dedup rank
- **This is where the problem occurs!**
- Shows what gets KEPT (rn=1) vs DISCARDED (rn>1)

#### Part 4: Conflict Detail View
- ONLY charttimes with multiple observations
- Easier to see the conflicts
- **Most useful for debugging**

#### Part 5: After Segmentation
- Shows how observations are grouped into segments
- Shows segment_id changes
- Look for: Segments that shouldn't be combined

#### Part 6: Segment Summary
- Each segment collapsed (start, end, is_af)
- Shows how many observations in each segment
- Look for: Very long segments that span different rhythms

#### Part 7: Final AF Episodes
- The final output (what gets saved to the table)
- Compare to raw data to see what information was lost

---

## Expected Findings

### Problem 1: Deduplication Bias

**What happens**:
```sql
ORDER BY is_af DESC  -- Always prefers AF (TRUE) over non-AF (FALSE)
```

When multiple rhythms are charted at the same time:
- **Current behavior**: Keeps AF, discards everything else
- **Problem**: Hides rhythm transitions
- **Result**: Creates artificially long AF episodes

**Example**:
```
At 02:00:00, BOTH of these are charted:
  - "AF (Atrial Fibrillation)"    → is_af = TRUE
  - "1st AV (First degree AV Block)" → is_af = FALSE

Dedup keeps: AF
Dedup discards: 1st AV

Algorithm thinks: AF continues
Reality: Patient transitioned to 1st AV block
```

### Problem 2: Regex May Be Too Broad

**Current regex**:
```regex
(atrial.?fibrillation|a[- ]fib|afib)
```

**Potential issues**:
- `a[- ]fib` matches "a fib" in "a flut" → **Check if this is happening**
- Doesn't exclude "flutter" explicitly

**Test**: In Part 2, look for "A Flut" with is_af=TRUE (shouldn't happen, but check)

---

## How to Interpret Results

### Red Flags to Look For:

#### 🚩 Red Flag 1: AF and Non-AF at Same Charttime
```
charttime: 2140-04-18 02:00:00
  AF (Atrial Fibrillation) | KEPT
  1st AV (First degree AV Block) | DISCARDED
```
**Problem**: Dedup is hiding a rhythm change

#### 🚩 Red Flag 2: Long Episode Spanning Different Rhythms
```
Episode 1: 21:48 to 11:00 (13.2 hours)
But in Part 1, you see:
  21:48-01:00: AF
  02:00-06:00: 1st AV  ← Should NOT be in episode!
  07:00-10:00: A Flut  ← Should NOT be in episode!
  11:00+: AF
```
**Problem**: Episode is aggregating non-AF periods

#### 🚩 Red Flag 3: Observations with Same Charttime, Different Storetime
```
charttime: 08:00:00 | storetime: 11:52:00 | AF
charttime: 08:00:00 | storetime: 11:52:00 | A Flut
```
**Problem**: Both stored at same time, but only one kept

---

## Solutions (After You Confirm the Problem)

### Solution 1: Fix Deduplication Logic
Instead of `ORDER BY is_af DESC`, use:
```sql
ORDER BY storetime DESC  -- Most recent documentation wins
```

### Solution 2: Stricter Regex
```sql
CASE
  WHEN REGEXP_CONTAINS(value_lc, r'flutter') THEN FALSE  -- Exclude flutter first
  WHEN REGEXP_CONTAINS(value_lc, r'(atrial.?fibrillation|afib)') THEN TRUE
  WHEN REGEXP_CONTAINS(value_lc, r'a[- ]fib')
    AND NOT REGEXP_CONTAINS(value_lc, r'flutter') THEN TRUE
  ELSE FALSE
END AS is_af
```

### Solution 3: Time-Window Deduplication
Instead of exact charttime, use 1-minute bins:
```sql
PARTITION BY stay_id, TIMESTAMP_TRUNC(charttime, MINUTE)
```

---

## Next Steps

1. **Run `diagnostic_simple.sql`** to see conflicts
2. **Run Part 4 of `diagnostic_audit_query.sql`** for detailed conflict view
3. **Confirm the problem**: Are AF observations beating non-AF at same charttimes?
4. **If yes**: We need to fix the dedup logic
5. **Document the fix**: Update `01_CREATE_AF_EPISODES.md` with corrected algorithm

---

## Questions to Answer

After running these queries, you should be able to answer:

1. ✅ **Are there AF and non-AF observations at the same charttime?**
   - If YES: This explains the problem

2. ✅ **How many conflicts exist?**
   - Count of charttimes with obs_count > 1

3. ✅ **What rhythms are getting discarded?**
   - Look at rank > 1 rows

4. ✅ **Does storetime help?**
   - Check if different observations have different storetimes

5. ✅ **Is the regex wrong?**
   - Look for "A Flut" or "1st AV" with is_af=TRUE in Part 2

---

Good luck debugging! The queries will show you exactly where the algorithm makes the wrong decision.
