# configs/ — documentation

This folder stores config templates and a registry for WW3 namelist sets.

What to use
- `manage_config.sh` — manage configs: `init-baseline`, `new`, `diff`, `--list-templates`, `rebuild-registry`.
- `nml_files_template/` — template namelists to copy when creating configs.
- `REGISTRY.md` — full machine-generated registry (do not edit).
- `REGISTRY_SUMMARY.md` — compact registry summary (useful for automation/AI).

Quick examples

Create a baseline:

```bash
./manage_config.sh init-baseline CARRA2_exp_1
```

Create a new config (interactive) and optionally select templates:

```bash
./manage_config.sh new myconfig --from CARRA2_exp_1 --list-templates
```

Notes
- Templates are only copied when requested (via tags, explicit modified list, or interactive selection).
- Use `./manage_config.sh rebuild-registry` to regenerate `REGISTRY.md` from existing `.config_meta` files.

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
