# Secret detection: scan diff before sending to cloud providers
if [ "$AI_PROVIDER" != "ollama" ] && [ "$SKIP_SECRET_SCAN" != "true" ] && [ -n "$GIT_DIFF" ]; then
    if ! detect_secrets_in_diff "$GIT_DIFF"; then
        if ! handle_detected_secrets "$AI_PROVIDER"; then
            exit 0
        fi
    fi
fi

# Define few-shot examples for better AI learning
FEW_SHOT_EXAMPLES="
EXAMPLES OF GOOD COMMIT MESSAGES (BE SPECIFIC LIKE THESE):

Example 1 - Video feature:
Input: Changed video.php, added uploadVideo() function
Output:
feat: add video upload with format validation

- implement uploadVideo() function
- add support for mp4, avi, mov formats
- validate file size and duration

Example 2 - Authentication:
Input: Modified auth/login.php, updated validateUser()
Output:
fix: resolve session timeout in user login

- increase session lifetime to 24 hours
- add automatic token refresh
- fix validateUser() edge case

Example 3 - Payment processing:
Input: Changed payment.php and invoice.php
Output:
fix: correct tax calculation in payment flow

- fix rounding error in calculateTax()
- update invoice generation logic
- add currency conversion handling

BAD EXAMPLES (AVOID THESE - TOO GENERIC):
❌ 'fix: resolve bug'
❌ 'update: change files'
❌ 'feat: add feature'
❌ 'chore: update code'

BAD FORMAT (NEVER DO THIS - PARAGRAPH STYLE):
❌ WRONG:
feat: add new icons to library

- this commit expands the icons library by adding new icons for data saving, data thresholding, light bulb, profile, storage, and videocam. it also exports these new icons and updates the index.ts file to include them, making them accessible for use in the application.

✓ CORRECT:
feat: add new icons to library

- add data saving icon
- add data thresholding icon
- add light bulb icon
- add profile icon
- add storage icon
- add videocam icon
- export new icons in index.ts

REMEMBER:
- Mention the SPECIFIC AREA (video, auth, payment, etc.) and WHAT changed (function names, features)
- Keep each bullet to 12 words MAXIMUM (count the words!)
- Use bullet list format with SHORT lines, NOT paragraphs
- If you have many similar items, list each one separately"

# Prepare branch context
BRANCH_CONTEXT="Branch context:
- Branch name: $BRANCH_NAME"

if [ -n "$TICKET_NUMBER" ]; then
    BRANCH_CONTEXT="$BRANCH_CONTEXT
- Ticket number: $TICKET_NUMBER (include this in your commit message)"
fi

if [ -n "$SUGGESTED_TYPE" ]; then
    BRANCH_CONTEXT="$BRANCH_CONTEXT
- Suggested type: $SUGGESTED_TYPE (based on $TYPE_SOURCE)"
fi

if [ "$IS_BREAKING" = "true" ]; then
    BRANCH_CONTEXT="$BRANCH_CONTEXT
- BREAKING CHANGE DETECTED: $BREAKING_REASON"
fi

# Prepare closing instruction
CLOSING_INSTRUCTION="CRITICAL: Look at the filenames being changed and describe WHAT FEATURE/AREA is affected.
- If video.php is changed, mention 'video' in your summary (e.g., 'fix video upload', 'add video processing')
- If auth/login.php is changed, mention 'authentication' or 'login'
- If UserProfile.tsx is changed, mention 'user profile'
- Make your commit message SPECIFIC to what was actually worked on, not generic.

BULLET POINT QUALITY CHECKLIST:
✓ Can you add WHY this change was made? → 'add JWT auth to enable secure sessions'
✓ Can you add IMPACT/BENEFIT? → 'add caching to reduce DB queries by 60%'
✓ Can you add technical details? → 'increase timeout from 30s to 120s'
✓ Can you show before/after? → 'replace oldLogin() with login() for email support'
✓ Can you mention specific functions? → 'implement uploadVideo() with validation'
✓ Are numbers/metrics relevant? → 'increase max file size to 500MB'

