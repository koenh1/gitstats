#!/usr/bin/env bash
#
# Creates a deterministic test repository with edge cases for double-counting detection.
#
# Tracks total line count at each commit for verification.
#
# Edge cases covered:
#   - Adding multiple files in one commit
#   - Same-day commits (different times)
#   - Multi-file modifications in one commit
#   - Line additions, removals, and alterations
#   - File rename (git mv)
#   - File deletion (git rm)
#   - Reverting a file to an earlier state
#
# Expected line count at each commit is documented below.
#

set -euo pipefail

REPO_DIR="/Users/koenhendrikx/gitstats-edge-case-repo"

echo "=== Removing old edge-case repo ==="
rm -rf "$REPO_DIR"
mkdir -p "$REPO_DIR"
cd "$REPO_DIR"

echo "=== Initializing git repo ==="
git init
git config user.name "Alice"
git config user.email "alice@example.com"

# Helper: create a file with numbered lines
make_file() {
    local filename="$1"
    local prefix="$2"
    local num_lines="$3"
    rm -f "$filename"
    for i in $(seq 1 "$num_lines"); do
        echo "${prefix} line ${i}" >> "$filename"
    done
}

# Helper: commit with a specific date and author
commit_at() {
    local date_str="$1"
    local message="$2"
    local author_name="${3:-Alice}"
    local author_email="${4:-alice@example.com}"
    GIT_AUTHOR_DATE="$date_str" GIT_COMMITTER_DATE="$date_str" \
    GIT_AUTHOR_NAME="$author_name" GIT_AUTHOR_EMAIL="$author_email" \
    GIT_COMMITTER_NAME="$author_name" GIT_COMMITTER_EMAIL="$author_email" \
        git commit -m "$message"
}

# =========================================================
# Commit 1: Add 5 files, 10 lines each = 50 lines total
# Date: 2023-01-15 10:00
# =========================================================
for i in $(seq 1 5); do
    make_file "file${i}.txt" "f${i}-original" 10
done
git add .
commit_at "2023-01-15T10:00:00+00:00" "C1: Add 5 files (10 lines each)"
# TOTAL: 50 lines

# =========================================================
# Commit 2: Add 5 more files, 10 lines each = +50 = 100 lines total
# Date: 2023-02-15 10:00
# =========================================================
for i in $(seq 6 10); do
    make_file "file${i}.txt" "f${i}-original" 10
done
git add .
commit_at "2023-02-15T10:00:00+00:00" "C2: Add 5 more files (10 lines each)"
# TOTAL: 100 lines

# =========================================================
# Commit 3: Append 5 lines to file1.txt = +5 = 105 lines total
# Date: 2023-03-10 10:00
# =========================================================
for i in $(seq 11 15); do
    echo "f1-added line ${i}" >> file1.txt
done
git add file1.txt
commit_at "2023-03-10T10:00:00+00:00" "C3: Append 5 lines to file1"
# TOTAL: 105 lines

# =========================================================
# Commit 4: Remove 3 lines from file2.txt (lines 4-6) = -3 = 102 lines total
# Date: 2023-03-10 15:00 (SAME DAY as C3!)
# =========================================================
head -n 3 file2.txt > file2.txt.tmp
tail -n 4 file2.txt >> file2.txt.tmp
mv file2.txt.tmp file2.txt
git add file2.txt
commit_at "2023-03-10T15:00:00+00:00" "C4: Remove 3 lines from file2 (same day as C3)"
# TOTAL: 102 lines

# =========================================================
# Commit 5: Alter 3 lines in file3.txt (replace lines 2-4) = +0 = 102 lines total
# Date: 2023-04-20 10:00
# =========================================================
{
    head -n 1 file3.txt
    echo "f3-altered line 2"
    echo "f3-altered line 3"
    echo "f3-altered line 4"
    tail -n 6 file3.txt
} > file3.txt.tmp
mv file3.txt.tmp file3.txt
git add file3.txt
commit_at "2023-04-20T10:00:00+00:00" "C5: Alter 3 lines in file3" "Bob" "bob@example.com"
# TOTAL: 102 lines

