# Distance-First Matching for Strava Sync

## Problem

TrainingPeaks CSV imports create workouts at midnight (00:00) because the CSV only contains dates, not times. When Strava sync runs, it creates duplicates because:
1. Time-based matching fails (TP has midnight, Strava has actual time)
2. Category matching fails (sources categorize activities differently - e.g., "MountainBikeRide" vs "Mountain Biking")

## Solution: Distance-First Matching

### Part 1: Matching Logic

For each Strava activity:

1. **Filter candidates**: Same calendar day (category NOT required - sources differ)
2. **Primary match**: Distance within 5% (cross-category) or 10% (same category)
3. **Secondary validation**: Duration within 25%
4. **If multiple candidates match**: Prefer same category, then closest distance
5. **If no distance data**: Fall back to duration-only matching (requires same category)

### Bug Fix: Activity Category Mapping

Expanded Strava activity type mapping to include:
- `mountainbikeride`, `gravelride`, `emountainbikeride` → `.bike`
- `highintensityintervaltraining` → `.strength`

### Part 2: Enrichment Behavior

When a Strava activity matches an existing TrainingPeaks workout:

**Always overwrite from Strava:**
- `stravaActivityId` - Link the records
- `title` - Strava has the actual workout name
- `startDate` / `endDate` - Strava has precise times; TP only has midnight
- `routeData` / `hasRoute` - Strava has GPS polyline

**Preserve from TrainingPeaks (never overwrite):**
- `tss` - TP has the verified training stress score
- `tssType` - Keep the TP verification status
- `source` - Keep original source marker

**Conditionally update (only if TP value is missing/nil):**
- `averageHeartRate`, `maxHeartRate`
- `averagePower`, `maxPower`, `normalizedPower`
- `averageCadence`
- `totalAscent`
- `activeCalories`
- `averagePaceSecondsPerKm`

### Part 3: Edge Cases

**Multiple workouts on same day:**
- Match by closest distance first, then duration as tiebreaker

**Indoor workouts (no distance):**
- Fall back to duration-only matching with tighter threshold (10%)
- Indoor flag must also match

**Already-linked workouts:**
- Skip any workout that already has a `stravaActivityId`

**No match found:**
- Create new workout from Strava
- Mark source as `.strava`

**Strava activity missing data:**
- If no distance AND no duration: skip activity, log warning
- If only distance missing: use duration matching