Think: What are all the changes? What's the purpose/impact? Then: Write descriptive bullets with context."
if [ -n "$WP_CONTEXT" ]; then
    CLOSING_INSTRUCTION="$CLOSING_INSTRUCTION

🚨 CRITICAL - WORDPRESS FUNCTIONS DETECTED 🚨
Your summary line MUST describe the WordPress functionality being added/modified.

REQUIRED format for summary line:
- register_post_type('research') → feat: register research custom post type
- register_taxonomy('genre') → feat: add genre taxonomy for [post type]
- add_action('init', ...) → feat: add [what] initialization hook
- wp_enqueue_script('handle') → feat: enqueue [handle] script

DO NOT write:
❌ 'feat: update research post type fields'
❌ 'feat: modify register function'
❌ 'feat: update acf fields and register function'

The summary MUST start with the WordPress action (register/add/enqueue) and the specific thing being registered.
Your FIRST PRIORITY is describing the WordPress function being used."
fi
if [ -n "$TICKET_NUMBER" ]; then
    CLOSING_INSTRUCTION="$CLOSING_INSTRUCTION Include ticket as ($TICKET_NUMBER) after the type, like: feat: ($TICKET_NUMBER) summary text"
fi
if [ "$IS_BREAKING" = "true" ]; then
    CLOSING_INSTRUCTION="$CLOSING_INSTRUCTION This is a BREAKING CHANGE - add ! after type and include BREAKING CHANGE footer."
fi

# Prepare prompt with scope and gitmoji options
# Define gitmoji mappings
GITMOJI_INSTRUCTION=""
if [ "$USE_GITMOJI" = "true" ]; then
    GITMOJI_INSTRUCTION="
GITMOJI PREFIXES:
Add the appropriate emoji prefix before the type:
- ✨ feat: new feature
- 🐛 fix: bug fix
- 📝 docs: documentation
- 💄 style: formatting/styling
- ♻️ refactor: code refactoring
- ✅ test: adding tests
- 🔧 chore: tooling/config/maintenance
- 🚀 perf: performance improvement
- 🔒 security: security fix"
fi

# Build format instruction based on USE_SCOPE and USE_GITMOJI
if [ "$USE_SCOPE" = "true" ] && [ "$USE_GITMOJI" = "true" ]; then
    SCOPE_INSTRUCTION="OUTPUT FORMAT (summary line MUST be first):
<emoji> <type>(<scope>): <concise summary of all changes below>
$GITMOJI_INSTRUCTION

The scope should be a short noun describing what part of the codebase changed:
- auth, api, ui, db, cli, docs, config, tests, deps, etc.
- Choose the most relevant scope based on which files/areas changed
- If changes span multiple areas, pick the primary one

BREAKING CHANGES (RARE - only for incompatible changes):
- ONLY add ! if this breaks existing functionality for users
- Examples: removing APIs, changing CLI flags, changing config format
- Bug fixes, new features, and refactors are NOT breaking changes
- If breaking, add ! after type: <emoji> <type>!(<scope>):
- Add a BREAKING CHANGE footer explaining what breaks"
    SCOPE_EXAMPLES="Examples (note: most commits should NOT have !):
- ✨ feat(auth): add JWT token validation
- ✨ feat(auth): (ABC-123) add JWT token validation
- 🐛 fix(api): resolve timeout in user endpoint
- 🐛 fix(api): (JIRA-456) resolve timeout in user endpoint
- ✨ feat!(api): remove legacy login endpoint

BREAKING CHANGE: Legacy /auth/login endpoint removed, use /auth/v2/login instead"
elif [ "$USE_SCOPE" = "true" ]; then
    SCOPE_INSTRUCTION="OUTPUT FORMAT (summary line MUST be first):
<type>(<scope>): <concise summary of all changes below>

The scope should be a short noun describing what part of the codebase changed:
- auth, api, ui, db, cli, docs, config, tests, deps, etc.
- Choose the most relevant scope based on which files/areas changed
- If changes span multiple areas, pick the primary one