# =========================================================
# Commit 6: Multi-file: append 2 lines to file4 AND remove 2 lines from file5
#   +2 - 2 = 0 net change = 102 lines total
# Date: 2023-05-15 10:00
# =========================================================
echo "f4-added line 11" >> file4.txt
echo "f4-added line 12" >> file4.txt
head -n 8 file5.txt > file5.txt.tmp
mv file5.txt.tmp file5.txt
git add file4.txt file5.txt
commit_at "2023-05-15T10:00:00+00:00" "C6: Multi-file: +2 to file4, -2 from file5"
# TOTAL: 102 lines

# =========================================================
# Commit 7: Multi-file same day: alter file6 and file7
# Date: 2023-05-15 18:00 (SAME DAY as C6!)
# =========================================================
{
    echo "f6-altered line 1"
    tail -n 9 file6.txt
} > file6.txt.tmp
mv file6.txt.tmp file6.txt
{
    head -n 5 file7.txt
    echo "f7-altered line 6"
    echo "f7-altered line 7"
    tail -n 3 file7.txt
} > file7.txt.tmp
mv file7.txt.tmp file7.txt
git add file6.txt file7.txt
commit_at "2023-05-15T18:00:00+00:00" "C7: Multi-file same day: alter file6+file7" "Bob" "bob@example.com"
# TOTAL: 102 lines

# =========================================================
# Commit 8: Rename file8.txt -> renamed_file8.txt (no content change)
# Date: 2023-06-20 10:00
# =========================================================
git mv file8.txt renamed_file8.txt
commit_at "2023-06-20T10:00:00+00:00" "C8: Rename file8 to renamed_file8"
# TOTAL: 102 lines

# =========================================================
# Commit 9: Delete file9.txt = -10 = 92 lines total
# Date: 2023-07-15 10:00
# =========================================================
git rm file9.txt
commit_at "2023-07-15T10:00:00+00:00" "C9: Delete file9"
# TOTAL: 92 lines

# =========================================================
# Commit 10: Revert file1.txt back to its state at C1 (remove the 5 appended lines)
#   -5 = 87 lines total
# Date: 2023-08-10 10:00
# =========================================================
make_file "file1.txt" "f1-original" 10
git add file1.txt
commit_at "2023-08-10T10:00:00+00:00" "C10: Revert file1 to original 10 lines"
# TOTAL: 87 lines

# =========================================================
# Commit 11: Append 3 lines to file10 = +3 = 90 lines total
# Date: 2023-08-10 14:00 (SAME DAY as C10!)
# =========================================================
for i in $(seq 11 13); do
    echo "f10-added line ${i}" >> file10.txt
done
git add file10.txt
commit_at "2023-08-10T14:00:00+00:00" "C11: Append 3 lines to file10 (same day as C10)"
# TOTAL: 90 lines

# =========================================================
# Commit 12: Large multi-file: append 5 lines to file1, file2, file3 each
#   +15 = 105 lines total
# Date: 2023-09-15 10:00
# =========================================================
for f in file1.txt file2.txt file3.txt; do
    base=$(basename "$f" .txt)
    for i in $(seq 1 5); do
        echo "${base}-c12-added line ${i}" >> "$f"
    done
done
git add file1.txt file2.txt file3.txt
commit_at "2023-09-15T10:00:00+00:00" "C12: Append 5 lines to file1+file2+file3"
# TOTAL: 105 lines

echo ""
echo "=== Edge-case repo created at: $REPO_DIR ==="
echo "  12 commits, various edge cases"
echo ""
echo "Expected line counts per commit:"
echo "  C1:  50  (5 files × 10 lines)"
echo "  C2:  100 (10 files × 10 lines)"
echo "  C3:  105 (+5 to file1)"
echo "  C4:  102 (-3 from file2, same day as C3)"
echo "  C5:  102 (alter file3, no count change)"
echo "  C6:  102 (+2 file4, -2 file5, net 0)"
echo "  C7:  102 (alter file6+file7, same day as C6)"
echo "  C8:  102 (rename file8, no count change)"
echo "  C9:  92  (-10, delete file9)"
echo "  C10: 87  (-5, revert file1)"
echo "  C11: 90  (+3 to file10, same day as C10)"
echo "  C12: 105 (+15, append to file1+file2+file3)"
echo ""
git log --oneline
