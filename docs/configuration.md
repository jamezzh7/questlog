# Configuration and supported plans

Connect projects through the detail window. Manual configuration is optional; quit the app before editing a configuration file yourself.

## Configuration locations

| Use | Configuration |
| --- | --- |
| Installed app | `~/Library/Application Support/Questlog/projects.json` |
| Development app | `projects.json` beside the source |
| Browser preview | File passed to `server.py --config` |

`projects.example.json` contains an empty project list and no local paths. Settings files contain private project paths and should not be published.

## Plain checklists

```md
# Project tasks
- [x] A1 Set up the workspace
- [ ] A2 Build the core feature
- [ ] A3 Verify the release
```

Tasks use Markdown checkboxes. Stable, unique uppercase IDs are recommended. Without an explicit main scope, checklist items are counted equally. Use `primaryIds` when a file combines top-level acceptance tasks with detailed subtasks.

## Linked module plans

A main checklist can link to a local module plan:

```md
[Module tasks](docs/module-plan.md)
```

```md
# Module plan
## Release module
### RELEASE-01: Prepare the release
- Status: in progress
- Priority: P1
- Acceptance: Verify a clean installation
```

Questlog also supports Task/Status tables and module checkbox lists. Explicit status text is preserved. A ready task is not automatically active; delivery or partial completion does not automatically complete parent acceptance.

Local linked-plan reads stay within the project: at most eight linked files, two link levels, and 2 MB per document. External links, archived plans, and fenced examples are excluded. The [Orbit fixture](../examples/orbit/tasks.md) contains a main checklist and linked modules.

## Example project configuration

Replace the sample root with an absolute directory on your Mac. For the included fixture, use the absolute path to `examples/orbit`.

```json
{
  "version": 1,
  "language": "auto",
  "projects": [
    {
      "id": "orbit",
      "name": "Orbit",
      "root": "/absolute/path/to/orbit",
      "tasksFile": "tasks.md",
      "primaryIds": ["A1", "A2", "A3", "A4", "A5"],
      "hoursPerDay": 4,
      "estimates": {"A4": [4, 6], "A5": [2, 4]}
    }
  ]
}
```

`language` accepts `auto`, `en`, `zh`, or `fr`. `primaryIds` selects the main denominator. `estimates` maps remaining main task IDs to minimum/maximum hours; the UI provides validation and an editor. `dependencies` can map IDs to human-written dependency notes.

Each selected source retains its own scope, dependencies, and estimates. Prefer the UI source picker when switching between plans. Missing sources produce an error and a recovery action; absent plans display “—” instead of invented progress.
