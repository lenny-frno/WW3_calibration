# configs/ — documentation

This folder contains configuration templates and a registry for WW3 namelist
sets used by experiments. There are two kinds of documents here:

- `REGISTRY.md` — machine-updated registry of named configs (do not edit).
- `README.md` — this human-facing documentation (you are reading it).

Contents
- `manage_config.sh` — CLI to manage config variants (`init-baseline`, `new`, `diff`).
- `nml_files_template/` — canonical template namelists to copy when creating configs.
- `<config>/` — per-config folders created by `manage_config.sh`.

Quick examples

Create a baseline from an existing folder:

```bash
./manage_config.sh init-baseline CARRA2_exp_1
```

Create a new config branching from the baseline (interactive):

```bash
./manage_config.sh new with_ice
```

Notes about templates
- When a parent config lacks optional namelists (ice, boundary, etc.), the
  tool can copy appropriate files from `nml_files_template/` into the new
  config only when requested (via tags or explicit modified list).
- The registry of created configs is stored in `REGISTRY.md` and is updated
  automatically by `manage_config.sh`.

If you want me to: I can (a) add non-interactive flags (`--tags`,
`--modified`, `--yes`), (b) add a `--list-templates` command, or (c)
improve template filename mapping. Which would you like next?

### `with_sic`

> **Parent:** `CARRA2_exp_1`
> **Description:** add sic and wind

<details>
<summary>Diff vs <code>CARRA2_exp_1</code> at creation time</summary>

```diff
### ww3_prnc_wind.nml (new file in with_sic)


```

</details>

---

### `with_sithick`

> **Parent:** `CARRA2_exp_1`
> **Description:** add ice thickness + concentration and wind

<details>
<summary>Diff vs <code>CARRA2_exp_1</code> at creation time</summary>

```diff
### ww3_prnc_wind.nml (new file in with_sithick)


```

</details>

---

### `with_bounc`

> **Parent:** `CARRA2_exp_1`
> **Description:** add boundary spectrum

<details>
<summary>Diff vs <code>CARRA2_exp_1</code> at creation time</summary>

```diff
(No differences at creation time — namelists are identical to parent.
Edit the namelists in with_bounc/ then re-run:
  ./manage_config.sh diff with_bounc)
```

</details>

---

### `everything_betamax_1_75`

> **Parent:** `CARRA2_exp_1`
> **Description:** all templates; will set BETAMAX=1.75

<details>
<summary>Diff vs <code>CARRA2_exp_1</code> at creation time</summary>

```diff
### ww3_prnc_wind.nml (new file in everything_betamax_1_75)


```

</details>

---

### `everything_betamax_1_65`

> **Parent:** `CARRA2_exp_1`
> **Description:** all templates; will set BETAMAX=1.65

<details>
<summary>Diff vs <code>CARRA2_exp_1</code> at creation time</summary>

```diff
### ww3_prnc_wind.nml (new file in everything_betamax_1_65)


```

</details>

---
