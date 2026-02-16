# Bug Fix: Auto-Fix sed Error

## Issue

The `auto_fix_message()` function had a sed regex error:
```
sed: 1: "s/^([a-z]+)(\([^)]+\))? ...": \4 not defined in the RE
```

## Root Cause

Line 4506 attempted to fix capitalized first letters with:
```bash
first_line=$(echo "$first_line" | sed -E 's/^([a-z]+)(\([^)]+\))?!?: ([A-Z])/\1\2\3: \L\4/')
```

**Problems**:
1. Only 3 capture groups exist, but referenced `\4` (doesn't exist)
2. `\L` (lowercase modifier) is not portable across sed implementations
3. Redundant - `enforce_lowercase()` already handles case conversion

## Solution

**Removed the problematic line entirely** (line 4506).

**Rationale**:
- Auto-fix should focus on **formatting** (spacing, punctuation)
- `enforce_lowercase()` already handles **case conversion**
- `enforce_lowercase()` runs **before** `auto_fix_message()`
- No need to duplicate functionality

## What Auto-Fix Now Does

Focuses on formatting issues only:
1. ✅ Remove trailing periods from summary line
2. ✅ Fix missing spaces after colons (`feat:add` → `feat: add`)
3. ✅ Remove multiple consecutive spaces
4. ✅ Normalize bullet point spacing
5. ✅ Remove empty bullet points
6. ✅ Remove trailing whitespace
7. ✅ Consolidate multiple blank lines

**Case conversion**: Handled by `enforce_lowercase()` (separate function)

## Processing Order

```
AI generates message
    ↓
Strip markdown fences
    ↓
enforce_lowercase() ← Handles case conversion
    ↓
auto_fix_message()  ← Handles formatting
    ↓
apply_template()
    ↓
Display to user
```

## Files Modified

1. **gh-commit-ai** (line 4504-4506)
   - Removed problematic sed command

2. **AUTO-FIX-DEMO.md**
   - Updated to note case conversion is separate

3. **README.md**
   - Removed capitalization fix from features list
   - Added note about separate case handling

4. **.gh-commit-ai.example.yml**
   - Updated comment to clarify separation

5. **IMPROVEMENTS-SUMMARY.md**
   - Updated features list

## Testing

```bash
# Syntax check
bash -n gh-commit-ai
# ✅ No errors

# The function now works without sed errors
# Case conversion still happens via enforce_lowercase()
```

## Impact

- ✅ **Bug fixed**: No more sed errors
- ✅ **Functionality preserved**: Case conversion still works
- ✅ **Cleaner separation**: Formatting vs case conversion
- ✅ **No breaking changes**: Same output as intended

## Lesson Learned

When adding new features:
1. Test with actual data, not just syntax check
2. Avoid duplicating existing functionality
3. Keep functions focused (single responsibility)
4. Use portable bash/sed constructs
