# Workspace Local Root and Zed Design

## Problem

Repositories are currently stored as remote associations only. A separate clone service exists, but adding a repository does not invoke it and the visible Open in IDE action bypasses its flow. IDE launch generates a VS Code workspace file and relies on the operating system default editor, which can open Kiro rather than Zed.

## Design

Each workspace owns one optional `localRootPath`. The app resolves an unset root to `~/Developer/CockpitDev/<workspace-name>` and persists that path when it first needs local files. Each added repository is cloned into a child folder of that root using its GitLab repository name, and its existing `localPath` records that child directory.

Adding a repository is atomic from the user's perspective: GitLab validation succeeds, the clone completes under the workspace root, then the repository model is persisted. If cloning fails, the repository is not added and the error remains visible for retry.

Opening a workspace in the IDE ensures any previously remote-only repositories are cloned into the same root, then opens the single workspace root directory in Zed. The app does not generate or open a `.code-workspace` file for this flow.

## UI

The Repositories settings header shows the workspace local root. New repository rows show the child checkout path after successful cloning. The add-repository sheet explains that adding also clones into the workspace root.

## Errors And Compatibility

Existing workspaces can have no root path and repositories without local paths; opening in Zed repairs that state by cloning missing repositories under the resolved root. Existing linked repository paths remain available until the user opens the workspace or adds new repositories.

## Verification

Tests cover persisted workspace root, repository placement beneath it, and launching Zed with the root directory rather than a generated workspace file. Existing clone and repository management tests remain in scope.