BREAKING CHANGES (RARE - only for incompatible changes):
- ONLY add ! if this breaks existing functionality for users
- Examples: removing APIs, changing CLI flags, changing config format
- Bug fixes, new features, and refactors are NOT breaking changes
- If breaking, add ! after type: <type>!(<scope>):
- Add a BREAKING CHANGE footer explaining what breaks"
    SCOPE_EXAMPLES="Examples (note: most commits should NOT have !):
- feat(auth): add JWT token validation
- feat(auth): (ABC-123) add JWT token validation
- fix(api): resolve timeout in user endpoint
- fix(api): (JIRA-456) resolve timeout in user endpoint
- feat!(api): remove legacy login endpoint

BREAKING CHANGE: Legacy /auth/login endpoint removed, use /auth/v2/login instead"
elif [ "$USE_GITMOJI" = "true" ]; then
    SCOPE_INSTRUCTION="OUTPUT FORMAT (summary line MUST be first):
<emoji> <type>: <concise summary of all changes below>
$GITMOJI_INSTRUCTION

BREAKING CHANGES (RARE - only for incompatible changes):
- ONLY add ! if this breaks existing functionality for users
- Examples: removing APIs, changing CLI flags, changing config format
- Bug fixes, new features, and refactors are NOT breaking changes
- If breaking, add ! after type: <emoji> <type>!:
- Add a BREAKING CHANGE footer explaining what breaks"
    SCOPE_EXAMPLES="Examples (note: most commits should NOT have !):
- ✨ feat: add user authentication
- ✨ feat(auth): (ABC-123) add user login
- 🐛 fix: resolve database connection issue
- 🐛 fix(api): (JIRA-456) fix timeout error
- ✨ feat!: remove legacy login endpoint

BREAKING CHANGE: Legacy /auth/login endpoint removed, use /auth/v2/login instead"
else
    SCOPE_INSTRUCTION="OUTPUT FORMAT (summary line MUST be first):
<type>: <concise summary of all changes below>

BREAKING CHANGES (RARE - only for incompatible changes):
- ONLY add ! if this breaks existing functionality for users
- Examples: removing APIs, changing CLI flags, changing config format
- Bug fixes, new features, and refactors are NOT breaking changes
- If breaking, add ! after type: <type>!:
- Add a BREAKING CHANGE footer explaining what breaks"
    SCOPE_EXAMPLES="Examples (note: most commits should NOT have !):
- feat: add user authentication
- feat: (ABC-123) add user login
- fix: resolve database connection issue
- fix: (JIRA-456) fix timeout error
- feat!: remove legacy login endpoint

BREAKING CHANGE: Legacy /auth/login endpoint removed, use /auth/v2/login instead"
fi

# Prepare multiple options instruction if requested
MULTIPLE_OPTIONS_INSTRUCTION=""
if [ "$MULTIPLE_OPTIONS" = "true" ]; then
    MULTIPLE_OPTIONS_INSTRUCTION="

IMPORTANT: Generate 3 different variations of the commit message with reasoning:

For each variation, follow this exact format:
[OPTION X]
<commit message here>

[REASONING]
<explain why this option is good and when to use it>

1. CONCISE - Minimal details, shorter bullet list
2. DETAILED - More comprehensive, longer bullet list
3. ALTERNATIVE - Different perspective or scope

After all 3 options, provide your recommendation:

[RECOMMENDATION]
I recommend Option X because <reasoning for which is most appropriate for these changes>

Separate each variation with the marker: ---OPTION---"
fi

# Prepare language instruction
LANGUAGE_INSTRUCTION=""
if [ "$COMMIT_LANGUAGE" != "en" ]; then
    LANGUAGE_NAME=$(get_language_name "$COMMIT_LANGUAGE")
    LANGUAGE_INSTRUCTION="

IMPORTANT - LANGUAGE:
- Write ALL commit message text in $LANGUAGE_NAME
- Keep the commit type prefix in English (feat:, fix:, docs:, etc.)
- Write the summary and bullets in $LANGUAGE_NAME
- Maintain technical terms (API, HTTP, function names, etc.) in English
- Example format: feat: [summary in $LANGUAGE_NAME]
  - [bullet 1 in $LANGUAGE_NAME]
  - [bullet 2 in $LANGUAGE_NAME]"
