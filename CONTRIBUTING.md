# Contributing to Questlog

Bug fixes, translations, documentation, and focused feature proposals are welcome. For a substantial change, open an issue to discuss the behavior and scope first.

## Run locally

Follow [the development guide](docs/development.md). Python uses only the standard library; Node.js is needed for JavaScript checks, and macOS Command Line Tools are needed for native builds.

Use an isolated configuration and fictional project fixtures. Do not commit `projects.json`, runtime settings, application bundles, screenshots of personal projects, or tool registry files. Do not use another person's project as writable test data.

## Before opening a pull request

- Explain the problem, resulting behavior, and how you verified it.
- Keep changes focused. Add meaningful regression coverage for changed parsing, calculations, or API behavior.
- Run the Python tests and JavaScript checks in the development guide.
- For UI changes, check the native app and detail view, including English, Simplified Chinese, French, minimum window size, keyboard focus, and reduced-motion behavior when relevant.
- Describe checks you could not run. Do not claim native behavior from a browser screenshot alone.

## Design and data boundaries

- Keep the native widget small and the detail service on demand.
- Preserve the distinction between main acceptance progress, module states, milestones, and Git activity.
- Keep project sources read-only. Save preferences only in Questlog's configuration.
- Confine Markdown reads to the connected project and retain bounded traversal.
- Explain the need before introducing background services or dependencies.

## Translations

Interface strings live in `public/i18n.js` and `Questlog.swift`. Keep placeholders intact, update both web and native interfaces, and run `node --test tests/test_i18n.cjs`. The build extracts the shared error catalog for native use. Leave project-authored text unchanged.

## Reporting bugs

Include your macOS version, chip architecture, Questlog version, Python version, expected behavior, and reproduction steps. Prefer a small fictional Markdown example. Remove personal paths, project names, and sensitive content from logs and screenshots.

For security concerns, follow [SECURITY.md](SECURITY.md) instead of posting exploit details in an ordinary bug report.
