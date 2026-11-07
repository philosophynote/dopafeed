@AGENTS.md

## Claude Code 固有
- Skills: `/kick #N` で Unit を Issue から PR まで回し、`/wrapup #PR` で仕上げる（.claude/skills/{kick,wrapup}）。.claude/skills/{claude-api,pwa-ios,kamal-deploy} は必要な Unit のときだけ読む
- Hooks が保存ごとに RuboCop、停止前に `bin/rspec`（system を除く）を回す。赤のまま終わるな
- PR を開く前に `reviewer` サブエージェントに差分を渡し、指摘を直してから開く
