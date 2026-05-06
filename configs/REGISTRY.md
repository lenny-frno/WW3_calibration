# WW3 Config Registry

Managed by `manage_config.sh` v1.0.
Do not edit the table or diff sections by hand — use the tool.

## Baseline

**`CARRA2_exp_1/`** — designated baseline at 2026-05-06T15:19:15

All diffs are recorded relative to the direct parent config at creation time.

---

## Config Summary

<!-- schema=v1.0 -->
| Name | Parent | Date | Tags | Description |
|------|--------|------|------|-------------|
| `CARRA2_exp_1` | — | 2026-05-06T15:19:15 | baseline | Baseline configuration |

---


| `everything_betamax_1_65` | `CARRA2_exp_1` | 2026-05-06T15:04:34 | all | all templates; will set BETAMAX=1.65 |


| `everything_betamax_1_75` | `CARRA2_exp_1` | 2026-05-06T15:04:34 | all | all templates; will set BETAMAX=1.75 |


| `with_bounc` | `CARRA2_exp_1` | 2026-05-06T15:04:34 | bounc | add boundary spectrum |


| `with_sic` | `CARRA2_exp_1` | 2026-05-06T15:04:34 | sic | add sic and wind |


| `with_sithick` | `CARRA2_exp_1` | 2026-05-06T15:04:34 | ice | add ice thickness + concentration and wind |

## Config Details


### `everything_betamax_1_65`

> **Parent:** `CARRA2_exp_1`
> **Description:** all templates; will set BETAMAX=1.65

<details>
<summary>Diff vs <code>CARRA2_exp_1</code> at creation time</summary>

```diff
### namelist.nml
--- CARRA2_exp_1/namelist.nml
+++ everything_betamax_1_65/namelist.nml
@@ -1,5 +1,5 @@
 &PRO2 DTIME = 2500. /
 &PRO3 WDTHCG = 1.50, WDTHTH = 1.50 /
-&SIN4 BETAMAX = 1.43 /
+&SIN4 BETAMAX = 1.65 /
 &MISC WCOR1=99, WCOR2=0.0/
 END OF NAMELISTS

### ww3_bounc.nml (new file in everything_betamax_1_65)

### ww3_grid.nml (new file in everything_betamax_1_65)

### ww3_multi.nml (new file in everything_betamax_1_65)

### ww3_prnc_wind.nml (new file in everything_betamax_1_65)


```

</details>

---

### `everything_betamax_1_75`

> **Parent:** `CARRA2_exp_1`
> **Description:** all templates; will set BETAMAX=1.75

<details>
<summary>Diff vs <code>CARRA2_exp_1</code> at creation time</summary>

```diff
### namelist.nml
--- CARRA2_exp_1/namelist.nml
+++ everything_betamax_1_75/namelist.nml
@@ -1,5 +1,5 @@
 &PRO2 DTIME = 2500. /
 &PRO3 WDTHCG = 1.50, WDTHTH = 1.50 /
-&SIN4 BETAMAX = 1.43 /
+&SIN4 BETAMAX = 1.75 /
 &MISC WCOR1=99, WCOR2=0.0/
 END OF NAMELISTS

### ww3_bounc.nml (new file in everything_betamax_1_75)

### ww3_grid.nml (new file in everything_betamax_1_75)

### ww3_multi.nml (new file in everything_betamax_1_75)

### ww3_prnc_wind.nml (new file in everything_betamax_1_75)


```

</details>

---

### `with_bounc`

> **Parent:** `CARRA2_exp_1`
> **Description:** add boundary spectrum

<details>
<summary>Diff vs <code>CARRA2_exp_1</code> at creation time</summary>

```diff
### ww3_bounc.nml (new file in with_bounc)


```

</details>

---

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
