# Phase 4 Optimisation — Knowledge Document

> WW3 runtime optimisation beyond compilation flags.
> Benchmark baseline: **324 s** @ 16 nodes × 69 tasks/node × 2 CPUs/task (p3_pgo_avx2_nd).
> Target: **300 s**. Gap: 24 s (−7.4 %).

---

## 1. How WW3 divides work (the compute kernel)

WW3 solves the wave action balance equation on a discretised spectrum:

- **NSPEC = NK × NTH = 32 × 36 = 1152** spectral bins (frequency × direction)
- **~4 200 000 sea points** on the CARRA2 CURV 2869×2869 grid

Each global timestep (DTMAX = 270 s) the model does:

```
for each spectral bin (1152 iterations):          ← outer spectral loop
    gather halo data from neighbours (MPI)
    for each LOCAL sea point (~4200 per rank):    ← inner spatial loop
        propagate(bin, point)                      ← W3XYP2 / W3UNO2
    scatter halo data to neighbours (MPI)
```

Plus source terms (ST4, NL1, BT4…) over all spectral bins per sea point.

The number of times `W3XYP2` is called per global step is:

$$\text{NTLOC} = \left\lceil \frac{\text{DTMAX}}{\text{DTXY}} \right\rceil = \left\lceil \frac{270}{90} \right\rceil = 3$$

---

## 2. Parallelism modes illustrated

### Mode 1 — MPI only (current build, no OpenMP switches)

```
╔══════════════════════════════════════════════════════════════════════════════╗
║  GLOBAL WW3 DOMAIN  (~4 200 000 sea points)                                  ║
║  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐           ║
║  │ Rank  0  │ │ Rank  1  │ │ Rank  2  │ │  ...     │ │ Rank 959 │           ║
║  │ ~4200 pts│ │ ~4200 pts│ │ ~4200 pts│ │          │ │ ~4200 pts│           ║
║  │          │ │          │ │          │ │          │ │          │           ║
║  │ 1 thread │ │ 1 thread │ │ 1 thread │ │ 1 thread │ │ 1 thread │           ║
║  │ CPU #0   │ │ CPU #0   │ │ CPU #0   │ │ CPU #0   │ │ CPU #0   │           ║
║  │ CPU #1   │ │ CPU #1   │ │ CPU #1   │ │ CPU #1   │ │ CPU #1   │           ║
║  │ (async   │ │ (async   │ │ (async   │ │ (async   │ │ (async   │           ║
║  │  MPI     │ │  MPI     │ │  MPI     │ │  MPI     │ │  MPI     │           ║
║  │  thread) │ │  thread) │ │  thread) │ │  thread) │ │  thread) │           ║
║  └──────────┘ └──────────┘ └──────────┘ └──────────┘ └──────────┘           ║
║                                                                              ║
║  Each rank loops over ALL 1152 spectral bins sequentially.                   ║
║  MPI_StartAll → compute 1152 bins → MPI_WaitAll (async thread handles I/O)   ║
╚══════════════════════════════════════════════════════════════════════════════╝

  16 nodes × 60 ranks/node × 2 CPUs/rank = 1920 CPUs total
  CPU #0  →  WW3 computation (sequential over spectral bins + sea points)
  CPU #1  →  Intel MPI async-progress thread (manages inter-node OFI transfers)
```

**Key insight:** Without `cpus-per-task=2`, the async-progress thread and the compute
thread share a single CPU → `MPI_WaitAll` blocks → ~2× slower. This is why 2 CPUs are
needed even though WW3 itself is single-threaded.

---

### Mode 2 — OpenMP only (not used for WW3 at this scale; conceptual)

```
╔══════════════════════════════════════════════════════════════════════════════╗
║  GLOBAL WW3 DOMAIN  (~4 200 000 sea points; hypothetical single-node run)    ║
║  ┌────────────────────────────────────────────────────────────────────────┐  ║
║  │  1 MPI Rank  (owns all sea points)                                      │  ║
║  │                                                                         │  ║
║  │  Inner loop parallelised across threads:                                │  ║
║  │  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐  │  ║
║  │  │OMP thread #0 │ │OMP thread #1 │ │OMP thread #2 │ │OMP thread #3 │  │  ║
║  │  │pts  0–1049   │ │pts 1050–2099 │ │pts 2100–3149 │ │pts 3150–4199 │  │  ║
║  │  └──────────────┘ └──────────────┘ └──────────────┘ └──────────────┘  │  ║
║  └────────────────────────────────────────────────────────────────────────┘  ║
║                                                                              ║
║  No inter-process communication. Scales within a single node.                ║
║  Not practical for 4 200 000 sea points → single-node memory limit.          ║
╚══════════════════════════════════════════════════════════════════════════════╝
```

---

### Mode 3 — Hybrid MPI + OpenMP (OMPH + OMPG; target of Phase 4)

