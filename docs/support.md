# Questlog support

Questlog is a local macOS project-progress companion maintained by jamezzh7. For help, [open an issue](https://github.com/jamezzh7/questlog/issues/new/choose). English, 简体中文 and français are welcome. Include the app version, macOS version, expected result and steps to reproduce. Use the fictional [Orbit sample](../examples/orbit/tasks.md) instead of private project files.

**A project cannot be read.** In the store build, select its folder in the macOS system dialog. An authorized Codex or Claude index does not grant access to project folders. If permissions were reset, use the “Authorize project folder…” button. Moved folders or files may require selecting the folder or checklist again.

**No progress percentage appears.** Connect a Markdown checklist with `- [ ]` / `- [x]` items. Module states and Git activity provide context; they do not invent main acceptance counts. A project without a plan can remain connected while you add one.

**The percentage differs from module completion.** Main acceptance and module work are counted separately. Check the selected source and task scope. See [configuration](configuration.md).

**No finish estimate appears.** Add hour ranges for every remaining main item and your daily availability. The estimate excludes unknown external waiting time.

**Tool discovery is empty.** Explicitly select the tool's registry JSON in the store build, or use Manual → Choose folder. Discovery formats may change; manual connection does not require a supported tool index.

**No Git commits appear.** Git is optional. The store build reads up to five first-parent commits directly with bounded reads. Git metadata outside the selected project, unsupported pack formats or unreadable/corrupt metadata are skipped. The main checklist still works.

**How do I revoke access?** Settings → Reset file permissions forgets folder and index grants. Connections and estimates remain. Remove a connection to delete its tracking settings. Project files are retained. See the [privacy policy](privacy.md).

Do not put credentials, private project text, raw registry files or personal paths in public reports. Use [private security reporting](https://github.com/jamezzh7/questlog/security/advisories/new) for sensitive vulnerabilities.
