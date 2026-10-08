# MealMate Agent Docs

The working map for coding agents. It sits between the root files (`README.md` for users,
`AGENTS.md` for agent rules, `STYLE.md` for visuals) and the source.

## Reading Order

1. `AGENTS.md` (mandatory before planning, editing, committing or pushing)
2. `AGENTS.local.md` when present
3. `codebase-map.md`
4. `STYLE.md` when touching UI
5. The topic doc below for the area you change
6. The source files that doc points to

## Files

- `brief.md`: product intent, feature scope (v1) and quality bar.
- `codebase-map.md`: source layout, ownership boundaries, where new code goes.
- `auth.md`: server setup, native OIDC flow, password/token fallbacks, credential storage,
  sign-out, DEBUG harness, what needs manual verification.
- `api.md`: `MealieService` structure, adding endpoints, models, errors, dates, caching,
  image URLs, Mealie server quirks.
- `ui.md`: app shell, router and route intents, reusable components, sheets, screen patterns.
- `recipes.md`: recipe lists, detail, cook mode, editor, import, library.
- `shopping-and-mealplan.md`: shopping lists (grouping, add bar, optimistic writes) and the
  meal planner.
- `share-extension.md`: the MealMateShare target, its shared files and verification.
- `development-workflow.md`: build, unit and UI tests, screenshots, simulators, test data.
- `../scripts/README.md`: `screenshot.sh`, `ui-test.sh` and the full route list.
- `supporter.md`: plan (not built) for an optional tip jar.
- `mealie-openapi-v3.28.json`: Mealie's OpenAPI spec. Large: query it with `jq`/`grep`.

## Style of These Docs

Concise and operational: responsibilities, data/control flow, extension points, invariants,
traps, verification. No method-by-method mirrors, no TODO lists without an owner. When a
change alters a flow, boundary, reusable component, setting or verification step, update the
matching doc in the same change. Source beats docs: fix stale docs when you notice them.
