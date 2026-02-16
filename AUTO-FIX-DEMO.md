# Auto-Fix Feature Demonstration

The auto-fix feature automatically corrects common formatting issues in AI-generated commit messages.

## What Gets Fixed

**Note:** Auto-fix focuses on formatting issues. Case conversion is handled by the separate `enforce_lowercase()` function.

### 1. Trailing Periods on Summary Line
Conventional commits should not end with periods.

**Before:**
```
feat: add user authentication.
```

**After:**
```
feat: add user authentication
```

### 2. Missing Space After Colon
Ensures proper spacing after the commit type.

**Before:**
```
feat:add authentication
```

**After:**
```
feat: add authentication
```

### 3. Multiple Consecutive Spaces
Removes extra spaces for cleaner formatting.

**Before:**
```
feat:  add   authentication
```

**After:**
```
feat: add authentication
```

### 4. Case Normalization
Handled by `enforce_lowercase()` function which runs before auto-fix.

**Note:** Auto-fix focuses on formatting. Case conversion is handled separately.

### 5. Empty Bullet Points
Removes bullet points that have no content.

**Before:**
```
feat: add authentication

- implement JWT
-
- create login endpoint
```

**After:**
```
feat: add authentication

- implement JWT
- create login endpoint
```

### 6. Inconsistent Bullet Spacing
Normalizes spacing after bullet dashes.

**Before:**
```
feat: add authentication

-    implement JWT
-  create login endpoint
```

**After:**
```
feat: add authentication

- implement JWT
- create login endpoint
```

### 7. Multiple Consecutive Blank Lines
Keeps only one blank line between sections.

**Before:**
```
feat: add authentication


- implement JWT


- create login endpoint
```

**After:**
```
feat: add authentication

- implement JWT

- create login endpoint
```

### 8. Trailing Whitespace
Removes trailing spaces from all lines.

**Before:**
```
feat: add authentication

- implement JWT
- create login endpoint
```

**After:**
```
feat: add authentication

- implement JWT
- create login endpoint
```

## Configuration

### Enable (Default)
```bash
AUTO_FIX=true gh commit-ai
```

### Disable
```bash
AUTO_FIX=false gh commit-ai
```

### Via Config File
```yaml
# .gh-commit-ai.yml
auto_fix: true
```

Or globally:
```yaml
# ~/.gh-commit-ai.yml
auto_fix: false
```

## Integration

Auto-fix runs automatically after:
1. Lowercase enforcement (`enforce_lowercase`)
2. Before template application (`apply_template`)

This ensures the message is properly formatted before being saved or displayed to the user.

## What Doesn't Get Fixed

The auto-fix feature intentionally preserves:
- Acronyms (API, HTTP, JSON) - handled by `enforce_lowercase`
- Ticket numbers (ABC-123) - handled by `enforce_lowercase`
- Code snippets or file paths
- Intentional formatting in breaking change footers
- Line breaks within bullet points

## Examples

### Complex Example

**Before (multiple issues):**
```
feat:  Add User  Authentication.

-    implement JWT token generation
-
-  create login endpoint
- add password  hashing


- configure  middleware
```

**After (all issues fixed):**
```
feat: add user authentication

- implement JWT token generation
- create login endpoint
- add password hashing

- configure middleware
```

### With Scope

**Before:**
```
feat(auth):Add Login.

-    implement JWT
```

**After:**
```
feat(auth): add login

- implement JWT
```

### With Breaking Change

**Before:**
```
feat!:  Redesign API.

-    remove oldLogin function
```

**After:**
```
feat!: redesign API

- remove oldLogin function
```

## Benefits

1. **Consistency**: All commits follow the same formatting rules
2. **Quality**: Fixes issues that AI models sometimes introduce
3. **Automatic**: No manual intervention required
4. **Configurable**: Can be disabled if needed
5. **Safe**: Only fixes formatting, doesn't change content
6. **Fast**: Minimal performance impact

## Testing

To verify auto-fix is working:

1. Make some changes and stage them:
   ```bash
   echo "test" > test.txt
   git add test.txt
   ```

2. Generate a commit message with preview mode:
   ```bash
   ./gh-commit-ai --preview
   ```

3. Check the output for proper formatting:
   - No trailing periods on summary line
   - Proper spacing after colons
   - Clean bullet point formatting
   - No multiple blank lines

## Implementation

The auto-fix feature is implemented in the `auto_fix_message()` function (lines ~4408-4508 in gh-commit-ai) and is integrated into three processing locations:
1. Options mode (multiple message variations)
2. Single message mode (regular commit)
3. Regenerate mode (when user presses 'r')

The function processes the message in two stages:
1. **Summary line processing**: Fixes type-specific issues
2. **Body processing**: Fixes bullet points and blank lines
