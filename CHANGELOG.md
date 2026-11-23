# Changelog

## 0.0.1

First release.

- `mix ecto.doctor` with 14 checks of schemas and changesets against PostgreSQL, MySQL and SQLite.
- N+1 detection in tests, requests, LiveView events and Oban jobs with a baseline file.
- `EctoDoctor.Plug` for a dev footer listing a page's N+1 queries.
- Text, JSON, SARIF and GitHub annotation output.
- `--fix` and `--apply` for migrations and `mix ecto_doctor.install`.