fi

# Use simplified prompt for WordPress plugin updates
if [ -n "$WP_COMPONENT_NAME" ]; then
    # Check if this is a bulk plugin update
    if [ "$WP_COMPONENT_TYPE" = "plugin-bulk" ]; then
        # Very simple prompt for bulk plugin updates
        PROMPT="Create a simple commit message for a WordPress plugin update.

Plugin name: $WP_COMPONENT_NAME

Generate a minimal commit message with NO detailed bullets.

Format:
chore: update $WP_COMPONENT_NAME plugin

RULES:
- Type must be 'chore'
- Summary line: 'update $WP_COMPONENT_NAME plugin' (use the exact plugin name)
- NO bullet points
- NO detailed changes
- Use lowercase for all text
- Output ONLY the commit message, NO explanations, NO markdown, NO code fences$LANGUAGE_INSTRUCTION"
    else
        # Capitalize first letter for display (portable method)
        if [ "$WP_COMPONENT_TYPE" = "plugin" ]; then
            WP_COMPONENT_TYPE_CAP="Plugin"
            WP_COMPONENT_TYPE_PLURAL="plugins"
        else
            WP_COMPONENT_TYPE_CAP="Theme"
            WP_COMPONENT_TYPE_PLURAL="themes"
        fi

        # Check if multiple plugins/themes (comma-separated)
        if [[ "$WP_COMPONENT_NAME" == *,* ]]; then
            # Multiple components - generate simple bullet list
            PROMPT="Create a simple commit message for multiple WordPress $WP_COMPONENT_TYPE_PLURAL.

$WP_COMPONENT_TYPE_CAP names: $WP_COMPONENT_NAME

Generate a simple commit message with one bullet per $WP_COMPONENT_TYPE.

Format:
chore: update wordpress $WP_COMPONENT_TYPE_PLURAL

- update [first-$WP_COMPONENT_TYPE-name] $WP_COMPONENT_TYPE
- update [second-$WP_COMPONENT_TYPE-name] $WP_COMPONENT_TYPE

RULES:
- Type must be 'chore'
- Summary line: 'update wordpress $WP_COMPONENT_TYPE_PLURAL'
- One bullet point per $WP_COMPONENT_TYPE: 'update [name] $WP_COMPONENT_TYPE'
- NO detailed changes or explanations
- Use lowercase for all text
- Use the exact $WP_COMPONENT_TYPE names provided above
- Output ONLY the commit message, NO explanations, NO markdown, NO code fences$LANGUAGE_INSTRUCTION"
        else
            # Single component
            WP_CONTEXT_SECTION=""
            if [ -n "$WP_CONTEXT" ]; then
                WP_CONTEXT_SECTION="
$WP_CONTEXT
"
            fi

            PROMPT="Create a commit message for WordPress $WP_COMPONENT_TYPE changes.

$WP_COMPONENT_TYPE_CAP name: $WP_COMPONENT_NAME
${WP_CONTEXT_SECTION}
Files changed:
$GIT_STATUS

Stats:
$GIT_STATS

Generate a commit message describing what WordPress functionality was added or modified.
If specific WordPress functions are detected above, incorporate them into your message.

Format:
<type>: <specific description>

- <detailed change 1>
- <detailed change 2>

RULES:
- Choose appropriate type based on changes: feat (new functionality), fix (bug fixes), chore (maintenance)
- Summary line should be specific about what was changed (e.g., 'register book custom post type', not just 'update $WP_COMPONENT_NAME')
- Each bullet point: max 12 words per line
- Use bullet list format, NOT paragraphs
- One change per bullet line
- If WordPress functions are detected, mention them specifically
- Use lowercase for all text
- Use imperative mood (add/fix not added/fixed)
- Output ONLY the commit message, NO explanations, NO markdown, NO code fences$LANGUAGE_INSTRUCTION"
        fi
    fi
