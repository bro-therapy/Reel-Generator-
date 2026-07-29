# Art Cleanup TODO

The included images are approved first-playtest assets and references. Log
specific issues here during implementation rather than silently generating or
painting replacements.

| Priority | Asset | Frame/state | Problem | Temporary handling | Final cleanup |
|---|---|---|---|---|---|
| High |  |  | collision/readability/pivot issue |  |  |
| Medium |  |  | consistency issue |  |  |
| Low |  |  | polish issue |  |  |

## Known first-pass risks

- Normalize foot/ground pivots before chaining hero locomotion frames.
- Verify chain and bell weights stay inside each First Bell cell.
- Confirm transparent mattes do not show green fringe under bloom.
- Keep friendly violet effects below hostile red telegraphs in draw priority.
- Use environment art as a visual reference; build navigable geometry in 3D.
- Rebuild generated UI screens with native Godot Controls rather than using
  flattened mockups as interactive menus.
