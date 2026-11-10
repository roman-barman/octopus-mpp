# Spec Delta

## ADDED Requirements

### Requirement: Moved files are measured by their destination
The gate SHALL treat a moved or renamed file as one changed file at its destination path, with the lines changed between the source and destination contents. Exclusions SHALL apply to the destination path.

#### Scenario: Change archived without edits
- **GIVEN** a change directory under `openspec/changes/<name>/` on the target branch
- **WHEN** a PR moves it unchanged to `openspec/changes/archive/<date>-<name>/`
- **THEN** the moved files contribute zero files and zero lines

#### Scenario: File moved out of an excluded path
- **WHEN** a PR moves a file from `openspec/changes/archive/` to `openspec/specs/`
- **THEN** the file counts as one changed file at its new path, with any content changes as lines