else
    PROMPT="!!!CRITICAL FORMATTING RULES - READ FIRST!!!

YOU MUST FOLLOW THIS EXACT FORMAT:

<type>: <summary max 50 chars>

- bullet 1 with context (max 18 words)
- bullet 2 with context (max 18 words)
- bullet 3 with context (max 18 words)

BULLET POINT QUALITY GUIDELINES:
✓ Include WHY or IMPACT when relevant: \"implement JWT auth to enable secure session management\"
✓ Add technical details: \"increase timeout from 30s to 120s for large uploads\"
✓ Show before/after for fixes: \"replace oldLogin(username) with login(email, password)\"
✓ Mention specific functions/methods: \"add uploadVideo() with format validation\"
✓ Note performance impacts: \"add Redis caching (reduces DB queries by 60%)\"
✓ Include consequences: \"remove deprecated API endpoint (breaking change for v1 clients)\"

ABSOLUTELY FORBIDDEN - NEVER DO THIS:
❌ NO PARAGRAPHS: \"this commit introduces several new icons to the libs/icons package, including addicon, buildcircleicon, datasaverofficon, datathresholdingicon, lightbulbicon...\"
❌ NO LONG BULLETS: More than 18 words in one line
❌ NO MULTIPLE SENTENCES: One change per bullet only
❌ NO VAGUE BULLETS: \"update config\" → ✓ \"update API timeout from 30s to 120s in config\"

BASIC EXAMPLE (minimal context):
feat: add new icons to library

- add addicon component
- add buildcircleicon component
- add datasaverofficon component
- add datathresholdingicon component
- add lightbulbicon component

BETTER EXAMPLE (with context):
feat: add user authentication system

- implement JWT token generation for secure session management
- create login endpoint with email and password validation
- add bcrypt password hashing to protect user credentials
- set up session middleware for protected routes

BEST EXAMPLE (with technical details):
fix: resolve video upload timeout for large files

- increase upload timeout from 30s to 120s in config
- change max file size from 100MB to 500MB
- replace synchronous upload with chunked streaming for better performance
- add progress tracking callback for user feedback

COUNT YOUR WORDS - EACH BULLET MUST BE 18 WORDS OR LESS!

Now analyze these git changes:

$SCOPE_INSTRUCTION

PROCESS:
1. First, identify all significant changes
2. For each change, determine if you can add WHY/impact/technical details
3. Write descriptive bullets (max 18 words) that include context where helpful
4. Write ONE concise summary line that captures the overall change
5. Choose type: feat, fix, docs, style, refactor, test, or chore

RULES:
- Summary line: max 50 chars
- EACH BULLET: MAXIMUM 18 WORDS - COUNT THEM
- Include context (why/impact/details) when it adds value
- ONE change per bullet line
- NO paragraphs, NO multiple sentences per bullet
- Use lowercase (except API, HTTP, JSON, JWT, SQL, ticket codes like ABC-123)
- Ticket codes stay UPPERCASE: ABC-123 not abc-123
- Use imperative mood: add/fix not added/fixed
- Do NOT use ! unless it breaks existing functionality
- Output ONLY the commit message, NO explanations, NO markdown, NO code fences$LANGUAGE_INSTRUCTION

$SCOPE_EXAMPLES

$FEW_SHOT_EXAMPLES
$REPO_EXAMPLES

$BRANCH_CONTEXT

$HISTORY_INSIGHTS
$WP_CONTEXT
$FILE_CONTEXT
$FUNCTION_CONTEXT
$SEMANTIC_ANALYSIS
$FILE_RELATIONSHIPS

=== KEY FILES MODIFIED ===
Pay special attention to these filenames when writing your commit message.
Your summary line MUST reflect WHAT PART of the application was changed.

$GIT_STATUS

$FILE_SUMMARIES

Stats:
$GIT_STATS

Diff sample:
$GIT_DIFF

$CLOSING_INSTRUCTION$MULTIPLE_OPTIONS_INSTRUCTION"
fi