```
╔══════════════════════════════════════════════════════════════════════════════╗
║  GLOBAL WW3 DOMAIN  (~4 200 000 sea points)                                  ║
║  ┌─────────────────────────────────┐  ┌─────────────────────────────────┐   ║
║  │  MPI Rank 0   (~8800 pts)        │  │  MPI Rank 1   (~8800 pts)        │   ║
║  │                                 │  │                                 │   ║
║  │  OMPH — inner sea-point loop:   │  │  OMPH — inner sea-point loop:   │   ║
║  │  ┌─────────────┐┌─────────────┐ │  │  ┌─────────────┐┌─────────────┐ │   ║
║  │  │ OMP thread 0││ OMP thread 1│ │  │  │ OMP thread 0││ OMP thread 1│ │   ║
║  │  │ pts 0–4399  ││pts 4400–8799│ │  │  │ pts 0–4399  ││pts 4400–8799│ │   ║
║  │  │   CPU #0    ││   CPU #1    │ │  │  │   CPU #0    ││   CPU #1    │ │   ║
║  │  └─────────────┘└─────────────┘ │  │  └─────────────┘└─────────────┘ │   ║
║  │  CPU #2 = Intel MPI async thread │  │  CPU #2 = Intel MPI async thread │   ║
║  └─────────────────────────────────┘  └─────────────────────────────────┘   ║
║         ↕ MPI_StartAll / MPI_WaitAll  ↕                                     ║
║  ┌─────────────────────────────────┐                                        ║
║  │  MPI Rank 2  ...                │   16 nodes × 48 ranks/node            ║
║  └─────────────────────────────────┘   = 768 ranks, 3 CPUs each             ║
╚══════════════════════════════════════════════════════════════════════════════╝

  Variant A (run_phase4_omph --step 2):
    16 nodes × 48 ranks/node × 3 CPUs/rank = 2304 CPUs
    CPU #0 + CPU #1 → OMP threads (OMPH inner loop, OMPG source terms)
    CPU #2         → Intel MPI async-progress (keeps MPI_WaitAll fast)
    Node budget: 48 × 3 = 144 CPUs = 100% of Fahrenheit node ✓

  Variant B (run_phase4_omph --step 3):
    16 nodes × 60 ranks/node × 2 CPUs/rank = 1920 CPUs (same as current)
    CPU #0 + CPU #1 → OMP threads
    async progress DISABLED → MPI_WaitAll blocks briefly (no 3rd CPU)
```

---

### What OMPH actually threads in `w3pro2md.F90`

```
W3XYP2 — called NTLOC=3 times per global timestep, once per spectral bin:

  WITHOUT OMPH (current):           WITH OMPH enabled:
  ─────────────────────             ─────────────────────────────────
  DO JSEA = 1, NSEA_local           !$OMP PARALLEL DO PRIVATE(...)
    propagate(JSEA)                 DO JSEA = 1, NSEA_local
  END DO                              propagate(JSEA)
  (1 thread, sequential)            END DO
                                    !$OMP END PARALLEL DO
                                    (2 threads, each handles ~½ points)
```

Similarly, `OMPG` threads the outer spectral loop over source terms in
`w3srcemd.F90`:

```
  WITHOUT OMPG:                     WITH OMPG:
  DO IS = 1, NSPEC                  !$OMP PARALLEL DO
    source_terms(IS)                DO IS = 1, NSPEC
  END DO                              source_terms(IS)
                                    END DO
                                    !$OMP END PARALLEL DO
```

---

## 3. Non-blocking MPI overlap (why async matters)

The main time loop in `w3wavemd.F90` uses a non-blocking pattern:

```fortran
CALL MPI_STARTALL(NRQSG1, IRQSG1, IERR)   ! post inter-node sends (non-blocking)

DO ISPEC = 1, NSPEC                        ! 1152 iterations of local computation
    CALL W3GATH(...)                        !   gather from local halo
    CALL W3XYP2(...)                        !   propagate this spectral bin
    CALL W3SCAT(...)                        !   scatter to local halo
END DO                                     ! ← async-progress thread works here

CALL MPI_WAITALL(NRQSG1, IRQSG1, ...)     ! wait for inter-node transfers to finish
```

The 1152-iteration compute loop is the **overlap window**. While CPU #0 runs
through `W3XYP2`, CPU #1 (async-progress thread) handles the OFI network
transfers. By the time `MPI_WAITALL` is reached, the data is already there →
instant return. Without the async thread, `MPI_WAITALL` blocks waiting for the
network.

---

## 4. Phase 4 experiments summary

| Script | What changes | Recompile | Expected gain |
|--------|-------------|-----------|---------------|
| `run_phase4_mpi_pinning.sh` | `env.sh` only (MPI pin vars) | No | 3–8 % |
| `run_phase4_dtxy.sh` | `ww3_grid.nml` DTXY/DTMAX → re-runs `ww3_grid` | No | up to 33 % |
| `run_phase4_omph.sh` | Switch (`OMPH OMPG`) + CMakeLists (`-qopenmp`) | Yes | 15–30 % |

