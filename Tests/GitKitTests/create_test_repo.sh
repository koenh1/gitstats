#!/usr/bin/env bash
#
# Creates a deterministic test git repository for analysis verification.
#
# Structure:
#   Phase 1 (commits 1-10): Each commit adds a new 100-line file
#     - Commits 1,3,5,7,9:  file1.txt .. file5.txt
#     - Commits 2,4,6,8,10: file1.md  .. file5.md
#
#   Phase 2 (commits 11-20): Each commit modifies 50 lines in an existing file
#     - Commits 11,13,15,17,19: modify file1.txt .. file5.txt (replace lines 26-75)
#     - Commits 12,14,16,18,20: modify file1.md  .. file5.md  (replace lines 26-75)
#
# Dates are deterministic and span known quarters:
#   Phase 1: 2023-01 through 2023-10 (one month apart)
#   Phase 2: 2023-11 through 2024-08 (one month apart)
#
# After all 20 commits, at HEAD:
#   - 10 files total (5 .txt + 5 .md)
#   - Each file has 100 lines total
#   - Each file has 50 original lines (from Phase 1) and 50 modified lines (from Phase 2)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="/Users/koenhendrikx/gitstats-test-repo"

echo "=== Removing old test repo ==="
rm -rf "$REPO_DIR"
mkdir -p "$REPO_DIR"
cd "$REPO_DIR"

echo "=== Initializing git repo ==="
git init
git config user.name "Test User"
git config user.email "test@example.com"

# Helper: generate a file with numbered lines
generate_file() {
    local filename="$1"
    local prefix="$2"
    local num_lines="$3"
    rm -f "$filename"
    for i in $(seq 1 "$num_lines"); do
        echo "${prefix} line ${i}" >> "$filename"
    done
}

# Helper: modify lines 26-75 (50 lines) in an existing 100-line file
modify_file() {
    local filename="$1"
    local new_prefix="$2"
    local tmpfile="${filename}.tmp"
    # Keep lines 1-25, replace 26-75, keep 76-100
    head -n 25 "$filename" > "$tmpfile"
    for i in $(seq 26 75); do
        echo "${new_prefix} modified line ${i}" >> "$tmpfile"
    done
    tail -n 25 "$filename" >> "$tmpfile"
    mv "$tmpfile" "$filename"
}

# Helper: commit with a specific date
commit_at() {
    local date_str="$1"
    local message="$2"
    GIT_AUTHOR_DATE="$date_str" GIT_COMMITTER_DATE="$date_str" \
        git commit -m "$message"
}

echo "=== Phase 1: Adding files (commits 1-10) ==="

# Commit 1: 2023-01-15 — add file1.txt
generate_file "file1.txt" "original-txt1" 100
git add file1.txt
commit_at "2023-01-15T12:00:00+00:00" "Add file1.txt"

# Commit 2: 2023-02-15 — add file1.md
generate_file "file1.md" "original-md1" 100
git add file1.md
commit_at "2023-02-15T12:00:00+00:00" "Add file1.md"

# Commit 3: 2023-03-15 — add file2.txt
generate_file "file2.txt" "original-txt2" 100
git add file2.txt
commit_at "2023-03-15T12:00:00+00:00" "Add file2.txt"

# Commit 4: 2023-04-15 — add file2.md
generate_file "file2.md" "original-md2" 100
git add file2.md
commit_at "2023-04-15T12:00:00+00:00" "Add file2.md"

# Commit 5: 2023-05-15 — add file3.txt
generate_file "file3.txt" "original-txt3" 100
git add file3.txt
commit_at "2023-05-15T12:00:00+00:00" "Add file3.txt"

# Commit 6: 2023-06-15 — add file3.md
generate_file "file3.md" "original-md3" 100
git add file3.md
commit_at "2023-06-15T12:00:00+00:00" "Add file3.md"

# Commit 7: 2023-07-15 — add file4.txt
generate_file "file4.txt" "original-txt4" 100
git add file4.txt
commit_at "2023-07-15T12:00:00+00:00" "Add file4.txt"

# Commit 8: 2023-08-15 — add file4.md
generate_file "file4.md" "original-md4" 100
git add file4.md
commit_at "2023-08-15T12:00:00+00:00" "Add file4.md"

# Commit 9: 2023-09-15 — add file5.txt
generate_file "file5.txt" "original-txt5" 100
git add file5.txt
commit_at "2023-09-15T12:00:00+00:00" "Add file5.txt"

# Commit 10: 2023-10-15 — add file5.md
generate_file "file5.md" "original-md5" 100
git add file5.md
commit_at "2023-10-15T12:00:00+00:00" "Add file5.md"

echo "=== Phase 2: Modifying files (commits 11-20) ==="

# Commit 11: 2023-11-15 — modify file1.txt
modify_file "file1.txt" "modified-txt1"
git add file1.txt
commit_at "2023-11-15T12:00:00+00:00" "Modify file1.txt"

# Commit 12: 2023-12-15 — modify file1.md
modify_file "file1.md" "modified-md1"
git add file1.md
commit_at "2023-12-15T12:00:00+00:00" "Modify file1.md"

# Commit 13: 2024-01-15 — modify file2.txt
modify_file "file2.txt" "modified-txt2"
git add file2.txt
commit_at "2024-01-15T12:00:00+00:00" "Modify file2.txt"

# Commit 14: 2024-02-15 — modify file2.md
modify_file "file2.md" "modified-md2"
git add file2.md
commit_at "2024-02-15T12:00:00+00:00" "Modify file2.md"

# Commit 15: 2024-03-15 — modify file3.txt
modify_file "file3.txt" "modified-txt3"
git add file3.txt
commit_at "2024-03-15T12:00:00+00:00" "Modify file3.txt"

# Commit 16: 2024-04-15 — modify file3.md
modify_file "file3.md" "modified-md3"
git add file3.md
commit_at "2024-04-15T12:00:00+00:00" "Modify file3.md"

# Commit 17: 2024-05-15 — modify file4.txt
modify_file "file4.txt" "modified-txt4"
git add file4.txt
commit_at "2024-05-15T12:00:00+00:00" "Modify file4.txt"

# Commit 18: 2024-06-15 — modify file4.md
modify_file "file4.md" "modified-md4"
git add file4.md
commit_at "2024-06-15T12:00:00+00:00" "Modify file4.md"

# Commit 19: 2024-07-15 — modify file5.txt
modify_file "file5.txt" "modified-txt5"
git add file5.txt
commit_at "2024-07-15T12:00:00+00:00" "Modify file5.txt"

# Commit 20: 2024-08-15 — modify file5.md
modify_file "file5.md" "modified-md5"
git add file5.md
commit_at "2024-08-15T12:00:00+00:00" "Modify file5.md"

echo ""
echo "=== Test repo created at: $REPO_DIR ==="
echo "  20 commits, 10 files (5 .txt + 5 .md)"
echo "  Each file: 100 lines (50 original + 50 modified)"
echo "  Total: 1000 lines at HEAD"
echo ""
git log --oneline
