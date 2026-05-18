Suggestions and next improvements for `manage_config.sh`

- Add non-interactive flags: `--tags`, `--modified <files>`, `--all-templates`, `--yes` for scripting/CI.
- Record copied template filenames into `.config_meta` (provenance).
- Add `--dry-run` to preview actions without creating files.
- Add filename normalization/mapping for variants (e.g. `ww3_prnc_ice.nml.sic` → `ww3_prnc_sic.nml`).
- Add unit/smoke tests (`configs/test_manage_config.sh`) and run in CI.
- Run `shellcheck` and enforce style (script already uses strict mode).

Quick commands

```bash
# list templates
./manage_config.sh list-templates

# rebuild registry from existing configs
./manage_config.sh rebuild-registry
```

If you want, I can implement any of the above; I recommend adding `--all-templates` and updating `.config_meta` provenance first.