### 4.1 MPI pinning variants (`run_phase4_mpi_pinning.sh`)

| Variant | Environment variables added | Mechanism |
|---------|---------------------------|-----------|
| `baseline` | none (control) | no change |
| `compact` | `I_MPI_PIN=1`, `I_MPI_PIN_DOMAIN=auto:compact` | pack ranks into fewest NUMA domains → maximise shared L3 |
| `scatter` | `I_MPI_PIN=1`, `I_MPI_PIN_DOMAIN=auto:scatter` | spread ranks across all NUMA domains → maximise total L3 |
| `async_off` | `I_MPI_ASYNC_PROGRESS=0` | disable async-progress thread; measures its value; required as OMPH baseline |

### 4.2 DTXY timestep strategies (`run_phase4_dtxy.sh`)

$$\text{NTLOC} = \left\lceil \frac{\text{DTMAX}}{\text{DTXY}} \right\rceil$$

| Strategy | DTXY (s) | DTMAX (s) | DTKTH (s) | NTLOC | Gain vs ref |
|----------|----------|-----------|-----------|-------|-------------|
| `90_ref` | 90 | 270 | 135 | 3 | reference |
| `120_dtmax240` | 120 | 240 | 120 | 2 | ~33 % fewer prop steps |
| `135_dtmax270` | 135 | 270 | 135 | 2 | ~33 % fewer prop steps |
| `180_dtmax360` | 180 | 360 | 180 | 2 | bolder; verify stability |

**Safety:** Increasing DTXY above the true CFL limit causes instabilities. The 90 s
value is ~90% of the theoretical $T_\text{CFL}$. Run `135_dtmax270` first; check
output fields for NaN or unrealistic wave heights before trusting the result.

### 4.3 OMPH variants (`run_phase4_omph.sh`)

Switch file chain:
1. `REFERENCE_MODEL/WW3/model/bin/switch_dnora` — **never modified**
2. `cp -r REFERENCE_MODEL → MODELS_ROOT/p4_omph/` — full copy
3. `MODELS_ROOT/p4_omph/WW3/model/bin/switch_dnora` — patched (OMPH OMPG added)
4. CMake invoked with `-DSWITCH=<patched copy>`

| Variant | cpus-per-task | tasks/node | OMP_NUM_THREADS | Async progress | Total CPUs |
|---------|--------------|-----------|-----------------|---------------|-----------|
| A (step 2) | 3 | 48 | 2 | ON (CPU #2) | 16×48×3 = 2304 |
| B (step 3) | 2 | 60 | 2 | OFF | 16×60×2 = 1920 |

Fahrenheit node budget: **144 cores/node**
- Variant A: 48 × 3 = 144 = 100 % ✓
- Variant B: 60 × 2 = 120 = 83 % ✓

---

## 5. Key environment variables reference

| Variable | Where set | Purpose |
|----------|-----------|---------|
| `I_MPI_FABRICS=shm:ofi` | `env.sh` (setup.sh) | Use shared memory (intra-node) + OFI (inter-node) |
| `OMP_NUM_THREADS` | `run_shel.job` | Number of OMP threads per MPI rank |
| `I_MPI_PIN` | Phase 4 env.sh patch | Enable process pinning |
| `I_MPI_PIN_DOMAIN` | Phase 4 env.sh patch | Pin domain strategy (compact/scatter) |
| `I_MPI_ASYNC_PROGRESS` | Phase 4 env.sh patch | Enable/disable async-progress thread |

---

## 6. WW3 switch file — OpenMP-relevant tokens

| Token | Fortran guard | What it enables |
|-------|--------------|-----------------|
| `OMPH` | `#ifdef W3_OMPH` | `!$OMP PARALLEL DO` in `w3pro2md.F90` / `w3uno2md.F90` (inner sea-point loop) |
| `OMPG` | `#ifdef W3_OMPG` | `!$OMP PARALLEL DO` in `w3srcemd.F90` / `w3wavemd.F90` (outer source-term loop) |
| `OMP0` | `#ifdef W3_OMP0` | Alternative OMP threading (not tested) |
| `PDLIB` | `#ifdef W3_PDLIB` | Unstructured grid solver (not relevant here) |

None of these are in the current switch (`switch_dnora`). The current content is:
```
NOGRB DIST MPI PR2 UNO FLX0 LN1 ST4 STAB0 NL1 BT4 DB1 MLIM TR0 BS0 IC0 IS0 REF0 WNT1 WNX0 CRT0 CRX0 O0 O1 O2 O2a O2c O4 O5
```

After `run_phase4_omph.sh --step 1`, the copy's switch becomes:
```
NOGRB DIST MPI PR2 UNO FLX0 LN1 ST4 STAB0 NL1 BT4 DB1 MLIM TR0 BS0 IC0 IS0 REF0 WNT1 WNX0 CRT0 CRX0 OMPH OMPG O0 O1 O2 O2a O2c O4 O5
```
