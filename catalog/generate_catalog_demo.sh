#!/bin/bash
# =============================================================================
# WEKA Catalog Demo File Generator
# Creates a realistic deep directory structure with common file types for demos
# 50 base folders | nested subfolders | 10 file types | random counts & sizes
# =============================================================================

set -e

# Must run as root to create users/groups and chown files
if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: This script must be run as root (sudo) to create users, groups, and set ownership."
  echo "Usage: sudo $0"
  exit 1
fi

# =============================================================================
# Prompt for target directory and validate it is on a mounted WEKA filesystem
# =============================================================================

echo "============================================"
echo "  WEKA Catalog Demo File Generator"
echo "============================================"
echo ""

# Prompt for target directory
read -rp "Enter the target directory for demo files (must be on a mounted WEKA filesystem): " BASE_DIR

if [ -z "$BASE_DIR" ]; then
  echo "ERROR: No directory specified. Exiting."
  exit 1
fi

# Resolve to absolute path and strip trailing slash
BASE_DIR="$(realpath -m "$BASE_DIR" 2>/dev/null || echo "$BASE_DIR")"
BASE_DIR="${BASE_DIR%/}"

# Verify the path sits on a mounted wekafs filesystem
# Walk up from BASE_DIR until we find a matching mount point
check_wekafs_mount() {
  local check_path="$1"

  # Collect all wekafs mount points
  local mounts
  mounts=$(mount -t wekafs 2>/dev/null | awk '{print $3}')

  if [ -z "$mounts" ]; then
    return 1
  fi

  # Walk up the path hierarchy and look for a match
  local current="$check_path"
  while true; do
    while IFS= read -r mp; do
      if [ "$current" = "$mp" ]; then
        return 0
      fi
    done <<< "$mounts"
    # Stop if we've reached the filesystem root
    [ "$current" = "/" ] && break
    current="$(dirname "$current")"
  done
  return 1
}

echo ""
echo "Checking that '$BASE_DIR' is on a mounted WEKA filesystem..."

if ! check_wekafs_mount "$BASE_DIR"; then
  echo ""
  echo "ERROR: '$BASE_DIR' does not appear to be on a mounted WEKA filesystem."
  echo ""
  echo "Currently mounted WEKA filesystems:"
  if mount -t wekafs 2>/dev/null | grep -q .; then
    mount -t wekafs | awk '{printf "  %s → %s\n", $1, $3}'
  else
    echo "  (none found)"
  fi
  echo ""
  echo "Mount a WEKA filesystem first, e.g.:"
  echo "  mount -t wekafs <cluster>/<fs> /mnt/weka"
  exit 1
fi

echo "  OK — WEKA filesystem confirmed."
echo ""

# =============================================================================
# Configuration
# =============================================================================

# 10 common file extensions
EXTENSIONS=("txt" "pdf" "xls" "doc" "jpg" "png" "csv" "json" "xml" "log")

# Realistic folder names
FOLDERS=(
  "finance/reports" "finance/invoices" "finance/budgets" "finance/audits" "finance/tax"
  "engineering/designs" "engineering/specs" "engineering/cad" "engineering/test_results" "engineering/firmware"
  "marketing/campaigns" "marketing/assets" "marketing/analytics" "marketing/brand" "marketing/events"
  "hr/policies" "hr/recruitment" "hr/onboarding" "hr/payroll" "hr/training"
  "legal/contracts" "legal/compliance" "legal/patents" "legal/nda" "legal/litigation"
  "sales/proposals" "sales/quotes" "sales/forecasts" "sales/presentations" "sales/crm_exports"
  "operations/logistics" "operations/inventory" "operations/vendors" "operations/sops" "operations/quality"
  "research/papers" "research/datasets" "research/experiments" "research/models" "research/references"
  "it/configs" "it/backups" "it/logs" "it/scripts" "it/network"
  "executive/board_decks" "executive/strategy" "executive/memos" "executive/kpis" "executive/reviews"
)

# Realistic filename prefixes per extension
declare -A PREFIXES
PREFIXES[txt]="readme notes meeting_minutes changelog todo draft_memo release_notes config setup instructions"
PREFIXES[pdf]="report whitepaper datasheet manual invoice contract policy certificate brochure proposal"
PREFIXES[xls]="budget forecast headcount pipeline tracker metrics inventory pricing schedule analysis"
PREFIXES[doc]="proposal template runbook playbook charter brief requirements design review sow"
PREFIXES[jpg]="photo screenshot diagram hero_image banner product_shot event_pic headshot office site"
PREFIXES[png]="logo icon chart graph mockup wireframe ui_capture architecture dashboard infographic"
PREFIXES[csv]="export dump users transactions products orders metrics events logs accounts"
PREFIXES[json]="config payload schema response manifest metadata settings mapping template fixture"
PREFIXES[xml]="feed sitemap data record manifest transform schema message report config"
PREFIXES[log]="access error application debug system audit security build deploy cron"

