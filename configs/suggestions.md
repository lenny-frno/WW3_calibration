Suggestions and next improvements for manage_config.sh

- Add non-interactive flags: --tags, --modified, --yes, --from to allow scripting without prompts.
- Add explicit --all-templates flag to include every file from nml_files_template.
- Improve filename mapping for variant files (e.g. ww3_prnc_ice.nml.sic -> ww3_prnc_sic.nml) and normalize names.
- Record which template files were copied into .config_meta for provenance.
- Add a dry-run mode that prints actions without copying files.
- Add unit/smoke tests under configs/test_manage_config.sh and run them in CI.
- Run shellcheck for linting and set bash strict mode at top (already set).
