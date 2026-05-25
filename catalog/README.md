# Catalog Demo

Scripts for generating a realistic file catalog on a WEKA filesystem, suitable for demonstrating WEKA's namespace, metadata, and data management capabilities.

## generate_catalog_demo.sh

Populates a WEKA filesystem with a deep, realistic directory structure across 10 simulated departments. Useful for showcasing file catalog features, namespace scale, and per-user/group data ownership.

### What it creates

| Category | Detail |
|---|---|
| Departments | finance, engineering, marketing, hr, legal, sales, operations, research, it, executive |
| Top-level folders | 50 (5 per department) |
| Nested subfolders | 1–7 levels deep in randomly selected subfolders |
| File types | `.txt` `.pdf` `.xls` `.doc` `.jpg` `.png` `.csv` `.json` `.xml` `.log` |
| Files per type | 40–2,000 (random) |
| File sizes | 20 KB – 2 MB (weighted toward ~100 KB) |
| OS users/groups | One system user (`usr_<dept>`) and group (`dept_<dept>`) per department |
| Ownership | Each department tree is `chown`-ed to its corresponding user and group |

### Requirements

- **WEKA client** installed and a WEKA filesystem mounted via `mount -t wekafs`
- Run as **root** (`sudo`) — needed to create system users/groups and set ownership
- Linux OS (tested on RHEL/Rocky/Ubuntu)

### Usage

```bash
sudo ./generate_catalog_demo.sh
```

The script will:

1. Prompt you for the target directory (e.g. `/mnt/weka/catalog_demo`)
2. Verify the path sits on a mounted WEKA filesystem (`mount -t wekafs`) — exits with an error if it does not
3. Create department users and groups
4. Build the full folder hierarchy and generate files
5. Set per-department ownership

### Example session

```
Enter the target directory for demo files (must be on a mounted WEKA filesystem): /mnt/weka/catalog_demo

Checking that '/mnt/weka/catalog_demo' is on a mounted WEKA filesystem...
  OK — WEKA filesystem confirmed.

Base directory : /mnt/weka/catalog_demo
...
Generation Complete
  Files created    : 8342
  Total folders    : 312
  Total size       : ~742 MB
  Location         : /mnt/weka/catalog_demo
```

### Cleanup

Remove generated files:

```bash
rm -rf /mnt/weka/catalog_demo   # adjust path to match what you entered
```

Remove demo OS users and groups:

```bash
for d in finance engineering marketing hr legal sales operations research it executive; do
  userdel usr_${d} 2>/dev/null
  groupdel dept_${d} 2>/dev/null
done
```