# Generate a random size between 20KB and 2MB, weighted toward ~100KB
random_size() {
  local bucket=$((RANDOM % 100))
  if   [ $bucket -lt 30 ]; then echo $(( (RANDOM % 80)  + 20   ))   # 20-100 KB  (30%)
  elif [ $bucket -lt 70 ]; then echo $(( (RANDOM % 200) + 50   ))   # 50-250 KB  (40%)
  elif [ $bucket -lt 90 ]; then echo $(( (RANDOM % 500) + 200  ))   # 200-700 KB (20%)
  else                          echo $(( (RANDOM % 1300) + 700  ))   # 700-2000KB (10%)
  fi
}

echo "Base directory : $BASE_DIR"
echo "Folders        : ${#FOLDERS[@]}"
echo "File types     : ${EXTENSIONS[*]}"
echo "Files per type : 40–2000 (random)"
echo ""

# =============================================================================
# Phase 0: Create department users and groups
# =============================================================================

DEPARTMENTS=("finance" "engineering" "marketing" "hr" "legal" "sales" "operations" "research" "it" "executive")

echo "Setting up department users and groups..."
for dept in "${DEPARTMENTS[@]}"; do
  grp="dept_${dept}"
  usr="usr_${dept}"

  if getent group "$grp" >/dev/null 2>&1; then
    echo "  Group '$grp' already exists (gid=$(getent group "$grp" | cut -d: -f3))"
  else
    groupadd "$grp"
    echo "  Created group '$grp' (gid=$(getent group "$grp" | cut -d: -f3))"
  fi

  if id "$usr" >/dev/null 2>&1; then
    echo "  User  '$usr' already exists (uid=$(id -u "$usr"))"
  else
    useradd -r -s /usr/sbin/nologin -g "$grp" -M "$usr" 2>/dev/null || \
    useradd -r -s /bin/false -g "$grp" -M "$usr"
    echo "  Created user  '$usr' (uid=$(id -u "$usr"), group=$grp)"
  fi
done
echo ""

# =============================================================================
# Phase 1: Create folder structure and flat files
# =============================================================================

echo "Creating ${#FOLDERS[@]} folders..."
for folder in "${FOLDERS[@]}"; do
  mkdir -p "$BASE_DIR/$folder"
done
echo "  Done."
echo ""

total_bytes=0
file_count=0

for ext in "${EXTENSIONS[@]}"; do
  count=$(( (RANDOM % 1961) + 40 ))
  echo -n "Creating $count .${ext} files..."

  IFS=' ' read -ra names <<< "${PREFIXES[$ext]}"
  num_names=${#names[@]}

  for i in $(seq 1 $count); do
    folder="${FOLDERS[$((RANDOM % ${#FOLDERS[@]}))]}"
    prefix="${names[$((RANDOM % num_names))]}"
    filename="${prefix}_$(printf '%04d' $i)_$(date -d "-$((RANDOM % 365)) days" +%Y%m%d 2>/dev/null || date +%Y%m%d).${ext}"
    size_kb=$(random_size)
    total_bytes=$((total_bytes + size_kb * 1024))
    dd if=/dev/urandom of="$BASE_DIR/$folder/$filename" bs=1024 count=$size_kb 2>/dev/null
    file_count=$((file_count + 1))
  done
  echo " done"
done

# =============================================================================
# Phase 2: Nested subfolders
# =============================================================================

SUBNAMES=("2024" "2025" "2026" "archive" "draft" "final" "v1" "v2" "v3"
           "Q1" "Q2" "Q3" "Q4" "jan" "feb" "mar" "apr" "may" "jun"
           "internal" "external" "approved" "pending" "reviewed" "backup"
           "client_a" "client_b" "project_alpha" "project_beta" "misc")

declare -A DEPT_SUBS
DEPT_SUBS[finance]="reports invoices budgets audits tax"
DEPT_SUBS[engineering]="designs specs cad test_results firmware"
DEPT_SUBS[marketing]="campaigns assets analytics brand events"
DEPT_SUBS[hr]="policies recruitment onboarding payroll training"
DEPT_SUBS[legal]="contracts compliance patents nda litigation"
DEPT_SUBS[sales]="proposals quotes forecasts presentations crm_exports"
DEPT_SUBS[operations]="logistics inventory vendors sops quality"
DEPT_SUBS[research]="papers datasets experiments models references"
DEPT_SUBS[it]="configs backups logs scripts network"
DEPT_SUBS[executive]="board_decks strategy memos kpis reviews"

echo ""
echo "Creating nested subfolders with files..."
nested_folder_count=0

for dept in "${DEPARTMENTS[@]}"; do
  IFS=' ' read -ra subs <<< "${DEPT_SUBS[$dept]}"
  num_subs=${#subs[@]}

  pick_count=$(( (RANDOM % 2) + 2 ))
  selected=()
  used=()
  while [ ${#selected[@]} -lt $pick_count ]; do
    idx=$((RANDOM % num_subs))
    skip=0
    for u in "${used[@]}"; do [ "$u" = "$idx" ] && skip=1; done
    if [ $skip -eq 0 ]; then
      selected+=("${subs[$idx]}")
      used+=("$idx")
    fi
  done

  for sub in "${selected[@]}"; do
    parent_path="$BASE_DIR/$dept/$sub"
    nest_count=$(( (RANDOM % 7) + 1 ))

    for n in $(seq 1 $nest_count); do
      subname="${SUBNAMES[$((RANDOM % ${#SUBNAMES[@]}))]}"
      nest_path="$parent_path/$subname"
      mkdir -p "$nest_path"
      nested_folder_count=$((nested_folder_count + 1))

      num_types=$(( (RANDOM % 4) + 1 ))
      chosen_exts=()
      for t in $(seq 1 $num_types); do
        chosen_exts+=("${EXTENSIONS[$((RANDOM % ${#EXTENSIONS[@]}))]}")
      done

      for ext in "${chosen_exts[@]}"; do
        nest_file_count=$(( (RANDOM % 76) + 5 ))
        IFS=' ' read -ra names <<< "${PREFIXES[$ext]}"
        num_names=${#names[@]}

        for i in $(seq 1 $nest_file_count); do
          prefix="${names[$((RANDOM % num_names))]}"
          filename="${prefix}_$(printf '%04d' $i)_$(date -d "-$((RANDOM % 365)) days" +%Y%m%d 2>/dev/null || date +%Y%m%d).${ext}"
          size_kb=$(random_size)
          total_bytes=$((total_bytes + size_kb * 1024))
          dd if=/dev/urandom of="$nest_path/$filename" bs=1024 count=$size_kb 2>/dev/null
          file_count=$((file_count + 1))
        done
      done
    done
    echo "  $dept/$sub → $nest_count nested subfolders"
  done
done

# =============================================================================
# Phase 3: Set ownership per department
# =============================================================================

echo ""
echo "Setting file ownership per department..."
for dept in "${DEPARTMENTS[@]}"; do
  grp="dept_${dept}"
  usr="usr_${dept}"
  dept_path="$BASE_DIR/$dept"

  if [ -d "$dept_path" ]; then
    chown -R "$usr:$grp" "$dept_path"
    dept_files=$(find "$dept_path" -type f | wc -l)
    echo "  $dept_path → $usr:$grp ($dept_files files)"
  fi
done

# =============================================================================
# Summary
# =============================================================================

total_mb=$((total_bytes / 1024 / 1024))
total_folders=$(find "$BASE_DIR" -type d | wc -l)

echo ""
echo "============================================"
echo "  Generation Complete"
echo "============================================"
echo "  Files created    : $file_count"
echo "  Total folders    : $total_folders"
echo "  Nested subfolders: $nested_folder_count"
echo "  Total size       : ~${total_mb} MB"
echo "  Location         : $BASE_DIR"
echo ""
echo "  Ownership mapping:"
for dept in "${DEPARTMENTS[@]}"; do
  printf "    %-14s → usr_%-14s : dept_%s\n" "$dept" "$dept" "$dept"
done
echo ""
echo "Quick check:"
echo "  find $BASE_DIR -type f | wc -l        # count files"
echo "  find $BASE_DIR -type d | wc -l        # count folders"
echo "  du -sh $BASE_DIR                      # total size"
echo "  find $BASE_DIR -name '*.pdf' | wc -l  # count by type"
echo "  ls -la $BASE_DIR/                     # verify dept ownership"
echo "  tree $BASE_DIR -d | tail -1           # folder tree summary"
echo ""
echo "To remove demo users/groups later:"
echo "  for d in ${DEPARTMENTS[*]}; do userdel usr_\$d 2>/dev/null; groupdel dept_\$d 2>/dev/null; done"
echo ""
echo "To remove the demo data:"
echo "  rm -rf $BASE_DIR"
